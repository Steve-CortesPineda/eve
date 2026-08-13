#!/bin/sh
# eve-session-start.sh -- Claude Code SessionStart hook.
#
# WHAT IT DOES
#   Prints a short standing-context block when a session opens: how big the
#   memory store is, what it holds standing rules about, where the index is,
#   and one sentence telling the model when to consult it.
#
# WHY IT EXISTS
#   A fresh session does not know the store exists. Everything else in Eve is
#   reactive -- it answers a prompt. This is the one place that establishes,
#   before the first prompt, that there is something to consult.
#
# BUDGET DISCIPLINE
#   This block is paid for on every single session, so it is the easiest place
#   in the whole system to waste context. Nothing here may be something the
#   model can derive for free: no date banner, no OS, no disk usage, no
#   decoration. Every line must be information it cannot otherwise get.
#   Each component is individually bounded; the global cap is only a backstop.
#
# PRODUCES
#   stdout -> the model's context (consumer: the model)
#
# CONTRACT
#   Always exits 0. Silent when there is nothing worth saying.
#
# TEST IT BY HAND
#   printf '{"source":"startup"}' | EVE_HOME=/tmp/eve-test ./eve-session-start.sh

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
eve_store_ready || exit 0

# stdin carries {"source":"startup"|"resume"|"compact"|"clear", ...}. We read it
# so the hook drains its input cleanly and so EVE_DEBUG can record which source
# fired, but the emitted block is the same for every source: the store has not
# changed between them, and branching here would mean two behaviours to test.
INPUT=$(cat 2>/dev/null) || INPUT=''
SOURCE=$(eve_json_get "$INPUT" source)

# --- Store shape -----------------------------------------------------------
#
# Pass 1 emits one small record per file, reading only the frontmatter window.
# Pass 2 aggregates. Splitting it this way means xargs is free to invoke awk
# more than once on a large store without double-counting anything.

