#!/bin/sh
# doctor.sh -- check that Eve is actually wired up, and prove it by running it.
#
# Installed as $EVE_HOME/bin/eve-doctor. Every check prints PASS, WARN or FAIL
# followed by a one-line remedy. Exit status is 1 if anything FAILed, else 0.
# WARN never fails the run: a warning is something to look at, not something
# that is broken.
#
# The last check is the only one that really matters. It feeds a synthetic
# prompt into the real recall hook and prints the bytes that come back. Every
# other check is an inference; that one is a measurement. See
# docs/05-design-laws.md, law 5.
#
# POSIX sh. Reads nothing outside $EVE_HOME and the Claude config dir.

set -eu

EVE_HOME=${EVE_HOME:-"$HOME/.eve"}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}
VERBOSE=0

while [ $# -gt 0 ]; do
	case "$1" in
	--eve-home)
		[ $# -ge 2 ] || { echo "eve-doctor: --eve-home needs a path" >&2; exit 64; }
		EVE_HOME=$2
		shift 2
		;;
	--eve-home=*)
		EVE_HOME=${1#--eve-home=}
		shift
		;;
	--claude-dir)
		[ $# -ge 2 ] || { echo "eve-doctor: --claude-dir needs a path" >&2; exit 64; }
		CLAUDE_DIR=$2
		shift 2
		;;
	--claude-dir=*)
		CLAUDE_DIR=${1#--claude-dir=}
		shift
		;;
	-v | --verbose)
		VERBOSE=1
		shift
		;;
	-h | --help)
		cat <<'USAGE'
Usage: eve-doctor [--eve-home PATH] [--claude-dir PATH] [-v]

Checks the store, the hook registration, the effective config, and then runs
the recall hook for real and prints its output.

Exit status: 0 if nothing FAILed, 1 otherwise.
USAGE
		exit 0
		;;
	*)
		echo "eve-doctor: unknown option: $1" >&2
		exit 64
		;;
	esac
done

case "$EVE_HOME" in /*) ;; *) EVE_HOME="$(pwd)/$EVE_HOME" ;; esac
case "$CLAUDE_DIR" in /*) ;; *) CLAUDE_DIR="$(pwd)/$CLAUDE_DIR" ;; esac
# Normalise the same way install.sh does, so the registered path in
# settings.json and the path checked here compare as equal strings.
EVE_HOME=$(printf '%s' "$EVE_HOME" | sed -e 's|//*|/|g' -e 's|/$||')
CLAUDE_DIR=$(printf '%s' "$CLAUDE_DIR" | sed -e 's|//*|/|g' -e 's|/$||')

SETTINGS="$CLAUDE_DIR/settings.json"
MEMDIR="$EVE_HOME/memory"
CONFIG="$EVE_HOME/config"

FAILS=0
WARNS=0

TMPD=""
cleanup() {
	[ -n "$TMPD" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"
	return 0
}
trap cleanup EXIT HUP INT TERM
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/eve-doctor.XXXXXX")

pass() { printf 'PASS  %s\n' "$*"; }
warn() {
	printf 'WARN  %s\n' "$1"
	[ $# -ge 2 ] && printf '      -> %s\n' "$2"
	WARNS=$((WARNS + 1))
	return 0
}
fail() {
	printf 'FAIL  %s\n' "$1"
	[ $# -ge 2 ] && printf '      -> %s\n' "$2"
	FAILS=$((FAILS + 1))
	return 0
}
head1() { printf '\n-- %s\n' "$*"; }

# grep -c prints 0 and exits 1 when there are no matches. `|| echo 0` therefore
# produces the string "0\n0", which then blows up an arithmetic test. This is
# the sort of thing that only shows up on the healthy path.
count_matches() { # PATTERN FILE
	_c=$(grep -c "$1" "$2" 2>/dev/null || true)
	[ -n "$_c" ] || _c=0
	printf '%s\n' "$_c"
}

# Config as the scripts resolve it: environment first, then the file, then the
# built-in default. Printing the file would be a different question from the one
# you are asking. See docs/05-design-laws.md, law 6.
cfg() { # NAME DEFAULT
	_n=$1
	_d=$2
	eval "_v=\${$_n-}"
	if [ -n "${_v:-}" ]; then
		printf '%s\n' "$_v"
		return 0
	fi
	if [ -f "$CONFIG" ]; then
		_v=$(sed -n "s/^[[:space:]]*$_n[[:space:]]*=[[:space:]]*//p" "$CONFIG" |
			sed -e 's/[[:space:]]*$//' -e 's/[[:space:]]*#.*$//' | sed -n '1p')
		if [ -n "$_v" ]; then
			printf '%s\n' "$_v"
			return 0
		fi
	fi
	printf '%s\n' "$_d"
}

