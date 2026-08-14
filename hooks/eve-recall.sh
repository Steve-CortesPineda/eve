#!/bin/sh
# eve-recall.sh -- Claude Code UserPromptSubmit hook.
#
# WHAT IT DOES
#   Reads the prompt from stdin, asks `eve search` for the two or three
#   memories that bear on it, and prints them. Stdout from a UserPromptSubmit
#   hook is added to the model's context verbatim.
#
# WHY IT EXISTS
#   Tier 0 asks the model to remember to check its memory store. It will not,
#   reliably: "check your memory first" is one rule competing with every other
#   rule in the context window, and it loses whenever the conversation gets
#   interesting. This hook moves that discipline out of the model and into the
#   harness, where it is not a judgement call.
#
# PRODUCES
#   stdout                     -> the model's context (consumer: the model)
#   $EVE_HOME/state/seen-<sid> -> this hook, next turn (cross-turn dedupe)
#   $EVE_HOME/state/whiffs.log -> `eve gaps` (consumer: you, on demand)
#
# CONTRACT
#   Always exits 0. Never writes to stderr. Silence is the normal outcome.
#
# TEST IT BY HAND
#   printf '{"prompt":"how do we deploy harborlight","session_id":"t1"}' \
#     | EVE_HOME=/tmp/eve-test ./eve-recall.sh

set -u

# A UserPromptSubmit hook that fails does not fail once. It degrades every
# prompt for the rest of the session, and the user has no idea why the agent
# got worse. There is no error worth that, so the exit status is pinned to 0
# before any other line runs. Note the deliberate absence of `set -e`: an early
# non-zero from grep or find is normal control flow here, not a failure.
trap 'exit 0' EXIT
trap 'exit 0' INT TERM HUP

