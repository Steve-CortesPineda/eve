#!/bin/sh
# eve-session-end.sh -- Claude Code SessionEnd hook.
#
# WHAT IT DOES
#   Appends one record per session to $EVE_HOME/sessions/YYYY-MM-DD.md: the
#   task, the files touched, and how the session ended.
#
# WHY IT EXISTS
#   If capturing what happened depends on the model choosing to write it down
#   before it stops, it will not happen on the sessions that matter -- the
#   long, messy, interesting ones, which are exactly the ones that run out of
#   room before anyone gets around to summarising.
#
# WHY SessionEnd AND NOT Stop
#   `Stop` fires at the end of every assistant turn. A capture routine wired to
#   it runs dozens of times per session and writes near-duplicate records, which
#   inflates every count derived from them. It looks like it works, because it
#   does fire. Read what triggers an event before wiring to it, and check the
#   emitted volume once, by hand, before trusting anything downstream.
#
# WHY IT NEVER WRITES INTO memory/
#   Session logs are machine residue; memories are curated by a human. Keeping
#   them in separate trees is what lets retrieval stay simple -- if generated
#   notes lived in the searched directory, the ranker would need shape and path
#   penalties to stop machine output burying hand-written rules. Separate at the
#   filesystem level and that entire ranking problem never exists.
#
# PRODUCES
#   $EVE_HOME/sessions/YYYY-MM-DD.md -> you, and eve-session-start.sh (which
#                                       reports the last session's date/count)
#
#   stdout is NOT added to context for SessionEnd. Nothing printed here is read
#   by the model; do not use it to talk to Claude.
#
# CONTRACT
#   Always exits 0. No-op for one-shot and headless invocations.
#
# TEST IT BY HAND
#   printf '{"session_id":"t1","transcript_path":"/tmp/t.jsonl","reason":"exit"}' \
#     | EVE_DRY_RUN=1 EVE_HOME=/tmp/eve-test ./eve-session-end.sh

set -u

trap 'exit 0' EXIT
trap 'exit 0' INT TERM HUP

_self=$0
case "$_self" in
*/*) _dir=$(cd "$(dirname "$_self")" 2>/dev/null && pwd) || _dir='' ;;
*) _dir=$(pwd) ;;
esac
[ -n "$_dir" ] || exit 0
[ -r "$_dir/lib/common.sh" ] || exit 0
# shellcheck source=lib/common.sh disable=SC1091
. "$_dir/lib/common.sh"

eve_load_config
eve_disabled && exit 0

DRY_RUN=${EVE_DRY_RUN:-0}

INPUT=$(cat 2>/dev/null) || INPUT=''
[ -n "$INPUT" ] || exit 0

SID_RAW=$(eve_json_get "$INPUT" session_id)
SID=$(eve_safe_id "$SID_RAW")
SHORT_SID=$(printf '%s' "$SID" | cut -c1-8)
TRANSCRIPT=$(eve_json_get "$INPUT" transcript_path)
REASON=$(eve_json_get "$INPUT" reason)
[ -n "$REASON" ] || REASON=exit

# No transcript means we cannot tell a real session from a one-shot. Writing
# nothing is the safe direction: a missing record costs one session of history,
# a spurious record costs the credibility of the whole log.
[ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ] || {
	eve_debug "session-end: no readable transcript, skipping (sid=$SHORT_SID)"
	exit 0
}

# --- Interactive gate ------------------------------------------------------
#
# Automated runs -- SDK calls, `claude -p` one-shots fired by a script, CI --
# end sessions too, and they will happily flood this log with records nobody
# will ever read. Two filters, in order of reliability:
#
#   1. Turn count. Portable, always available, and the one we actually rely on.
#   2. The transcript's `entrypoint` field, when present. Best effort only:
#      field names are not a stable interface, so an unrecognised value is
#      treated as "probably interactive" rather than as a reason to bail.

TURNS=$(grep -c '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | tr -d ' ')
TURNS=$(eve_int "$TURNS" 0)

# Fewer than two assistant turns is a session that was opened and closed, or a
# single scripted question. Neither is worth a line.
if [ "$TURNS" -lt 2 ]; then
	eve_debug "session-end: $TURNS turns, below floor, skipping (sid=$SHORT_SID)"
	exit 0
fi

FIRST_USER_LINE=$(grep -m1 '"type":"user"' "$TRANSCRIPT" 2>/dev/null) || FIRST_USER_LINE=''
if [ -n "$FIRST_USER_LINE" ]; then
	ENTRYPOINT=$(eve_json_get "$FIRST_USER_LINE" entrypoint)
	case "$ENTRYPOINT" in
	'' | cli | unknown) : ;; # interactive, or a format we do not recognise
	*)
		eve_debug "session-end: entrypoint=$ENTRYPOINT, not interactive, skipping"
		exit 0
		;;
	esac
fi

# --- Extract ---------------------------------------------------------------
#
# Everything below reads matched lines only. A transcript is a JSONL file that
# can reach tens of megabytes; slurping one through a JSON parser inside a hook
# is how a 10 second timeout gets hit. grep first, parse second, cap always.

TASK=''
if [ -n "$FIRST_USER_LINE" ]; then
	if eve_have_jq; then
		TASK=$(printf '%s' "$FIRST_USER_LINE" | jq -r '
      (.message.content // "")
      | if type == "string" then .
        elif type == "array" then ([.[]? | select(.type == "text") | .text] | join(" "))
        else "" end
      | gsub("[\n\r\t]+"; " ")' 2>/dev/null) || TASK=''
	fi
	if [ -z "$TASK" ]; then
		# sed -E, not BRE: `\|` alternation is a GNU extension that BSD sed
		# silently never matches. See the note in lib/common.sh.
		TASK=$(printf '%s' "$FIRST_USER_LINE" |
			sed -E -n 's/.*"content":"(([^"\]|\\.)*)".*/\1/p' 2>/dev/null |
			sed -e 's/\\n/ /g' -e 's/\\"/"/g' 2>/dev/null) || TASK=''
	fi