have_python3() {
	_py=$(command -v python3 2>/dev/null) || return 1
	[ -n "$_py" ] || return 1
	if [ "$(uname -s)" = "Darwin" ] && [ "$_py" = "/usr/bin/python3" ]; then
		[ -d /Library/Developer/CommandLineTools/usr/bin ] ||
			[ -d /Applications/Xcode.app ] || return 1
	fi
	python3 -c 'import json' >/dev/null 2>&1
}

# --------------------------------------------------------------------------
# A clock for the live probe
# --------------------------------------------------------------------------
#
# The doctor already runs the recall hook once. Timing that one call is nearly
# free and turns an unmeasured claim ("the hook works") into a measured one
# ("the hook works and it cost 84 ms"). It is deliberately NOT a benchmark:
# one cold sample, no warm-up, no floor, no percentiles. It exists to catch the
# machine where the hook takes 900 ms, and to send that person to `eve bench`.
#
# Budget: 250 ms. docs/03-hooks.md states the rule this defends -- a hook that
# adds a second to every prompt gets uninstalled -- and 250 ms is a quarter of
# that, tripped while the cost is still measurable rather than annoying.
#
# `date +%s%N` is tried FIRST here, unlike in eve-bench, and the difference is
# on purpose. It costs two forks (~2 ms) against python3's ~30 ms of
# interpreter startup, and the doctor's constraint is that it must not get
# slower. eve-bench has the opposite constraint -- accuracy and a per-run
# timeout -- so it prefers python3. Neither charges the timer's own startup to
# the measurement.
#
# Older BSD and older macOS `date` have no %N: they exit 0 and print a literal
# trailing "N", so an exit-status check passes and the arithmetic then silently
# does nothing sensible. Newer Darwin does support it. Do not assume either way
# -- check that what came back is all digits and long enough to be nanoseconds.
DOCTOR_BUDGET_MS=250
PROBE_CLOCK=none
if _t=$(date +%s%N 2>/dev/null); then
	case "$_t" in
	'' | *[!0-9]*) ;;
	*) [ "${#_t}" -ge 16 ] && PROBE_CLOCK=date ;;
	esac
fi
if [ "$PROBE_CLOCK" = none ] && have_python3; then
	PROBE_CLOCK=python
fi