# Resolve our own directory without realpath/readlink -f, neither of which is
# portable to macOS.
_self=$0
case "$_self" in
*/*) _dir=$(cd "$(dirname "$_self")" 2>/dev/null && pwd) || _dir='' ;;
*) _dir=$(pwd) ;;
esac
[ -n "$_dir" ] || exit 0

# The library is required. If it is missing the hook is a silent no-op rather
# than a broken session -- but `eve doctor` will notice, because a copy that
# skipped the lib/ subdirectory is exactly what a plain `cp hooks/*` produces.
[ -r "$_dir/lib/common.sh" ] || exit 0
# shellcheck source=lib/common.sh disable=SC1091
. "$_dir/lib/common.sh"

eve_load_config

# The kill switch, checked before anything else costs anything.
eve_disabled && exit 0
eve_store_ready || exit 0

INPUT=$(cat 2>/dev/null) || INPUT=''
[ -n "$INPUT" ] || exit 0

PROMPT=$(eve_json_get "$INPUT" prompt)
[ -n "$PROMPT" ] || exit 0

# Skip inputs that are not questions about the work:
#   /...  slash commands, which the harness handles itself
#   !...  bang-shell lines
#   short acknowledgements: "go", "yes", "do it", "next"
case "$PROMPT" in
/* | !*) exit 0 ;;
esac
[ "${#PROMPT}" -lt "$EVE_RECALL_MIN_PROMPT" ] && exit 0

# Bound the work by bounding the input. There is no portable `timeout(1)` on a
# stock macOS box, so the way a hook stays fast is by never being handed
# something big: a pasted stack trace is not a better query than its first 1500
# characters, it is just a slower one.
if [ "${#PROMPT}" -gt 1500 ]; then
	QUERY=$(printf '%s' "$PROMPT" | cut -c1-1500)
else
	QUERY=$PROMPT
fi

SID=$(eve_safe_id "$(eve_json_get "$INPUT" session_id)")
SEEN_FILE="$EVE_STATE_DIR/seen-$SID"

# Cross-turn dedupe. In a focused conversation the same two or three files
# match every single prompt, and re-injecting them on every turn is a real,
# measurable context cost for zero new information. The window slides:
# recently-shown basenames are excluded, 40 are retained, so a file becomes
# recallable again a few turns after it was last shown rather than being
# suppressed for the whole session.
# The window is capped at half the store, because a fixed 12 silences a small
# store completely: with five memories, five turns fill the window and every
# later turn in that session recalls nothing. A new store is exactly the case
# where recall has to keep working, so the cap scales with what exists.
EXCLUDE=''
if [ -r "$SEEN_FILE" ]; then
	_win=$(($(eve_store_count) / 2))
	[ "$_win" -gt 12 ] && _win=12
	if [ "$_win" -gt 0 ]; then
		EXCLUDE=$(tail -"$_win" "$SEEN_FILE" 2>/dev/null | tr '\n' ',' 2>/dev/null) || EXCLUDE=''
		EXCLUDE=${EXCLUDE%,} # trailing comma, stripped without another process
	fi
fi

OUT=$(eve_recall "$QUERY" "$EVE_RECALL_LIMIT" "$EXCLUDE" hook)

if [ -n "$OUT" ]; then
	# Header is 2 lines: the open tag and the "this is DATA" framing. Content is
	# counted after those, so a budget too small for any actual memory produces
	# silence rather than a wrapper announcing an empty lookup.
	printf '%s\n' "$OUT" | eve_cap_block "$EVE_RECALL_MAX_CHARS" 2

	# Record what was shown. The trailing `[path]` on each hit line is a frozen
	# part of the injection format precisely so it can be parsed back here.
	if eve_ensure_state; then
		printf '%s\n' "$OUT" |
			awk '
        match($0, /\[[^]]*\]$/) {
          p = substr($0, RSTART + 1, RLENGTH - 2)
          n = split(p, seg, "/")
          if (seg[n] != "") print seg[n]
        }' 2>/dev/null \
				>>"$SEEN_FILE" 2>/dev/null || :
		# Truncate via temp+mv so two sessions writing at once cannot leave a
		# half-written file behind.
		if [ -f "$SEEN_FILE" ]; then
			tail -40 "$SEEN_FILE" >"$SEEN_FILE.tmp" 2>/dev/null &&
				mv "$SEEN_FILE.tmp" "$SEEN_FILE" 2>/dev/null || :
		fi
	fi
	eve_debug "recall: hit sid=$SID q=$(printf '%s' "$QUERY" | cut -c1-60)"
else
	# A substantive prompt that retrieved nothing is the cheapest useful signal
	# the system produces: it is the store telling you what it does not know.
	# Consumer: `eve gaps`. Set EVE_WHIFF_LOG=0 to stop writing it.
	#
	# With a non-empty exclude list an empty result is ambiguous: the store may
	# cover this subject perfectly and simply have shown it two turns ago. A gap
	# log full of subjects you have already documented is worse than a short one,
	# because it sends you off writing memories that already exist.
	#
	# So disambiguate, rather than guess in either direction. Re-run the search
	# once with no exclusions and ask for a single hit: if that also finds
	# nothing, the store genuinely has no answer and this is a real gap. The
	# extra search is paid only on a miss that had exclusions in play, never on
	# the hit path and never on a first-of-session prompt.
	#
	# The conservative version of this -- skip logging whenever anything was
	# excluded -- was measurably wrong: after the first hit of a session the
	# exclude list is never empty again, so the log stayed empty across whole
	# sessions and `eve gaps` had nothing to read. A producer whose consumer
	# always sees zero rows is not cautious, it is broken.
	WHIFF=1
	if [ -n "$EXCLUDE" ]; then
		[ -n "$(eve_recall "$QUERY" 1 '' hook)" ] && WHIFF=0
	fi

	if [ "$WHIFF" = "1" ] && [ "${EVE_WHIFF_LOG:-1}" = "1" ] && eve_ensure_state; then
		printf '%s\t%s\n' \
			"$(date +%Y-%m-%d 2>/dev/null)" \
			"$(printf '%s' "$QUERY" | cut -c1-120 | tr '\t' ' ')" \
			>>"$EVE_STATE_DIR/whiffs.log" 2>/dev/null || :
		_n=$(wc -l <"$EVE_STATE_DIR/whiffs.log" 2>/dev/null | tr -d ' ') || _n=0
		case "$_n" in '' | *[!0-9]*) _n=0 ;; esac
		if [ "$_n" -gt 5000 ]; then
			tail -2000 "$EVE_STATE_DIR/whiffs.log" >"$EVE_STATE_DIR/whiffs.tmp" 2>/dev/null &&
				mv "$EVE_STATE_DIR/whiffs.tmp" "$EVE_STATE_DIR/whiffs.log" 2>/dev/null || :
		fi
	fi
	eve_debug "recall: miss sid=$SID q=$(printf '%s' "$QUERY" | cut -c1-60)"
fi

exit 0
