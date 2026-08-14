#!/usr/bin/env python3
"""Eve retrieval-recall eval — does the store give the memory back?

The sibling suite in `evals/` measures whether an agent lies about what a
corpus says. This one measures the step before that: whether the right memory
is handed to the agent at all. They fail differently and they fail
independently, so they are scored separately.

Four outcomes are counted, and they are not the same failure:

  MISS       the target existed and nothing came back. Costs you the memory.
             Recoverable — the agent asks, or `eve gaps` shows the whiff later.
  MISRANK    the right memory came back, but under a wrong one. Mild: the recall
             hook injects the whole block, so the agent still sees it.
  MISFIRE    something came back and the right memory is NOWHERE in the block.
             This is the dangerous one and it gets its own number. The agent is
             handed only wrong memories, with exactly the authority a right one
             would have carried, and nothing in the block to contradict them.
  FALSE POS  a query nothing in the store answers returned something anyway.
             The same damage as a misfire, counted with it, shown separately
             because a store that answers everything answers nothing.

The distinction between MISRANK and MISFIRE is the whole reason precision gets
its own gate. A change that lowers the relevance gate to lift recall will lift
MISFIRE at the same time, and a single recall number would call that progress.

Everything here is deterministic: fixed fixture, fixed queries, a ranker that
sorts on (score desc, id asc). Two runs over an unchanged tree produce identical
bytes, which is what lets the gate compare exactly instead of within a
tolerance.

Exit 0 pass · 1 regression against the baseline · 2 harness error.
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from lexicon import Store, load_stopwords, tokenise  # noqa: E402

ROOT = HERE.parent.parent
ANSWERABLE = ("verbatim", "paraphrase", "disjoint")
TIERS = ANSWERABLE + ("out-of-scope",)

# Config keys eve reads from the environment. They are stripped from the child
# so the run measures the SHIPPED DEFAULTS, not whatever the operator's shell
# happens to export. The gate is the thing under test; it must not be an input.
EVE_ENV_KEYS = (
    "EVE_MIN_SCORE",
    "EVE_RECALL_LIMIT",
    "EVE_SNIPPET_CHARS",
    "EVE_CANDIDATE_CAP",
    "EVE_MAX_LINES",
    "EVE_DISABLE",
    "EVE_HOME",
)


class HarnessError(Exception):
    pass


# ---------------------------------------------------------------------------
# running eve
# ---------------------------------------------------------------------------


def child_env(fixture):
    env = {k: v for k, v in os.environ.items() if k not in EVE_ENV_KEYS}
    env["EVE_HOME"] = str(fixture)
    env["LC_ALL"] = "C"  # byte-deterministic sort, same reason bin/eve sets it
    return env


def search(eve, fixture, query, limit, show_all=False):
    """Return [(score, id), ...] in rank order. Empty list means nothing cleared."""
    cmd = [str(eve), "search", "--query", query, "--limit", str(limit), "--format", "tsv"]
    if show_all:
        cmd.append("--all")
    try:
        p = subprocess.run(
            cmd, env=child_env(fixture), capture_output=True, text=True, timeout=60
        )
    except subprocess.TimeoutExpired as exc:
        raise HarnessError(f"eve timed out on query {query!r}") from exc
    except OSError as exc:
        raise HarnessError(f"cannot run {eve}: {exc}") from exc
    if p.returncode != 0:
        raise HarnessError(
            f"eve exited {p.returncode} on query {query!r}: {p.stderr.strip()}"
        )
    out = []
    for line in p.stdout.splitlines():
        if not line.strip():
            continue
        # Only the first two fields are read. A snippet containing a literal tab
        # would shift everything after it; score and id are before that point.
        parts = line.split("\t")
        if len(parts) < 2:
            continue
        try:
            out.append((int(parts[0]), parts[1]))
        except ValueError:
            continue
    return out


def shipped_gate(eve):
    """The default EVE_MIN_SCORE, read out of bin/eve so the header cannot go stale."""
    try:
        text = Path(eve).read_text(encoding="utf-8", errors="replace")
    except OSError:
        return None
    m = re.search(r"^\s*_d_minscore=(\d+)\s*$", text, re.M)
    return int(m.group(1)) if m else None


# ---------------------------------------------------------------------------
# fixture check
# ---------------------------------------------------------------------------


def check_fixture(spec, store, stopwords):
    """Assert every committed tier still matches the measured overlap.

    This is the guard that keeps the tier names honest. Without it, editing one
    word of a fixture memory could turn a `disjoint` query into a `paraphrase`
    one, the disjoint score would rise, and the improvement would be an artifact
    of the fixture rather than of the ranker.
    """
    problems = []
    seen = set()
    for q in spec["queries"]:
        if q["id"] in seen:
            problems.append(f"{q['id']}: duplicate query id")
        seen.add(q["id"])
        if q["tier"] not in TIERS:
            problems.append(f"{q['id']}: unknown tier {q['tier']!r}")
            continue
        if q["tier"] == "out-of-scope":
            if q.get("target"):
                problems.append(f"{q['id']}: out-of-scope query must have a null target")
            continue
        target = q.get("target")
        if not target:
            problems.append(f"{q['id']}: tier {q['tier']} needs a target")
            continue
        if target not in store.memories:
            problems.append(f"{q['id']}: target {target!r} is not in the fixture store")
            continue
        toks = tokenise(q["query"], stopwords)
        if not toks:
            problems.append(f"{q['id']}: every token was dropped as a stopword")
            continue
        measured = store.overlap(target, toks)["tier"]
        if measured != q["tier"]:
            problems.append(
                f"{q['id']}: registered tier {q['tier']!r} but measures {measured!r} "
                f"(query {q['query']!r} -> {target})"
            )
    return problems


# ---------------------------------------------------------------------------
# scoring
# ---------------------------------------------------------------------------


def grade(spec, eve, fixture, want_detail=True):
    rows = []
    for q in spec["queries"]:
        hits = search(eve, fixture, q["query"], 3)
        ids = [h[1] for h in hits]
        target = q.get("target")
        r = {
            "id": q["id"],
            "tier": q["tier"],
            "query": q["query"],
            "target": target,
            "hits": hits,
            "empty": not hits,
        }
        if q["tier"] == "out-of-scope":
            r["outcome"] = "false-positive" if hits else "silent"
            r["misfire"] = bool(hits)
            r["misrank"] = False
            r["hit1"] = False
            r["hit3"] = False
        else:
            r["hit1"] = bool(ids) and ids[0] == target
            r["hit3"] = target in ids
            # MISFIRE is "returned something, and the right memory is not in it"
            # — not merely "rank 1 was wrong". The hook injects the whole block,
            # so a target sitting at rank 3 was still delivered.
            r["misfire"] = bool(ids) and not r["hit3"]
            r["misrank"] = r["hit3"] and not r["hit1"]
            if r["hit1"]:
                r["outcome"] = "hit@1"
            elif r["misrank"]:
                r["outcome"] = "misrank"
            elif r["misfire"]:
                r["outcome"] = "misfire"
            else:
                r["outcome"] = "miss"
        # The diagnostic pass: gate off, wide limit, so a maintainer can see the
        # score the target actually earned instead of only that it lost.
        if want_detail and (r["misfire"] or r["misrank"] or (target and not r["hit3"])):
            allhits = search(eve, fixture, q["query"], 50, show_all=True)
            r["all"] = allhits
            r["target_score"] = next((s for s, i in allhits if i == target), None)
        rows.append(r)
    return rows


def tally(rows):
    per = {}
    for t in TIERS:
        sub = [r for r in rows if r["tier"] == t]
        per[t] = {
            "n": len(sub),
            "hit1": sum(1 for r in sub if r["hit1"]),
            "hit3": sum(1 for r in sub if r["hit3"]),
            "empty": sum(1 for r in sub if r["empty"]),
            "misfire": sum(1 for r in sub if r["misfire"]),
            # Reported, never gated. misrank is exactly hit3 - hit1, so gating it
            # would be the same constraint written twice — and the second copy
            # would eventually disagree with the first.
            "misrank": sum(1 for r in sub if r["misrank"]),
        }
    ans = [r for r in rows if r["tier"] in ANSWERABLE]
    return {
        "per_tier": per,
        "overall": {
            "n": len(rows),
            "answerable": len(ans),
            "hit1": sum(1 for r in ans if r["hit1"]),
            "hit3": sum(1 for r in ans if r["hit3"]),
            "empty": sum(1 for r in rows if r["empty"]),
            "misfire": sum(1 for r in rows if r["misfire"]),
            "misrank": sum(1 for r in rows if r["misrank"]),
        },
    }


# ---------------------------------------------------------------------------
# reporting
# ---------------------------------------------------------------------------


def pct(n, d):
    return "  -  " if not d else f"{100.0 * n / d:4.0f}%"


def report(rows, t, eve, fixture, store, gate, verbose):
    w = sys.stdout.write
    w("\neve retrieval-recall eval\n")
    w(f"  store    {rel(fixture)}  ({len(store.memories)} memories)\n")
    w(f"  binary   {rel(eve)}\n")
    w(f"  gate     EVE_MIN_SCORE={gate if gate is not None else '?'} (shipped default)\n")
    w(f"  queries  {t['overall']['n']}\n\n")

    rule = "-" * 72
    w(f"  {'tier':<13}{'n':>3}{'recall@1':>14}{'recall@3':>14}{'miss':>7}{'misrank':>9}{'MISFIRE':>9}\n")
    w(f"  {rule}\n")
    for name in ANSWERABLE:
        s = t["per_tier"][name]
        w(
            f"  {name:<13}{s['n']:>3}"
            f"{s['hit1']:>8} {pct(s['hit1'], s['n'])}"
            f"{s['hit3']:>8} {pct(s['hit3'], s['n'])}"
            f"{s['empty']:>7}{s['misrank']:>9}{s['misfire']:>9}\n"
        )
    o = t["overall"]
    w(f"  {rule}\n")
    w(
        f"  {'answerable':<13}{o['answerable']:>3}"
        f"{o['hit1']:>8} {pct(o['hit1'], o['answerable'])}"
        f"{o['hit3']:>8} {pct(o['hit3'], o['answerable'])}"
        f"{o['empty'] - t['per_tier']['out-of-scope']['empty']:>7}"
        f"{o['misrank']:>9}{o['misfire'] - t['per_tier']['out-of-scope']['misfire']:>9}\n"
    )
    s = t["per_tier"]["out-of-scope"]
    w(
        f"  {'out-of-scope':<13}{s['n']:>3}"
        f"{'(nothing to recall)':>28}{s['empty']:>7}{'':>9}{s['misfire']:>9}\n"
    )
    w(f"  {rule}\n\n")
    w(
        f"  MISFIRE RATE  {str(o['misfire']) + '/' + str(o['n']):>6}"
        f"  {pct(o['misfire'], o['n'])}   the right memory absent from a non-empty block\n"
    )
    w(
        f"  empty rate    {str(o['empty']) + '/' + str(o['n']):>6}"
        f"  {pct(o['empty'], o['n'])}   {s['empty']} of them the out-of-scope controls, correctly silent\n\n"
    )

    misfires = [r for r in rows if r["misfire"]]
    if misfires:
        w("MISFIRES — only wrong memories in the block, at full authority\n")
        w(rule + "\n")
        for r in misfires:
            w(f"  [{r['id']} {r['tier']}] {r['query']!r}\n")
            for sc, mid in r["hits"]:
                w(f"      returned  {sc:>4}  {mid}\n")
            if r["target"]:
                ts = r.get("target_score")
                if ts is None:
                    w(f"      wanted     ---  {r['target']}  (not a candidate: no token in the file)\n")
                else:
                    w(f"      wanted    {ts:>4}  {r['target']}  (needed {gate} to be shown)\n")
            else:
                w("      wanted     ---  nothing; no memory in the store answers this\n")
            w("\n")

    misranks = [r for r in rows if r["misrank"]]
    if misranks:
        w("MISRANKED — right memory returned, but under a wrong one\n")
        w(rule + "\n")
        for r in misranks:
            got = ", ".join(f"{mid}@{sc}" for sc, mid in r["hits"])
            w(f"  [{r['id']}] {r['query']!r}\n      {got}\n")
        w("\n")

    if verbose:
        w("EVERY QUERY\n")
        w("-" * 74 + "\n")
        for r in rows:
            mark = {
                "hit@1": "ok",
                "misrank": "rank",
                "silent": "ok",
                "miss": "miss",
                "misfire": "WRONG",
                "false-positive": "WRONG",
            }[r["outcome"]]
            top = f"{r['hits'][0][1]}@{r['hits'][0][0]}" if r["hits"] else "-"
            w(f"  {mark:<6}{r['id']:<5}{top:<46}{r['query']!r}\n")
        w("\n")


def rel(p):
    try:
        return str(Path(p).resolve().relative_to(ROOT))
    except ValueError:
        return str(p)


# ---------------------------------------------------------------------------
# the gate
# ---------------------------------------------------------------------------


def compare(t, base):
    """Regression rules, stated in one place.

    Recall may not fall and misfires may not rise. Both directions matter: a
    change that lifts paraphrase recall by dropping the gate will raise the
    misfire count, and this is the check that refuses to call that an
    improvement.
    """
    regressions = []
    improvements = []
    for name in ANSWERABLE:
        cur, old = t["per_tier"][name], base["per_tier"][name]
        if cur["n"] != old["n"]:
            regressions.append(
                f"{name}: query count changed {old['n']} -> {cur['n']}; "
                f"the baseline describes a different suite"
            )
        for k in ("hit1", "hit3"):
            if cur[k] < old[k]:
                regressions.append(f"{name}: {k} fell {old[k]} -> {cur[k]}")
            elif cur[k] > old[k]:
                improvements.append(f"{name}: {k} rose {old[k]} -> {cur[k]}")
    for name in TIERS:
        cur, old = t["per_tier"][name], base["per_tier"][name]
        if cur["misfire"] > old["misfire"]:
            regressions.append(
                f"{name}: misfires rose {old['misfire']} -> {cur['misfire']} "
                f"(a non-empty block with the right memory nowhere in it)"
            )
        elif cur["misfire"] < old["misfire"]:
            improvements.append(f"{name}: misfires fell {old['misfire']} -> {cur['misfire']}")
    if t["overall"]["misfire"] > base["overall"]["misfire"]:
        regressions.append(
            f"overall: misfires rose {base['overall']['misfire']} -> {t['overall']['misfire']}"
        )
    return regressions, improvements


# ---------------------------------------------------------------------------


def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="evals/recall/run.sh",
        description="Measure whether the memory store gives the right memory back.",
    )
    ap.add_argument("--eve", default=None, help="eve binary to test (default: bin/eve in this repo)")
    ap.add_argument("--questions", default=str(HERE / "questions.json"))
    ap.add_argument("--fixture", default=str(HERE / "fixture-store"))
    ap.add_argument("--baseline", default=str(HERE / "baseline.json"))
    ap.add_argument("--update-baseline", action="store_true", help="write the current result as the new floor")
    ap.add_argument("--no-gate", action="store_true", help="report only; never exit non-zero on regression")
    ap.add_argument("--json", action="store_true", help="machine-readable scorecard on stdout")
    ap.add_argument("-v", "--verbose", action="store_true", help="print every query and what came back")
    args = ap.parse_args(argv)

    eve = Path(args.eve) if args.eve else ROOT / "bin" / "eve"
    fixture = Path(args.fixture)

    try:
        if not eve.exists():
            raise HarnessError(f"no eve binary at {eve}")
        if not os.access(eve, os.X_OK):
            raise HarnessError(f"{eve} is not executable")
        memdir = fixture / "memory"
        if not memdir.is_dir():
            raise HarnessError(f"no fixture store at {memdir}")
        if (fixture / "config").exists():
            raise HarnessError(
                f"{fixture / 'config'} exists; the fixture must carry no config "
                f"or the run measures that file instead of the shipped defaults"
            )

        spec = json.loads(Path(args.questions).read_text(encoding="utf-8"))
        store = Store(memdir)
        stopwords = load_stopwords(ROOT / "bin" / "eve")

        problems = check_fixture(spec, store, stopwords)
        if problems:
            sys.stderr.write("fixture check FAILED — the query set no longer describes the store:\n")
            for p in problems:
                sys.stderr.write(f"  {p}\n")
            sys.stderr.write(
                "\nA tier is a measured property, not a label. Re-register the query\n"
                "(evals/recall/questions.json) or revert the fixture edit.\n"
            )
            return 2

        rows = grade(spec, eve, fixture)
        t = tally(rows)
    except HarnessError as exc:
        sys.stderr.write(f"evals/recall: {exc}\n")
        return 2
    except (OSError, ValueError, KeyError) as exc:
        sys.stderr.write(f"evals/recall: harness error: {exc}\n")
        return 2

    if args.json:
        print(json.dumps(t, indent=2, sort_keys=True))
    else:
        report(rows, t, eve, fixture, store, shipped_gate(eve), args.verbose)

    bpath = Path(args.baseline)
    if args.update_baseline:
        payload = dict(t)
        payload["_note"] = (
            "Measured floor, not a target. run.sh fails if recall falls below "
            "this or misfires rise above it. Regenerate with --update-baseline "
            "and say in the commit message what changed and why."
        )
        bpath.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        sys.stdout.write(f"baseline written to {rel(bpath)}\n")
        return 0

    if not bpath.exists():
        sys.stderr.write(
            f"\nno baseline at {rel(bpath)}. Record the current result with:\n"
            f"  sh evals/recall/run.sh --update-baseline\n"
        )
        return 2

    try:
        base = json.loads(bpath.read_text(encoding="utf-8"))
        regressions, improvements = compare(t, base)
    except (OSError, ValueError, KeyError) as exc:
        sys.stderr.write(f"evals/recall: cannot read baseline {rel(bpath)}: {exc}\n")
        return 2

    if improvements:
        sys.stdout.write("IMPROVED against the baseline:\n")
        for i in improvements:
            sys.stdout.write(f"  + {i}\n")
    if regressions:
        sys.stdout.write("\nREGRESSED against the baseline:\n")
        for r in regressions:
            sys.stdout.write(f"  - {r}\n")
        sys.stdout.write(
            "\nFAIL. Retrieval got worse, or it traded precision for recall.\n"
            "If the new behaviour is deliberate, re-record the floor with\n"
            "  sh evals/recall/run.sh --update-baseline\n"
            "and say in the commit message what you traded away.\n"
        )
        return 0 if args.no_gate else 1

    if improvements:
        sys.stdout.write(
            "\nPASS, and better than the floor. Lock it in so it cannot silently\n"
            "slide back:  sh evals/recall/run.sh --update-baseline\n"
        )
    else:
        sys.stdout.write("\nPASS — no regression against the committed baseline.\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