# timed_probe IN OUT ERR  -> sets PROBE_RC and PROBE_MS (PROBE_MS empty if we
# have no clock). Never fails the doctor: an unmeasurable probe is still a probe.
timed_probe() {
	PROBE_MS=''
	case "$PROBE_CLOCK" in
	date)
		_t0=$(date +%s%N)
		set +e
		EVE_HOME="$EVE_HOME" sh "$RECALL" <"$1" >"$2" 2>"$3"
		PROBE_RC=$?
		set -e
		_t1=$(date +%s%N)
		PROBE_MS=$(((_t1 - _t0) / 1000000))
		;;
	python)
		set +e
		_r=$(python3 - "$RECALL" "$1" "$2" "$3" "$EVE_HOME" <<'PYEOF'
import os, subprocess, sys, time
hook, fin, fout, ferr, home = sys.argv[1:6]
env = dict(os.environ); env["EVE_HOME"] = home
with open(fin, "rb") as i, open(fout, "wb") as o, open(ferr, "wb") as e:
    t = time.perf_counter()
    rc = subprocess.call(["/bin/sh", hook], stdin=i, stdout=o, stderr=e, env=env)
    ms = (time.perf_counter() - t) * 1000.0
sys.stdout.write("%.0f %d\n" % (ms, rc))
PYEOF
		)
		set -e
		_ms=${_r%% *}
		_rc=${_r#* }
		case "$_ms" in '' | *[!0-9]*) _ms='' ;; esac
		case "$_rc" in '' | *[!0-9]*) _rc='' ;; esac
		if [ -n "$_ms" ] && [ -n "$_rc" ]; then
			PROBE_MS=$_ms
			PROBE_RC=$_rc
		else
			# python could not run it. Do NOT invent an exit status: the probe
			# is the one check in this whole script that is a measurement, and
			# a health check that reports a success it did not observe is worse
			# than one that reports nothing. Run it plainly, unmeasured.
			set +e
			EVE_HOME="$EVE_HOME" sh "$RECALL" <"$1" >"$2" 2>"$3"
			PROBE_RC=$?
			set -e
		fi
		;;
	*)
		set +e
		EVE_HOME="$EVE_HOME" sh "$RECALL" <"$1" >"$2" 2>"$3"
		PROBE_RC=$?
		set -e
		;;
	esac
	return 0
}

printf 'eve-doctor\n'
printf '  EVE_HOME:   %s\n' "$EVE_HOME"
printf '  Claude dir: %s\n' "$CLAUDE_DIR"

# --------------------------------------------------------------------------
head1 "store"
# --------------------------------------------------------------------------

if [ ! -d "$EVE_HOME" ]; then
	fail "$EVE_HOME does not exist" "run ./install.sh"
	printf '\n1 FAIL. Nothing else can be checked.\n'
	exit 1
fi
pass "$EVE_HOME exists"

MEM_COUNT=0
if [ -d "$MEMDIR" ]; then
	# TEMPLATE.md, MEMORY.md and INDEX.md live in the store but are not
	# memories. Counting them means a fresh install reports a store that is not
	# empty, and the live probe below builds its query from `{{TITLE}}` and then
	# reports a retrieval failure that is really a counting bug. `eve search`
	# skips the same three names; the two lists have to agree.
	find "$MEMDIR" -maxdepth 1 -type f -name '*.md' \
		! -name 'TEMPLATE.md' ! -name 'INDEX.md' ! -name 'MEMORY.md' ! -name 'README.md' \
		-print >"$TMPD/mem.list" 2>/dev/null || : >"$TMPD/mem.list"
	MEM_COUNT=$(wc -l <"$TMPD/mem.list" | tr -d ' ')
else
	: >"$TMPD/mem.list"
fi

if [ ! -d "$MEMDIR" ]; then
	fail "no memory directory at $MEMDIR" "run ./install.sh, or mkdir -p '$MEMDIR'"
elif [ "$MEM_COUNT" -eq 0 ]; then
	warn "memory store is empty" "write one: $EVE_HOME/bin/eve add my-first-rule"
else
	pass "$MEM_COUNT memory file(s) in $MEMDIR"
fi

for d in sessions state; do
	if [ -d "$EVE_HOME/$d" ]; then
		pass "$EVE_HOME/$d exists"
	else
		warn "$EVE_HOME/$d is missing" "mkdir -p '$EVE_HOME/$d'"
	fi
done

# --------------------------------------------------------------------------
head1 "scripts"
# --------------------------------------------------------------------------

for f in bin/eve hooks/eve-recall.sh hooks/eve-session-start.sh hooks/eve-session-end.sh; do
	p="$EVE_HOME/$f"
	if [ ! -f "$p" ]; then
		fail "missing $p" "re-run ./install.sh from the clone"
	elif [ ! -x "$p" ]; then
		fail "not executable: $p" "chmod +x '$p'"
	else
		pass "$f"
	fi
done

if [ -f "$EVE_HOME/hooks/eve-guard.sh" ]; then
	if [ -s "$EVE_HOME/guard-patterns" ]; then
		gp=$(grep -cv '^[[:space:]]*#' "$EVE_HOME/guard-patterns" 2>/dev/null || true)
		[ -n "$gp" ] || gp=0
		pass "guard hook present, $gp pattern(s)"
	else
		pass "guard hook present, no patterns configured (warn-only, inert)"
	fi