fi
TASK=$(printf '%s' "$TASK" | tr -s ' \t' ' ' | cut -c1-220)
eve_trim_var "$TASK"
TASK=$_eve_r

# Files the session touched, from tool inputs. `head` bounds the scan: grep
# takes the pipe closing as its cue to stop, so this stays cheap on a huge
# transcript instead of reading all of it to throw most of it away.
TOUCHED=$(grep -o '"file_path":"[^"]*"' "$TRANSCRIPT" 2>/dev/null |
	head -200 |
	sed -e 's/^"file_path":"//' -e 's/"$//' 2>/dev/null |
	sort -u 2>/dev/null | head -6) || TOUCHED=''

TOUCHED_LINE=''
if [ -n "$TOUCHED" ]; then
	OLDIFS=$IFS
	IFS='
'
	for f in $TOUCHED; do
		TOUCHED_LINE="${TOUCHED_LINE}${TOUCHED_LINE:+, }$(eve_tilde "$f")"
	done
	IFS=$OLDIFS
	TOUCHED_LINE=$(printf '%s' "$TOUCHED_LINE" | cut -c1-400)
fi

# The tail of the last assistant turns is, in practice, the closing summary.
CLOSING=''
if eve_have_jq; then
	CLOSING=$(grep '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | tail -25 |
		jq -r '[.message.content[]? | select(.type == "text") | .text] | join(" ")' 2>/dev/null |
		awk 'NF' 2>/dev/null | tail -2 | tr '\n' ' ') || CLOSING=''
fi
if [ -z "$CLOSING" ]; then
	CLOSING=$(grep '"type":"assistant"' "$TRANSCRIPT" 2>/dev/null | tail -5 |
		grep -o '"text":"[^"]*"' 2>/dev/null | tail -2 |
		sed -e 's/^"text":"//' -e 's/"$//' -e 's/\\n/ /g' 2>/dev/null | tr '\n' ' ') || CLOSING=''
fi
CLOSING=$(printf '%s' "$CLOSING" | tr -s ' \t' ' ' | cut -c1-400)
eve_trim_var "$CLOSING"
CLOSING=$_eve_r

# --- Compose ---------------------------------------------------------------

TODAY=$(date +%Y-%m-%d 2>/dev/null) || TODAY=unknown
NOW_HM=$(date +%H:%M 2>/dev/null) || NOW_HM='??:??'
SESSION_FILE="$EVE_SESSIONS_DIR/$TODAY.md"
MARKER="<!-- eve:session $SID -->"

RECORD=$(
	printf '## %s  %s  (%s turns, %s)\n\n' "$NOW_HM" "$SHORT_SID" "$TURNS" "$REASON"
	printf '**Task:** %s\n' "${TASK:-not captured}"
	[ -n "$TOUCHED_LINE" ] && printf '**Touched:** %s\n' "$TOUCHED_LINE"
	[ -n "$CLOSING" ] && printf '**Ended with:** %s\n' "$CLOSING"
	printf '\n%s\n' "$MARKER"
)

# The only honest way to test a hook that runs at exit is to make it show you
# what it would have written without writing it.
if [ "$DRY_RUN" = "1" ]; then
	printf '%s\n' "--- EVE_DRY_RUN: would append to $SESSION_FILE ---"
	printf '%s\n' "$RECORD"
	exit 0
fi

mkdir -p "$EVE_SESSIONS_DIR" 2>/dev/null || exit 0

# Idempotent: a session that somehow ends twice gets one record, not two.
if [ -f "$SESSION_FILE" ] && grep -qF "$MARKER" "$SESSION_FILE" 2>/dev/null; then
	eve_debug "session-end: $SHORT_SID already logged today, skipping"
	exit 0
fi

if [ ! -f "$SESSION_FILE" ]; then
	{
		printf '# Sessions - %s\n\n' "$TODAY"
		printf 'Appended by eve-session-end.sh. This directory is NOT searched by\n'
		printf 'recall -- curated memories live in memory/. If something here is worth\n'
		printf 'remembering, promote it: `eve add <slug>`.\n\n'
	} >"$SESSION_FILE" 2>/dev/null || exit 0
fi

printf '%s\n\n' "$RECORD" >>"$SESSION_FILE" 2>/dev/null || exit 0
eve_debug "session-end: logged $SHORT_SID ($TURNS turns) to $SESSION_FILE"

exit 0
