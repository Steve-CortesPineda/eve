#!/bin/sh
# eve-guard.sh -- Claude Code PreToolUse hook. OPTIONAL, SHIPS DISABLED.
#
# WHAT IT DOES
#   Matches a tool call against patterns you wrote in $EVE_HOME/guard-patterns
#   and prints one line of warning before the call runs.
#
# WHY IT IS NOT INSTALLED BY DEFAULT
#   A guard that produces false positives gets ignored within a day, and an
#   ignored guard is worse than no guard: it trains you to click through the one
#   warning that mattered. The pattern file ships empty on purpose. Add a
#   pattern only after something has actually gone wrong once.
#
# WARN VS BLOCK
#   Warn-only (default): print to stderr, exit 0. The call proceeds.
#   Block: exit 2. Claude Code stops the call and feeds stderr back to the model
#   as the reason. Uncomment the marked line to switch. Do not switch until the
#   pattern has run in warn mode for a while without a single false positive.
#
# PATTERN FILE
#   $EVE_HOME/guard-patterns -- one POSIX extended regex per line, `#` comments.
#   Matched against the tool's command or file path. Examples:
#     # git push --force to a shared branch
#     git[[:space:]]+push.*--force
#     # editing generated files by hand
#     /INDEX\.md$
#
# CONTRACT
#   Exits 0 unless you deliberately enable blocking. Missing pattern file is a
#   silent no-op.
#
# TEST IT BY HAND
#   printf '{"tool_name":"Bash","tool_input":{"command":"git push --force"}}' \
#     | EVE_HOME=/tmp/eve-test ./eve-guard.sh

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

PATTERNS="$EVE_HOME/guard-patterns"
[ -r "$PATTERNS" ] || exit 0
grep -qv '^[[:space:]]*\(#.*\)\?$' "$PATTERNS" 2>/dev/null || exit 0 # empty or all comments

INPUT=$(cat 2>/dev/null) || INPUT=''
[ -n "$INPUT" ] || exit 0

TOOL=$(eve_json_get "$INPUT" tool_name)
[ -n "$TOOL" ] || exit 0

# tool_input is an object, so pull the two string fields worth matching on
# rather than trying to render arbitrary nested JSON as text.
SUBJECT=''
if eve_have_jq; then
	SUBJECT=$(printf '%s' "$INPUT" | jq -r '
    [ .tool_input.command? // empty, .tool_input.file_path? // empty ]
    | map(select(type == "string")) | join(" ")' 2>/dev/null) || SUBJECT=''
fi
if [ -z "$SUBJECT" ]; then
	# sed -E, not BRE: see the note in lib/common.sh about `\|`.
	SUBJECT=$(printf '%s' "$INPUT" |
		sed -E -n 's/.*"command"[[:space:]]*:[[:space:]]*"(([^"\]|\\.)*)".*/\1/p' 2>/dev/null) || SUBJECT=''
fi
[ -n "$SUBJECT" ] || exit 0

# Comments have to be stripped before grep -f sees the file, or a `#` line
# becomes a pattern that matches everything. Build the stripped copy in state/
# under our own pid so two concurrent tool calls cannot read each other's.
eve_ensure_state || exit 0
ACTIVE="$EVE_STATE_DIR/guard-active.$$"
grep -v '^[[:space:]]*#' "$PATTERNS" 2>/dev/null | grep -v '^[[:space:]]*$' >"$ACTIVE" 2>/dev/null || {
	rm -f "$ACTIVE" 2>/dev/null
	exit 0
}

HIT=$(printf '%s' "$SUBJECT" | grep -Ef "$ACTIVE" 2>/dev/null | head -1) || HIT=''
rm -f "$ACTIVE" 2>/dev/null || :

if [ -n "$HIT" ]; then
	printf 'eve-guard: %s call matches a pattern in %s\n' \
		"$TOOL" "$(eve_tilde "$PATTERNS")" >&2
	eve_debug "guard: matched tool=$TOOL"
	# exit 2   # <- uncomment to BLOCK instead of warn
fi

exit 0