fi

# Nothing in $EVE_HOME may reference the clone it was installed from: you must
# be able to delete the clone and keep a working system.
if [ -f "$EVE_HOME/state/install.log" ]; then
	repo=$(sed -n 's/.*repo=\([^	]*\).*/\1/p' "$EVE_HOME/state/install.log" | sed -n '$p')
	if [ -n "$repo" ] && [ "$repo" != "$EVE_HOME" ]; then
		if grep -rlF -- "$repo" "$EVE_HOME/bin" "$EVE_HOME/hooks" >/dev/null 2>&1; then
			warn "a script under $EVE_HOME hardcodes the clone path $repo" \
				"delete the clone and the system would break; report it as a bug"
		else
			pass "no script under $EVE_HOME references the clone it came from"
		fi
	fi
fi

# --------------------------------------------------------------------------
head1 "hook registration"
# --------------------------------------------------------------------------

if [ ! -f "$SETTINGS" ]; then
	fail "no $SETTINGS" "run ./install.sh, or ./install.sh --print-hooks and paste it"
else
	pass "$SETTINGS exists"

	# Count registrations per hook script by grepping the raw file. This is
	# deliberately not a JSON query: we want to catch a stale entry from an
	# earlier install at a different path, which a well-formed query keyed on the
	# current path would miss.
	for h in eve-recall.sh eve-session-start.sh eve-session-end.sh; do
		n=$(count_matches "$h" "$SETTINGS")
		want="$EVE_HOME/hooks/$h"
		if [ "$n" -eq 0 ]; then
			fail "$h is not registered in settings.json" \
				"run ./install.sh, or ./install.sh --print-hooks"
		elif [ "$n" -gt 1 ]; then
			fail "$h is registered $n times" \
				"duplicate registrations run the hook twice; delete the stale entry in $SETTINGS"
		elif grep -q "$want" "$SETTINGS" 2>/dev/null; then
			pass "$h registered once, absolute path resolves"
		else
			fail "$h registered, but not at $want" \
				"the registered path points somewhere else; re-run ./install.sh"
		fi
	done

	if grep -q '"Stop"' "$SETTINGS" 2>/dev/null &&
		grep -q 'eve-session-end.sh' "$SETTINGS" 2>/dev/null; then
		# Only a problem if the session-end hook is on Stop; a user's own Stop
		# hook is none of our business.
		if grep -A4 '"Stop"' "$SETTINGS" 2>/dev/null | grep -q 'eve-session-end.sh'; then
			fail "session-end hook is wired to Stop" \
				"Stop fires after every assistant turn. Use SessionEnd; re-run ./install.sh"
		fi
	fi
fi

if [ -f "$CLAUDE_DIR/CLAUDE.md" ]; then
	nblocks=$(count_matches '^<!-- eve:begin -->$' "$CLAUDE_DIR/CLAUDE.md")
	if [ "$nblocks" -eq 1 ]; then
		pass "one Eve block in CLAUDE.md"
	elif [ "$nblocks" -eq 0 ]; then
		warn "no Eve block in CLAUDE.md" "re-run ./install.sh; it writes the block between sentinels"
	else
		fail "$nblocks Eve blocks in CLAUDE.md" \
			"delete all but one; keep the sentinels paired"
	fi
fi

# --------------------------------------------------------------------------
head1 "parsers available to the hooks"
# --------------------------------------------------------------------------

if command -v jq >/dev/null 2>&1; then
	pass "jq: $(command -v jq) -- hooks will parse hook JSON with jq"
elif have_python3; then
	pass "no jq; python3: $(command -v python3) -- hooks will fall back to python3"
else
	warn "no jq and no usable python3" \
		"hooks fall back to sed parsing, which is fine but less robust"
fi

# --------------------------------------------------------------------------
head1 "effective config"
# --------------------------------------------------------------------------

if [ -f "$CONFIG" ]; then
	pass "config file: $CONFIG"
