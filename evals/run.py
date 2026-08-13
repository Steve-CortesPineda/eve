#!/usr/bin/env python3
"""Eve hallucination eval — runner.

    python3 evals/run.py                      # offline, reference answerer
    python3 evals/run.py --answerer naive     # a real but ungrounded retriever
    python3 evals/run.py --answerer bad -v    # a deliberately broken answerer
    python3 evals/run.py --cmd './my-agent'   # your own agent

The answerer is always a subprocess. It receives ONE question as JSON on stdin
and writes its answer to stdout. The built-in stubs use exactly the same
interface as a real agent would, so the offline path is not a special case that
can rot while nobody is looking.

What the answerer is told, deliberately: the question id, the question text, and
the absolute path of the KB. It is NOT told the category, the expected answer,
the expected citations, or whether the question is a trap. Leaking any of that
would make the suite measure nothing.

No third-party imports. Python 3.8+.
"""

import argparse
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from kb import KB                                    # noqa: E402
from scoring import (VERDICTS, DEFAULT_GATES, aggregate,  # noqa: E402
                     check_gates, judge, parse_response)

BUILTIN_ANSWERERS = {
    "reference": "reference.py",
    "naive": "naive_keyword.py",
    "bad": "bad.py",
}


# --------------------------------------------------------------------------

def load_questions(path):
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
    if "questions" not in data:
        raise ValueError("%s has no 'questions' array" % path)
    return data


def build_command(args):
    if args.cmd:
        return args.cmd, "custom"
    name = args.answerer
    if name not in BUILTIN_ANSWERERS:
        raise SystemExit("unknown answerer %r (choose from %s, or pass --cmd)"
                         % (name, ", ".join(sorted(BUILTIN_ANSWERERS))))
    script = os.path.join(HERE, "answerers", BUILTIN_ANSWERERS[name])
    if not os.path.isfile(script):
        raise SystemExit("missing built-in answerer: %s" % script)
    return [sys.executable, script], name


def ask(command, payload, timeout):
    """Run the answerer once. Returns (stdout, error_or_None)."""
    blob = json.dumps(payload)
    env = dict(os.environ)
    env["EVE_EVAL_KB"] = payload["kb_root"]
    env["EVE_EVAL_QUESTION_ID"] = payload["id"]
    try:
        proc = subprocess.run(
            command,
            input=blob,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            timeout=timeout,
            env=env,
            shell=isinstance(command, str),
        )
    except subprocess.TimeoutExpired:
        return "", "timeout after %ss" % timeout
    except OSError as exc:
        return "", "could not run answerer: %s" % exc
    if proc.returncode != 0:
        detail = (proc.stderr or "").strip().splitlines()
        tail = detail[-1] if detail else "no stderr"
        return proc.stdout or "", "exit %d: %s" % (proc.returncode, tail)
    return proc.stdout or "", None


# --------------------------------------------------------------------------

def pct(value):
    return "  n/a" if value is None else "%5.1f%%" % (100.0 * value)


def render(summary, results, meta, gates_report, passed, verbose):
    out = []
    add = out.append

    add("Eve hallucination eval")
    add("  fixture KB    %s  (%d documents)" % (meta["kb_root"], meta["n_docs"]))
    add("  questions     %s  (%d questions, reference date %s)"
        % (meta["questions_path"], summary["n_questions"], meta["reference_date"]))
    add("  answerer      %s  [%s]" % (meta["answerer"], meta["command"]))
    if meta["errors"]:
        add("  ERRORS        %d question(s) the answerer crashed or timed out on."
            % meta["errors"])
        add("                The run fails on this alone; --allow-answerer-errors "
            "to override.")
    add("")

    add("Verdicts")
    labels = {
        "grounded": "grounded          answered, correct, cited, citation checks out",
        "unsupported": "unsupported       correct but uncited, or stale and undated",
        "hallucinated": "hallucinated      asserted what the KB does not hold",
        "missed": "missed            abstained on something the KB answers",
        "abstained_correct": "abstained_correct declined a question with no answer in the KB",
    }
    for verdict in VERDICTS:
        add("  %3d  %s" % (summary["verdicts"][verdict], labels[verdict]))
    add("")

    add("By category")
    add("  %-14s %4s %9s %12s %13s %7s %10s"
        % ("", "n", "grounded", "unsupported", "hallucinated", "missed", "abstained"))
    for category in ("ANSWERABLE", "ABSENT", "STALE", "CONTRADICTED"):
        bucket = summary["per_category"].get(category)
        if not bucket:
            continue
        add("  %-14s %4d %9d %12d %13d %7d %10d"
            % (category, bucket["n"], bucket["grounded"], bucket["unsupported"],
               bucket["hallucinated"], bucket["missed"], bucket["abstained_correct"]))
    add("")

    add("Rates")
    rates = summary["rates"]
    denominators = {
        "grounded_correct": "%d answerable" % summary["n_answerable_class"],
        "hallucinated": "%d questions" % summary["n_questions"],
        "correctly_abstained": "%d absent" % summary["n_absent"],
        "citation_validity": "%d citations" % summary["citations_total"],
        "over_abstention": "%d answerable" % summary["n_answerable_class"],
    }
    for gate in gates_report:
        metric = gate["metric"]
        bound = "%s %s" % (gate["direction"], pct(gate["threshold"]))
        status = "skip" if gate["skipped"] else ("ok" if gate["ok"] else "FAIL")
        add("  %-20s %s   of %-14s  gate %-12s %s"
            % (metric.replace("_", "-"), pct(rates.get(metric)),
               denominators.get(metric, ""), bound, status))
    if summary["citation_validity_vacuous"]:
        add("  note: citation-validity is vacuous — the answerer emitted no citations at all.")
    add("")

    failures = [r for r in results if r["verdict"] in ("hallucinated", "missed", "unsupported")]
    if verbose or failures:
        add("Per-question" if verbose else "Failures")
        shown = results if verbose else failures
        for r in shown:
            add("  %-8s %-13s %-18s %s"
                % (r["id"], r["category"], r["verdict"], r["reason"]))
            if verbose and r["answer_preview"]:
                add("           answer: %s" % r["answer_preview"])
            for check in r["citations"]:
                if verbose or not check["valid"]:
                    mark = "ok " if check["valid"] else "BAD"
                    add("           cite %s %s  (%s)" % (mark, check["raw"], check["reason"]))
        add("")

    add("RESULT: %s" % ("PASS" if passed else "FAIL"))
    return "\n".join(out)


