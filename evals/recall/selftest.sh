#!/bin/sh
# Prove the recall gate still catches a regression.
#
# A suite that always passes is indistinguishable from a suite that is not
# running. This script deliberately breaks the ranker four ways and asserts the
# suite notices each one, then breaks the FIXTURE and asserts the tier check
# notices that too.
#
# The important case is `gate-down`. Lowering EVE_MIN_SCORE RAISES recall — a
# recall-only eval would call it an improvement and merge it. It must fail here,
# on precision, or this suite is not doing the job it was built for.
#
# Nothing is written inside the repo. Every degraded build is a copy in a temp
# directory, removed on exit. Re-runnable, no arguments, no network.
#
#   sh evals/recall/selftest.sh
#
# Exit 0 if every assertion holds, 1 otherwise.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
eve="$root/bin/eve"

tmp=$(mktemp -d "${TMPDIR:-/tmp}/eve-recall-selftest.XXXXXX")
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT HUP INT TERM

fails=0
pass() { printf '  ok    %s\n' "$1"; }
fail() {
	printf '  FAIL  %s\n' "$1"
	fails=$((fails + 1))
}

run() { sh "$here/run.sh" "$@" >"$tmp/out" 2>&1; }

# Build a degraded copy of bin/eve and REFUSE to continue if the substitution
# did nothing. A no-op sed would make the assertion below pass while proving
# nothing at all, which is the exact failure this file exists to prevent.
degrade() { # NAME SED-EXPR
	_name=$1
	_expr=$2
	sed "$_expr" "$eve" >"$tmp/eve-$_name"
	chmod +x "$tmp/eve-$_name"
	if cmp -s "$eve" "$tmp/eve-$_name"; then
		fail "$_name: '$_expr' changed nothing in bin/eve — the scorer moved; update this selftest"
		return 1
	fi
	return 0
}

# assert_fail NAME PATTERN -- the run must exit 1 and say PATTERN
assert_fail() {
	_name=$1
	_pat=$2
	if run --eve "$tmp/eve-$_name"; then
		fail "$_name: suite PASSED a broken ranker"
		return 0
	fi
	if grep -q "$_pat" "$tmp/out"; then
		pass "$_name: caught, and named it ($_pat)"
	else
		fail "$_name: failed, but never mentioned $_pat"
		sed -n '/REGRESSED/,$p' "$tmp/out" | sed 's/^/        /'
	fi
}

printf '\nevals/recall selftest\n\n'

# 1. The unmodified tree must pass. If this fails, everything below is noise.
if run; then
	pass "clean tree passes against the committed baseline"
else
	fail "clean tree does NOT pass — fix that before trusting anything below"
	sed -n '/REGRESSED/,$p' "$tmp/out" | sed 's/^/        /'
fi

# 2. Gate raised: fewer memories clear it, recall falls.
if degrade gate-up 's/_d_minscore=7/_d_minscore=14/'; then
	assert_fail gate-up 'hit1 fell'
fi

# 3. Gate lowered: recall RISES and precision collapses. The one that matters.
if degrade gate-down 's/_d_minscore=7/_d_minscore=2/'; then
	assert_fail gate-down 'misfires rose'
	if grep -q 'out-of-scope: misfires rose' "$tmp/out"; then
		pass "gate-down: out-of-scope controls stopped being silent, and that was caught"
	else
		fail "gate-down: out-of-scope false positives were not reported"
	fi
	# hit1 OR hit3. Dropping the floor does not change who ranks first, it lets
	# more memories in underneath the leader -- so the recall it buys shows up
	# at rank 3. Asserting hit1 specifically would fail for the wrong reason and
	# tempt the next person to weaken the precision half of this test.
	if grep -qE 'hit[13] rose' "$tmp/out"; then
		pass "gate-down: recall genuinely improved — so the FAIL came from precision alone"
	else
		fail "gate-down: recall did not rise; this no longer demonstrates the trade-off"
	fi
fi

# 4. Title weight flattened: the strongest signal a flat store has, removed.
if degrade title-weight 's/if (6 > best) best = 6/if (1 > best) best = 1/'; then
	assert_fail title-weight 'fell'
fi

# 5. Stopwords emptied: every query keeps its filler words, ranking floods.
if degrade stopwords 's/^STOPWORDS=.*/STOPWORDS=" "/'; then
	assert_fail stopwords 'REGRESSED'
fi

# 6. The fixture check must be load-bearing too. Give a `disjoint` query real
#    lexical overlap and the suite has to refuse the run (exit 2) rather than
#    quietly report a better disjoint score.
cp -R "$here/fixture-store" "$tmp/fixture-tampered"
# C01 is "can we ship this evening" against the deploy memory.
printf '\nAn evening deploy is still a deploy.\n' \
	>>"$tmp/fixture-tampered/memory/deploys-blocked-after-1800-utc.md"
set +e
sh "$here/run.sh" --fixture "$tmp/fixture-tampered" >"$tmp/out" 2>&1
rc=$?
set -e
if [ "$rc" -eq 2 ] && grep -q 'fixture check FAILED' "$tmp/out"; then
	pass "edited fixture is caught by the tier check (exit 2, not a silent rescore)"
else
	fail "edited fixture was NOT caught (exit $rc); tier labels are decorative"
	sed 's/^/        /' "$tmp/out" | head -20
fi

printf '\n'
if [ "$fails" -eq 0 ]; then
	printf 'selftest OK — the suite still tells a good ranker from a bad one.\n\n'
	exit 0
fi
printf 'selftest FAILED: %s assertion(s).\n\n' "$fails"
exit 1