else
	warn "no config file at $CONFIG" "defaults are used; re-run ./install.sh to write one"
fi

printf '      %-24s %s\n' "EVE_DISABLE" "$(cfg EVE_DISABLE 0)"
printf '      %-24s %s\n' "EVE_RECALL_LIMIT" "$(cfg EVE_RECALL_LIMIT 3)"
printf '      %-24s %s\n' "EVE_RECALL_MAX_CHARS" "$(cfg EVE_RECALL_MAX_CHARS 1200)"
printf '      %-24s %s\n' "EVE_RECALL_MIN_PROMPT" "$(cfg EVE_RECALL_MIN_PROMPT 12)"
printf '      %-24s %s\n' "EVE_SNIPPET_CHARS" "$(cfg EVE_SNIPPET_CHARS 150)"
printf '      %-24s %s\n' "EVE_CANDIDATE_CAP" "$(cfg EVE_CANDIDATE_CAP 300)"
printf '      %-24s %s\n' "EVE_MAX_LINES" "$(cfg EVE_MAX_LINES 400)"
printf '      %-24s %s\n' "EVE_MIN_SCORE" "$(cfg EVE_MIN_SCORE 7)"
printf '      %-24s %s\n' "EVE_BRIEF_MAX_CHARS" "$(cfg EVE_BRIEF_MAX_CHARS 800)"
printf '      %-24s %s\n' "EVE_ENGINE" "$(cfg EVE_ENGINE awk)"
printf '      %-24s %s\n' "EVE_DEBUG" "$(cfg EVE_DEBUG 0)"

if [ "$(cfg EVE_DISABLE 0)" = "1" ]; then
	warn "EVE_DISABLE=1: every hook exits immediately" "turn it back on: $EVE_HOME/bin/eve on"
fi

# --------------------------------------------------------------------------
head1 "memory files"
# --------------------------------------------------------------------------