# --------------------------------------------------------------------------

def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Score an answerer against the Eve fixture KB.")
    parser.add_argument("--answerer", default="reference",
                        help="built-in answerer: %s (default: reference)"
                             % ", ".join(sorted(BUILTIN_ANSWERERS)))
    parser.add_argument("--cmd", default=None,
                        help="shell command to run instead of a built-in answerer; "
                             "receives one question as JSON on stdin")
    parser.add_argument("--questions", default=os.path.join(HERE, "questions.json"))
    parser.add_argument("--kb", default=None, help="override the fixture KB root")
    parser.add_argument("--only", default=None,
                        help="restrict to one category, or a comma-separated list of ids")
    parser.add_argument("--timeout", type=float, default=60.0,
                        help="per-question timeout in seconds (default: 60)")
    parser.add_argument("--json", action="store_true", help="print the report as JSON")
    parser.add_argument("--out", default=None, help="write the JSON report to a file")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="show every question, not just the failures")
    parser.add_argument("--list", action="store_true",
                        help="list the question set and exit")
    for name, default in sorted(DEFAULT_GATES.items()):
        parser.add_argument("--" + name.replace("_", "-"), type=float, default=default,
                            dest=name, help="gate: default %.2f" % default)
    parser.add_argument("--no-gates", action="store_true",
                        help="report the scores but always exit 0")
    parser.add_argument("--allow-answerer-errors", action="store_true",
                        help="do not fail the run when the answerer crashed or "
                             "timed out on some questions")
    args = parser.parse_args(argv)

    try:
        data = load_questions(args.questions)
    except (OSError, ValueError) as exc:
        sys.stderr.write("cannot load questions: %s\n" % exc)
        return 2

    questions = data["questions"]
    if args.only:
        wanted = {w.strip().upper() for w in args.only.split(",") if w.strip()}
        questions = [q for q in questions
                     if q["category"].upper() in wanted or q["id"].upper() in wanted]
        if not questions:
            sys.stderr.write("no questions matched --only %s\n" % args.only)
            return 2

    if args.list:
        for q in questions:
            print("%-8s %-13s %s" % (q["id"], q["category"], q["question"]))
        return 0

    kb_root = args.kb or os.path.join(os.path.dirname(os.path.abspath(args.questions)),
                                      data.get("kb_root", "fixture-kb"))
    try:
        knowledge = KB(kb_root)
    except FileNotFoundError as exc:
        sys.stderr.write("%s\n" % exc)
        return 2

    command, answerer_name = build_command(args)
    if isinstance(command, str):
        printable = command
    else:
        # Report "python3", not "python3.14" — the scorecard should be identical
        # on every machine so that a pasted result is comparable.
        parts = ["python3" if c == sys.executable else c for c in command]
        printable = " ".join(
            os.path.basename(p) if os.path.sep in p else p for p in parts)

    results = []
    errors = 0
    for question in questions:
        payload = {
            "id": question["id"],
            "question": question["question"],
            "kb_root": knowledge.root,
        }
        stdout, error = ask(command, payload, args.timeout)
        resp = parse_response(stdout)
        if error:
            errors += 1
            resp.setdefault("errors", []).append(error)
        if resp["format"] == "empty" and not resp["citations"]:
            # Saying nothing is not asserting anything. Score it as an
            # abstention so a crashed answerer cannot be counted as a
            # hallucinator; the over-abstention rate will expose it instead.
            resp["abstain"] = True
        result = judge(question, resp, knowledge)
        if error:
            result["reason"] = "%s [answerer error: %s]" % (result["reason"], error)
        results.append(result)

    summary = aggregate(results)
    gates = {k: getattr(args, k) for k in DEFAULT_GATES}
    passed, gates_report = check_gates(summary, gates)

    # An answerer that crashed produced no assertions, which scores as
    # abstention — so on a run restricted to ABSENT questions a broken agent
    # would otherwise report PASS. Silence is not a safety property.
    if errors and not args.allow_answerer_errors:
        passed = False

    meta = {
        "kb_root": os.path.relpath(knowledge.root, os.getcwd()),
        "n_docs": len(knowledge.docs()),
        "questions_path": os.path.relpath(args.questions, os.getcwd()),
        "reference_date": data.get("reference_date", "unset"),
        "answerer": answerer_name,
        "command": printable,
        "errors": errors,
    }

    report = {"meta": meta, "summary": summary, "gates": gates_report,
              "passed": passed, "results": results}

    if args.out:
        with open(args.out, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=2, sort_keys=True)
            handle.write("\n")

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render(summary, results, meta, gates_report, passed, args.verbose))

    if args.no_gates:
        return 0
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
