#!/bin/sh
# Self-test for the eval suite itself.
#
# An eval that always reports "pass" is decoration. This script asserts that the
# suite DISCRIMINATES: that the reference answerer passes, that the deliberately
# bad answerer fails, and that it fails for the specific reasons the suite claims
# to detect — a fabricated citation path, a citation to a real file that does not
# contain the claim, guessing instead of abstaining, and asserting a superseded
# value as current.
#
# Run it in CI. It needs no model, no API key, and no network.
#
#   sh evals/selftest.sh
#
# Exit 0 if the suite behaves; 1 if it has stopped being able to tell good from
# bad, which is the failure mode that matters.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if command -v python3 >/dev/null 2>&1; then
    py=python3
else
    echo "selftest: python3 not found" >&2
    exit 2
fi

tmp=${TMPDIR:-/tmp}/eve-evals-selftest.$$
mkdir -p "$tmp"
trap 'rm -rf "$tmp"' EXIT INT TERM

fail=0
note() { printf '  %-6s %s\n' "$1" "$2"; }

echo "Eve eval self-test"
echo

# ---------------------------------------------------------------- fixture ---
echo "1. fixture integrity"
if "$py" "$here/check_fixture.py" >"$tmp/fixture.txt" 2>&1; then
    note "ok" "every expected citation resolves and supports its claim"
else
    note "FAIL" "fixture is inconsistent:"
    sed 's/^/         /' "$tmp/fixture.txt"
    fail=1
fi
echo

# -------------------------------------------------------------- reference ---
echo "2. reference answerer must PASS"
if "$py" "$here/run.py" --answerer reference --json >"$tmp/reference.json" 2>"$tmp/reference.err"; then
    note "ok" "exit 0, all gates met"
else
    note "FAIL" "reference answerer did not pass its own gates"
    sed 's/^/         /' "$tmp/reference.err" 2>/dev/null || true
    fail=1
fi
echo

# -------------------------------------------------------------------- bad ---
echo "3. deliberately bad answerer must be CAUGHT"
if "$py" "$here/run.py" --answerer bad --json >"$tmp/bad.json" 2>"$tmp/bad.err"; then
    note "FAIL" "the bad answerer passed the gates — the scorer is broken"
    fail=1
else
    note "ok" "exit 1, gates failed"
fi

# Assert the specific detections, not just "it failed somehow".
"$py" - "$tmp/bad.json" <<'PY' || fail=1
import json, sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

results = report["results"]
rates = report["summary"]["rates"]
reasons = [r["reason"] for r in results]
cite_reasons = [c["reason"] for r in results for c in r["citations"]]

def check(label, condition):
    print("  %-6s %s" % ("ok" if condition else "FAIL", label))
    return condition

ok = True
ok &= check("fabricated citation path detected",
            "path_not_found" in cite_reasons)
ok &= check("citation to a real file that lacks the claim detected",
            "claim_not_in_cited_text" in cite_reasons)
ok &= check("guessing on ABSENT questions detected",
            any(r["category"] == "ABSENT" and r["verdict"] == "hallucinated"
                for r in results))
ok &= check("superseded value asserted as current detected",
            any(reason.startswith("asserted_superseded_or_wrong_value")
                for reason in reasons))
ok &= check("stale fact quoted without its date detected",
            "stale_fact_quoted_without_its_date" in reasons)
ok &= check("correct answers still scored as grounded (not a blanket fail)",
            report["summary"]["verdicts"]["grounded"] > 0)
ok &= check("citation-validity is below 100 percent",
            rates["citation_validity"] < 1.0)
ok &= check("correct-abstention rate is zero on a never-abstaining answerer",
            rates["correctly_abstained"] == 0.0)

sys.exit(0 if ok else 1)
PY
echo

# ------------------------------------------------------------------ naive ---
echo "4. naive retriever must fail on ABSENT while doing fine elsewhere"
"$py" "$here/run.py" --answerer naive --json >"$tmp/naive.json" 2>/dev/null || true
"$py" - "$tmp/naive.json" <<'PY' || fail=1
import json, sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)

absent = [r for r in report["results"] if r["category"] == "ABSENT"]
answered = [r for r in absent if not r["abstained"]]
grounded = report["summary"]["verdicts"]["grounded"]

def check(label, condition):
    print("  %-6s %s" % ("ok" if condition else "FAIL", label))
    return condition

ok = True
ok &= check("an honest retriever with no abstention answers the traps anyway",
            len(answered) >= len(absent) - 1)
ok &= check("...while still getting real questions right", grounded > 0)
sys.exit(0 if ok else 1)
PY
echo

# ---------------------------------------------------------- custom command ---
echo "5. --cmd path works for an external agent"
cat >"$tmp/always_abstain.sh" <<'SH'
#!/bin/sh
cat >/dev/null
printf 'ABSTAIN: nothing in the knowledge base covers that.\n'
SH
chmod +x "$tmp/always_abstain.sh"
"$py" "$here/run.py" --cmd "$tmp/always_abstain.sh" --json >"$tmp/abstainer.json" 2>/dev/null || true
"$py" - "$tmp/abstainer.json" <<'PY' || fail=1
import json, sys

with open(sys.argv[1]) as handle:
    report = json.load(handle)
rates = report["summary"]["rates"]

def check(label, condition):
    print("  %-6s %s" % ("ok" if condition else "FAIL", label))
    return condition

ok = True
ok &= check("external command was scored at all",
            report["summary"]["n_questions"] > 0)
ok &= check("an always-abstaining agent scores zero hallucinations...",
            rates["hallucinated"] == 0.0)
ok &= check("...and is caught anyway by the over-abstention gate",
            rates["over_abstention"] == 1.0 and not report["passed"])
sys.exit(0 if ok else 1)
PY
echo

if [ "$fail" -eq 0 ]; then
    echo "SELFTEST: PASS  (the suite can tell a grounded answer from a fabricated one)"
    exit 0
fi
echo "SELFTEST: FAIL"
exit 1