if [ "$MEM_COUNT" -gt 0 ]; then
	bad_fm=0
	dupe_titles=0
	broken_links=0
	superseded=0

	: >"$TMPD/titles"
	: >"$TMPD/ids"
	: >"$TMPD/links"

	while IFS= read -r f; do
		[ -n "$f" ] || continue
		b=$(basename "$f")
		printf '%s\n' "${b%.md}" >>"$TMPD/ids"

		# A file that opens with '---' must close the block. Frontmatter is
		# optional; half a frontmatter block is a typo.
		if [ "$(head -n 1 "$f")" = "---" ]; then
			if ! awk 'NR > 1 && $0 == "---" { found = 1; exit } NR > 60 { exit } END { exit !found }' "$f"; then
				fail "unterminated frontmatter: $f" "close the block with a line containing only ---"
				bad_fm=$((bad_fm + 1))
			fi
		fi

		t=$(sed -n 's/^title:[[:space:]]*//p' "$f" | sed -n '1p')
		if [ -n "$t" ]; then
			printf '%s\n' "$t" >>"$TMPD/titles"
		fi

		if sed -n '1,30p' "$f" | grep -q '^status:[[:space:]]*superseded'; then
			superseded=$((superseded + 1))
			if [ -f "$EVE_HOME/INDEX.md" ] && grep -Fq "${b%.md}" "$EVE_HOME/INDEX.md" 2>/dev/null; then
				warn "superseded memory still listed in INDEX.md: $b" "run: $EVE_HOME/bin/eve index"
			fi
		fi

		grep -o '\[\[[^]]*\]\]' "$f" 2>/dev/null | sed -e 's/^\[\[//' -e 's/\]\]$//' >>"$TMPD/links" || true
	done <"$TMPD/mem.list"

	if [ "$bad_fm" -eq 0 ]; then
		pass "frontmatter parses in all $MEM_COUNT file(s)"
	fi

	dupe_titles=$(sort "$TMPD/titles" | uniq -d | wc -l | tr -d ' ')
	if [ "$dupe_titles" -gt 0 ]; then
		warn "$dupe_titles duplicate title(s)" "titles are what you see in recall; make them distinct"
		if [ "$VERBOSE" -eq 1 ]; then
			sort "$TMPD/titles" | uniq -d | sed 's/^/      /'
		fi
	else
		pass "no duplicate titles"
	fi

	dupe_ids=$(sort "$TMPD/ids" | uniq -d | wc -l | tr -d ' ')
	if [ "$dupe_ids" -gt 0 ]; then
		fail "$dupe_ids duplicate id(s)" "filenames are ids; they must be unique"
	fi

	if [ -s "$TMPD/links" ]; then
		sort -u "$TMPD/links" >"$TMPD/links.u"
		while IFS= read -r l; do
			[ -n "$l" ] || continue
			if [ ! -f "$MEMDIR/$l.md" ]; then
				broken_links=$((broken_links + 1))
				if [ "$VERBOSE" -eq 1 ]; then
					printf '      [[%s]] -> no such memory\n' "$l"
				fi
			fi
		done <"$TMPD/links.u"
		if [ "$broken_links" -gt 0 ]; then
			warn "$broken_links [[link]](s) point at nothing" "run with -v to list them; fix or create the target"
		else
			pass "all [[links]] resolve"
		fi
	fi

	if [ "$superseded" -gt 0 ]; then
		pass "$superseded memory(ies) marked superseded (kept, demoted, never deleted)"
	fi

	# Decisions nobody has been back to check.
	#
	# Printed, not scored. This is not a fault in the plumbing -- a decision
	# made last week is supposed to be sitting there unanswered -- so it is
	# neither a PASS nor a WARN, and it must never be able to turn the summary
	# line red. It is here because the doctor is where people look, and the
	# outcome habit is the one part of Eve that no script can perform for you.
	if [ -x "$EVE_HOME/bin/eve" ]; then
		wait_all=$(EVE_HOME="$EVE_HOME" "$EVE_HOME/bin/eve" waiting --format tsv 2>/dev/null | wc -l | tr -d ' ')
		[ -n "$wait_all" ] || wait_all=0
		if [ "$wait_all" -gt 0 ]; then
			wait_old=$(EVE_HOME="$EVE_HOME" "$EVE_HOME/bin/eve" waiting --days 90 --format tsv 2>/dev/null | wc -l | tr -d ' ')
			[ -n "$wait_old" ] || wait_old=0
			printf '      %s decision(s) with no recorded outcome' "$wait_all"
			if [ "$wait_old" -gt 0 ]; then
				printf ', %s of them over 90 days old' "$wait_old"
			fi
			printf '\n'
			printf '      the list, oldest first:  %s waiting\n' "$EVE_HOME/bin/eve"
			if [ "$VERBOSE" -eq 1 ]; then
				EVE_HOME="$EVE_HOME" "$EVE_HOME/bin/eve" waiting --limit 5 --format tsv 2>/dev/null |
					awk -F'	' '{ printf "        %6s  %s\n", $1, $2 }'
			fi
		fi
	fi

	# INDEX.md freshness. mtime flags differ between BSD and GNU stat, so try
	# both and give up quietly rather than guessing wrong.
	file_mtime() {
		stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0
	}
	if [ -f "$EVE_HOME/INDEX.md" ]; then
		idx=$(file_mtime "$EVE_HOME/INDEX.md")
		newest=0
		while IFS= read -r f; do
			[ -n "$f" ] || continue
			m=$(file_mtime "$f")
			if [ "$m" -gt "$newest" ]; then
				newest=$m
			fi
		done <"$TMPD/mem.list"
		if [ "$idx" -eq 0 ] || [ "$newest" -eq 0 ]; then
			pass "INDEX.md present (could not compare mtimes on this platform)"
		elif [ "$idx" -lt "$newest" ]; then
			warn "INDEX.md is older than the newest memory" "run: $EVE_HOME/bin/eve index"
		else
			pass "INDEX.md is current"
		fi
	else
		warn "no INDEX.md" "run: $EVE_HOME/bin/eve index"
	fi
fi

# --------------------------------------------------------------------------
head1 "live probe (the only check that is a measurement)"
# --------------------------------------------------------------------------

RECALL="$EVE_HOME/hooks/eve-recall.sh"
PROBE_SID="eve-doctor-probe"