SUMMARY=$(
	eve_find_memories |
		xargs -0 awk '
      function flush() {
        if (cur == "") return
        print "F"
        print "T\t" ftype
        if (fstatus == "superseded") print "S"
        if (ftype == "feedback" && ftags != "") print "G\t" ftags
      }
      FILENAME != cur { flush(); cur = FILENAME; ftype = "note"; fstatus = "active"; ftags = ""; infm = 0; fmdone = 0 }
      FNR > 15 { next }
      FNR == 1 { if ($0 ~ /^---[ \t]*$/) infm = 1; next }
      infm && !fmdone && /^---[ \t]*$/ { fmdone = 1; next }
      infm && !fmdone {
        if ($0 ~ /^type:/)        { v = $0; sub(/^type:[ \t]*/, "", v);   gsub(/[ \t"]/, "", v); if (v != "") ftype = v }
        else if ($0 ~ /^status:/) { v = $0; sub(/^status:[ \t]*/, "", v); gsub(/[ \t"]/, "", v); if (v != "") fstatus = v }
        else if ($0 ~ /^tags:/)   { v = $0; sub(/^tags:[ \t]*/, "", v);   gsub(/[][ \t"]/, "", v); ftags = v }
      }
      END { flush() }
    ' 2>/dev/null |
		awk -F'\t' '
      $0 == "F" { n++ }
      $0 == "S" { sup++ }
      $1 == "T" { if ($2 == "feedback") rules++ }
      $1 == "G" {
        c = split($2, a, ",")
        for (i = 1; i <= c; i++) {
          t = a[i]
          if (t != "" && !(t in seen)) { seen[t] = 1; order[++m] = t }
        }
      }
      END {
        tags = ""
        lim = (m > 6 ? 6 : m)
        for (i = 1; i <= lim; i++) tags = tags (tags == "" ? "" : ", ") order[i]
        printf "%d\t%d\t%d\t%s\n", n + 0, rules + 0, sup + 0, substr(tags, 1, 90)
      }
    ' 2>/dev/null
) || SUMMARY=''

[ -n "$SUMMARY" ] || exit 0

COUNT=$(printf '%s' "$SUMMARY" | cut -f1)
RULES=$(printf '%s' "$SUMMARY" | cut -f2)
SUPERSEDED=$(printf '%s' "$SUMMARY" | cut -f3)
TAGS=$(printf '%s' "$SUMMARY" | cut -f4)

COUNT=$(eve_int "$COUNT" 0)
RULES=$(eve_int "$RULES" 0)
SUPERSEDED=$(eve_int "$SUPERSEDED" 0)
[ "$COUNT" -gt 0 ] || exit 0

OTHER=$((COUNT - RULES))
[ "$OTHER" -ge 0 ] || OTHER=0

# --- Last session ----------------------------------------------------------
#
# Session logs are named YYYY-MM-DD.md, so a plain name sort is a date sort.
# That is deterministic, unlike `ls -t`, and needs no stat call.

LAST_LINE=''
if [ -d "$EVE_SESSIONS_DIR" ]; then
	LAST_FILE=$(find "$EVE_SESSIONS_DIR" -type f -name '2*.md' 2>/dev/null | sort | tail -1)
	if [ -n "$LAST_FILE" ] && [ -r "$LAST_FILE" ]; then
		LAST_DATE=$(basename "$LAST_FILE" .md)
		ENTRIES=$(grep -c '<!-- eve:session' "$LAST_FILE" 2>/dev/null | tr -d ' ')
		ENTRIES=$(eve_int "$ENTRIES" 0)
		if [ "$ENTRIES" -gt 0 ]; then
			if [ "$ENTRIES" -eq 1 ]; then NOUN=entry; else NOUN=entries; fi
			LAST_LINE="Last session log: $LAST_DATE ($ENTRIES $NOUN) at $(eve_tilde "$EVE_SESSIONS_DIR")"
		fi
	fi
fi

# --- Optional Tier 2 brief -------------------------------------------------
#
# A brief older than two hours is worse than no brief: it asserts a "current
# focus" that has already moved, and the model has no way to know it is stale.
# Freshness is checked here rather than trusted from the file's contents.

BRIEF=''
BRIEF_FILE="$EVE_STATE_DIR/brief.md"
if [ -r "$BRIEF_FILE" ]; then
	AGE=$(eve_file_age "$BRIEF_FILE")
	if [ "$AGE" -lt 7200 ]; then
		BRIEF=$(sed -e 's/^[[:space:]]*//' "$BRIEF_FILE" 2>/dev/null |
			grep -v '^$' 2>/dev/null | head -3 | tr '\n' ' ' | cut -c1-220)
		eve_trim_var "$BRIEF"
		BRIEF=$_eve_r
	fi
fi

# --- Emit ------------------------------------------------------------------

{
	printf '<eve-session>\n'

	if [ "$SUPERSEDED" -gt 0 ]; then
		printf 'Memory store: %d memories at %s (%d rules, %d notes, %d superseded). Index: %s\n' \
			"$COUNT" "$(eve_tilde "$EVE_MEMORY_DIR")" "$RULES" "$OTHER" "$SUPERSEDED" \
			"$(eve_tilde "$EVE_HOME/INDEX.md")"
	else
		printf 'Memory store: %d memories at %s (%d rules, %d notes). Index: %s\n' \
			"$COUNT" "$(eve_tilde "$EVE_MEMORY_DIR")" "$RULES" "$OTHER" \
			"$(eve_tilde "$EVE_HOME/INDEX.md")"
	fi

	[ -n "$TAGS" ] && printf 'Standing rules exist for: %s\n' "$TAGS"
	[ -n "$LAST_LINE" ] && printf '%s\n' "$LAST_LINE"
	[ -n "$BRIEF" ] && printf 'Where you left off: %s\n' "$BRIEF"

	printf 'Relevant memories are injected automatically. Before proposing an approach, check the index; before asserting a fact about this project, search the store.\n'
	printf '</eve-session>\n'
} | eve_cap_block "$EVE_BRIEF_MAX_CHARS"

eve_debug "session-start: source=${SOURCE:-none} memories=$COUNT rules=$RULES"

exit 0