if [ ! -x "$RECALL" ]; then
	fail "cannot probe: $RECALL is missing or not executable" "re-run ./install.sh"
elif [ "$MEM_COUNT" -eq 0 ]; then
	warn "cannot probe: no memories to find" "write one, then re-run the doctor"
else
	# Build a query out of the first memory's title, so a healthy system must
	# return something. Anything less is guessing.
	first=$(sed -n '1p' "$TMPD/mem.list")
	q=$(sed -n 's/^title:[[:space:]]*//p' "$first" | sed -n '1p')
	if [ -z "$q" ]; then
		b=$(basename "$first")
		q=$(printf '%s' "${b%.md}" | tr '-' ' ')
	fi
	q="what do we know about $q"

	# JSON-escape the query the same way a real hook payload would be encoded.
	qesc=$(printf '%s' "$q" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')
	printf '{"session_id":"%s","prompt":"%s","cwd":"%s"}' "$PROBE_SID" "$qesc" "$EVE_HOME" >"$TMPD/probe.json"

	printf '      query: %s\n' "$q"
	timed_probe "$TMPD/probe.json" "$TMPD/probe.out" "$TMPD/probe.err"
	prc=$PROBE_RC

	if [ "$prc" -ne 0 ]; then
		fail "recall hook exited $prc" \
			"a hook must always exit 0; a non-zero UserPromptSubmit hook degrades every prompt"
	else
		pass "recall hook exited 0"
	fi
	if [ -s "$TMPD/probe.err" ]; then
		fail "recall hook wrote to stderr" "stderr surfaces to the user; keep the happy path silent"
		sed 's/^/      | /' "$TMPD/probe.err"
	fi
	if [ -s "$TMPD/probe.out" ]; then
		pass "recall produced output; the exact bytes injected into context follow"
		sed 's/^/      | /' "$TMPD/probe.out"
		bytes=$(wc -c <"$TMPD/probe.out" | tr -d ' ')
		cap=$(cfg EVE_RECALL_MAX_CHARS 1200)
		if [ "$bytes" -gt "$cap" ]; then
			fail "injected block is $bytes bytes, over EVE_RECALL_MAX_CHARS=$cap" \
				"the recall hook must drop whole lines to stay under the cap"
		fi
	else
		warn "recall produced no output for its own memory's title" \
			"see the scores: $EVE_HOME/bin/eve search --query '$q' --format plain"
	fi

	# How long that one call took.
	#
	# One cold sample. It is not a benchmark and it says so: no warm-up, so the
	# page cache is cold and this reads HIGH; no floor, so it cannot tell you
	# whether the cost is your store or your shell; no percentiles, so it cannot
	# see a tail. All it is good for is noticing that the number is wrong by an
	# order of magnitude, which is the failure worth catching here.
	if [ -n "${PROBE_MS:-}" ]; then
		if [ "$PROBE_MS" -gt "$DOCTOR_BUDGET_MS" ]; then
			warn "recall took ${PROBE_MS} ms on this one cold call; the budget for a per-prompt hook is ${DOCTOR_BUDGET_MS} ms" \
				"one cold sample proves nothing on its own. Measure it properly: $EVE_HOME/bin/eve bench"
		else
			pass "recall returned in ${PROBE_MS} ms (one cold call, budget ${DOCTOR_BUDGET_MS} ms; p50/p95: $EVE_HOME/bin/eve bench)"
		fi
	fi

	# Leave no trace: the probe writes a per-session dedupe file like any other
	# session would.
	rm -f "$EVE_HOME/state/seen-$PROBE_SID" 2>/dev/null || true
fi

# --------------------------------------------------------------------------
printf '\n-- summary\n'
# --------------------------------------------------------------------------

if [ "$FAILS" -eq 0 ] && [ "$WARNS" -eq 0 ]; then
	printf 'All checks passed.\n'
	exit 0
fi
printf '%s FAIL, %s WARN.\n' "$FAILS" "$WARNS"
if [ "$FAILS" -gt 0 ]; then
	exit 1
fi
exit 0
