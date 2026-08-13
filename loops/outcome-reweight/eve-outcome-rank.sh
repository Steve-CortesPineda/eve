#!/bin/sh
#
# eve-outcome-rank.sh - Tier 2 learning loop: outcome reweighting.
#
# CONSUMER: you, reading $EVE_HOME/proposals/outcomes-<date>.md -- specifically
# the list of decisions reality has never voted on. That list is the product.
#
# SECOND CONSUMER, CONDITIONAL: $EVE_HOME/state/weights.tsv is written only
# when you pass --write-weights, and you should pass it only if your `eve
# search` reads that file. Check first. A weights file that nothing multiplies
# by is the write-only producer in its purest form: a number computed every
# night, stored forever, and multiplied by nothing.
#
# PRODUCER: you, recording how a decision turned out, in either place --
#
#   frontmatter:  outcome: worked | failed | mixed
#                 outcome_date: 2026-05-02
#
#   or a body section, which is better because it holds more than one verdict:
#
#     ## Outcomes
#     - 2026-05-02 worked - duplicate-row reports went to zero.
#     - 2026-06-18 mixed - one caller had to be migrated by hand.
#
# WRITES: $EVE_HOME/proposals/outcomes-<date>.md   (regenerable)
#         $EVE_HOME/state/weights.tsv              (only with --write-weights)
# NEVER: edits a memory, deletes a memory, or proposes a deletion. This loop
# ranks. Ranking and deleting are different operations and this one is not
# allowed near the other.
#
# WHAT IT DELIBERATELY DOES NOT DO: it does not rank successful decisions above
# failed ones. See the note above the weight formula -- that is the tempting
# mistake, and it is backwards.
#
# POSIX sh, no dependencies.
#
set -eu

PROG=eve-outcome-rank

usage() {
  cat <<'USAGE'
usage: eve-outcome-rank.sh [options]

  --dry-run         print the report, write nothing
  --all             consider every memory, not only `type: decision`
  --stale-days N    a decision with no recorded outcome is "waiting" after N
                    days (default 90)
  --write-weights   also write state/weights.tsv. Only do this if your
                    retrieval actually reads it.
  --format md|tsv   report format (default md)
  --out FILE        write the proposal here
  -h, --help        this

Exit codes: 0 always (usage errors: 64).
USAGE
}

die_usage() { printf '%s: %s\n' "$PROG" "$1" >&2; usage >&2; exit 64; }

# ---------------------------------------------------------------- config ----
EVE_HOME=${EVE_HOME:-$HOME/.eve}
CFG="$EVE_HOME/config"

cfg() { # cfg KEY DEFAULT
  _k=$1; _d=$2; _v=
  case $_k in *[!A-Za-z0-9_]*) printf '%s' "$_d"; return 0 ;; esac
  eval "_v=\${$_k-}"
  if [ -n "$_v" ]; then printf '%s' "$_v"; return 0; fi
  if [ -f "$CFG" ]; then
    _v=$(sed -n "s/^[[:space:]]*$_k[[:space:]]*=[[:space:]]*//p" "$CFG" 2>/dev/null |
         sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' | sed -n '1p')
  fi
  [ -n "$_v" ] || _v=$_d
  printf '%s' "$_v"
}

STALE_DAYS=$(cfg EVE_OUTCOME_STALE_DAYS 90)
DRY=0; ALL=0; WEIGHTS=0; FORMAT=md; OUT=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run)       DRY=1 ;;
    --all)           ALL=1 ;;
    --write-weights) WEIGHTS=1 ;;
    --stale-days)    [ $# -ge 2 ] || die_usage "--stale-days needs a value"; STALE_DAYS=$2; shift ;;
    --format)        [ $# -ge 2 ] || die_usage "--format needs a value"; FORMAT=$2; shift ;;
    --out)           [ $# -ge 2 ] || die_usage "--out needs a value"; OUT=$2; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die_usage "unknown option: $1" ;;
  esac
  shift
done
case $STALE_DAYS in *[!0-9]*) die_usage "--stale-days must be a number" ;; esac
case $FORMAT in md|tsv) ;; *) die_usage "--format must be md or tsv" ;; esac

MEMDIR="$EVE_HOME/memory"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%s 2>/dev/null || printf '0')
[ -n "$OUT" ] || OUT="$EVE_HOME/proposals/outcomes-$TODAY.md"

if [ ! -d "$MEMDIR" ]; then
  printf '%s: no memory directory at %s\n' "$PROG" "$MEMDIR"
  exit 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/eve-outcome.XXXXXX") ||
  { printf '%s: mktemp failed\n' "$PROG" >&2; exit 0; }
trap 'rm -rf "$TMP"' EXIT INT HUP TERM

# BSD and GNU stat disagree about everything. One helper, three attempts, and a
# zero if the platform is stranger than both.
file_mtime() {
  stat -f %m "$1" 2>/dev/null && return 0
  stat -c %Y "$1" 2>/dev/null && return 0
  printf '0'
}

# YYYY-MM-DD -> epoch seconds, or 0. BSD date needs -j -f, GNU date needs -d,
# and neither accepts the other's spelling. Both are tried; a platform with
# neither gets 0, which downgrades an age to "unknown" and never to a wrong
# number that some threshold then acts on.
date_to_epoch() {
  case ${1:-} in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) printf '0'; return 0 ;;
  esac
  date -j -f '%Y-%m-%d' "$1" +%s 2>/dev/null && return 0
  date -d "$1" +%s 2>/dev/null && return 0
  printf '0'
}

# --------------------------------------------------------------- extract ----
# One record per memory:
#   id TAB type TAB nworked TAB nfailed TAB nmixed TAB ndates TAB last_date
#   TAB age_days TAB title
: > "$TMP/rows"
for f in "$MEMDIR"/*.md; do
  [ -f "$f" ] || continue
  id=$(basename "$f" .md)

  mtype=$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$f" 2>/dev/null |
          sed -n 's/^type:[[:space:]]*//p' | sed -n '1p' | tr -d '\r')
  [ -n "$mtype" ] || mtype=note
  if [ "$ALL" -eq 0 ] && [ "$mtype" != decision ]; then continue; fi

  title=$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$f" 2>/dev/null |
          sed -n 's/^title:[[:space:]]*//p' | sed -n '1p' | tr -d '\r' | tr '\t|' '  ')
  [ -n "$title" ] || title=$id

  created=$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$f" 2>/dev/null |
            sed -n 's/^created:[[:space:]]*//p' | sed -n '1p' | tr -d '\r')

  # Outcomes from both places, normalized to "DATE VERDICT" lines.
  {
    fm_o=$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$f" 2>/dev/null |
           sed -n 's/^outcome:[[:space:]]*//p' | sed -n '1p' | tr -d '\r')
    fm_d=$(sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$f" 2>/dev/null |
           sed -n 's/^outcome_date:[[:space:]]*//p' | sed -n '1p' | tr -d '\r')
    if [ -n "$fm_o" ]; then printf '%s %s\n' "${fm_d:-0000-00-00}" "$fm_o"; fi
    # Body: "- YYYY-MM-DD verdict - free text"
    #
    # This was a sed script with `\(worked\|failed\|mixed\)` in it. That is a
    # GNU extension; BSD sed does not implement it, does not complain about it,
    # and simply matches nothing. Every body outcome silently counted as zero,
    # the report was well-formatted and confidently wrong, and the only clue
    # was that a file with two recorded failures showed "0 failed". Alternation
    # belongs in awk's ERE, where every awk agrees what it means.
    awk '
      {
        line = $0
        sub(/^[ \t]+/, "", line)
        if (line !~ /^[-*][ \t]+/) next
        sub(/^[-*][ \t]+/, "", line)
        n = split(line, p, /[ \t]+/)
        if (n < 2) next
        d = p[1]; v = tolower(p[2])
        if (d !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) next
        if (v != "worked" && v != "failed" && v != "mixed") next
        print d, v
      }' "$f" 2>/dev/null
  } | tr 'A-Z' 'a-z' | sort -u > "$TMP/out.$id" || : > "$TMP/out.$id"

  nworked=$(awk '$2=="worked"' "$TMP/out.$id" | wc -l | tr -d ' ')
  nfailed=$(awk '$2=="failed"' "$TMP/out.$id" | wc -l | tr -d ' ')
  nmixed=$(awk  '$2=="mixed"'  "$TMP/out.$id" | wc -l | tr -d ' ')
  ndates=$(awk '$1 != "0000-00-00" {print $1}' "$TMP/out.$id" | sort -u | wc -l | tr -d ' ')
  last=$(awk '$1 != "0000-00-00" {print $1}' "$TMP/out.$id" | sort | tail -1)
  [ -n "$last" ] || last='-'

  # Age from `created` when it is there. mtime is what retrieval ranks on, but
  # for "how long has this gone unanswered" mtime is the wrong clock: fixing a
  # typo in a decision does not make it younger, and it certainly does not mean
  # anyone found out whether the decision worked.
  age=0
  cepoch=$(date_to_epoch "$created")
  if [ "$cepoch" -gt 0 ] && [ "$NOW" -gt "$cepoch" ]; then
    age=$(( (NOW - cepoch) / 86400 ))
  else
    mt=$(file_mtime "$f"); case $mt in ''|*[!0-9]*) mt=0 ;; esac
    if [ "$mt" -gt 0 ] && [ "$NOW" -gt "$mt" ]; then age=$(( (NOW - mt) / 86400 )); fi
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$id" "$mtype" "$nworked" "$nfailed" "$nmixed" "$ndates" "$last" "$age" "$title" >> "$TMP/rows"
done

NROWS=$(wc -l < "$TMP/rows" | tr -d ' ')
if [ "$NROWS" -eq 0 ]; then
  printf '%s: no %s memories in %s\n' "$PROG" \
    "$([ "$ALL" -eq 1 ] && printf 'readable' || printf 'type: decision')" "$MEMDIR"
  printf 'This loop has nothing to rank until decisions exist and outcomes are\n'
  printf 'recorded against them. It is the last loop to install, not the first.\n'
  exit 0
fi

# ---------------------------------------------------------------- weight ----
#
# The weight is a function of EVIDENCE, not of success.
#
# Weighting successful decisions up and failed ones down is the obvious design
# and it is backwards. When you ask "should we cache the parsed manifests in
# process memory?", the memory that earns its retrieval is the one recording
# that this was tried and it failed. Down-ranking it because the outcome was
# bad hides the single most useful thing the store contains, and the store
# starts telling you only what you want to hear -- a memory system with a
# survivorship bias built into its ranker.
#
# So: a decision reality has voted on outranks one nobody ever checked. The
# verdict itself does not move the number. The tally is printed because you
# want to read it; it is not multiplied by anything.
#
# Bounds are tight (0.80 .. 1.40) and the floor is well above zero, because
# this multiplier must never be able to bury a memory. Ranking is not deletion
# and must not become a slow version of it.
awk -F'\t' -v staled="$STALE_DAYS" '
{
  id=$1; ty=$2; w=$3+0; f=$4+0; m=$5+0; nd=$6+0; last=$7; age=$8+0; title=$9
  n = w + f + m
  weight = 1.00
  if (n >= 1)  weight += 0.25            # reality voted at least once
  if (nd >= 2) weight += 0.10            # and was revisited on another day
  # The untested-intention penalty applies to decisions only. Under --all it
  # was landing on every reference note in the store, which have no outcomes
  # because the concept does not apply to them -- "Harborlight uses cursor
  # pagination" is not waiting to find out how it went. A loop that penalizes
  # a file for not having a field it was never supposed to have is measuring
  # its own schema, not the world.
  if (ty == "decision" && n == 0 && age > staled) weight -= 0.10
  if (weight < 0.80) weight = 0.80
  if (weight > 1.40) weight = 1.40
  printf "%s\t%.2f\t%d\t%d\t%d\t%d\t%s\t%d\t%s\t%s\n", id, weight, w, f, m, nd, last, age, title, ty
}' "$TMP/rows" | sort -t"$(printf '\t')" -k2,2nr -k1,1 > "$TMP/ranked"

NDEC=$(awk -F'\t' '$10=="decision"' "$TMP/ranked" | wc -l | tr -d ' ')
NVERIFIED=$(awk -F'\t' '$3+$4+$5 > 0' "$TMP/ranked" | wc -l | tr -d ' ')
# "Waiting" is a statement about decisions. Counting reference notes here was
# how the summary line came to claim five memories were overdue for an outcome
# that none of them could ever have.
NWAITING=$(awk -F'\t' -v s="$STALE_DAYS" '$10=="decision" && $3+$4+$5 == 0 && $8+0 > s' "$TMP/ranked" | wc -l | tr -d ' ')
NYOUNG=$(awk -F'\t' -v s="$STALE_DAYS" '$10=="decision" && $3+$4+$5 == 0 && $8+0 <= s' "$TMP/ranked" | wc -l | tr -d ' ')

# ---------------------------------------------------------------- report ----
report_tsv() {
  printf '# id\tweight\tworked\tfailed\tmixed\toutcome_dates\tlast\tage_days\ttitle\ttype\n'
  cat "$TMP/ranked"
}

report_md() {
  printf '<!-- generated by eve-outcome-rank.sh on %s; regenerable -->\n\n' "$TODAY"
  printf '# Decisions, ranked by whether reality has voted - %s\n\n' "$TODAY"
  printf 'Memories considered: %s (decisions: %s)\n' "$NROWS" "$NDEC"
  printf 'With a recorded outcome: %s   Waiting over %s days: %s   Still young: %s\n\n' \
    "$NVERIFIED" "$STALE_DAYS" "$NWAITING" "$NYOUNG"

  printf '## Ranked\n\n'
  printf '| weight | id | worked | failed | mixed | last outcome |\n'
  printf '|---|---|---|---|---|---|\n'
  while IFS='	' read -r id weight w f m nd last age title ty; do
    printf '| %s | %s | %s | %s | %s | %s |\n' "$weight" "$id" "$w" "$f" "$m" "$last"
  done < "$TMP/ranked"
  printf '\n'
  printf 'The weight rises when a decision has been checked against reality and\n'
  printf 'falls slightly when one has sat untested. It does not rise for success\n'
  printf 'or fall for failure -- a decision that failed is often the most useful\n'
  printf 'file in the store, and a ranker that buries failures will happily tell\n'
  printf 'you to do the thing that did not work last time.\n\n'

  printf '## Waiting on reality (%s)\n\n' "$NWAITING"
  if [ "$NWAITING" -eq 0 ]; then
    printf 'Every decision older than %s days has at least one recorded outcome.\n\n' "$STALE_DAYS"
  else
    printf 'Asserted, never checked. This is the actionable list: pick one, find out\n'
    printf 'what happened, and add a line under `## Outcomes`.\n\n'
    printf '| id | age (days) | title |\n|---|---|---|\n'
    awk -F'\t' -v s="$STALE_DAYS" \
      '$10=="decision" && $3+$4+$5 == 0 && $8+0 > s {printf "| %s | %s | %s |\n", $1, $8, $9}' \
      "$TMP/ranked"
    printf '\n'
  fi

  printf '## What this loop will not do\n\n'
  printf -- '- It will not edit a memory. Recording an outcome is a human act;\n'
  printf '  something that guessed outcomes would be inventing evidence.\n'
  printf -- '- It will not propose deleting anything, including a decision whose\n'
  printf '  every outcome is `failed`. That file is the reason nobody repeats it.\n'
  printf -- '- It will not weight below %s. A multiplier that can reach zero is a\n' '0.80'
  printf '  deletion with extra steps.\n\n'

  if [ "$WEIGHTS" -eq 1 ]; then
    printf '## weights.tsv\n\n'
    printf 'Written to `%s`. It is inert unless your retrieval multiplies by it.\n\n' \
      "$EVE_HOME/state/weights.tsv"
  fi
}

emit() { if [ "$FORMAT" = tsv ]; then report_tsv; else report_md; fi; }

if [ "$DRY" -eq 1 ]; then
  emit
  printf '\n[dry run] nothing written.\n'
  exit 0
fi

mkdir -p "$(dirname "$OUT")"
emit > "$OUT.tmp$$" && mv "$OUT.tmp$$" "$OUT"

if [ "$WEIGHTS" -eq 1 ]; then
  mkdir -p "$EVE_HOME/state"
  {
    printf '# generated by eve-outcome-rank.sh on %s -- do not edit\n' "$TODAY"
    printf '# id<TAB>weight. Inert unless something multiplies by it.\n'
    awk -F'\t' '{printf "%s\t%s\n", $1, $2}' "$TMP/ranked"
  } > "$EVE_HOME/state/weights.tsv.tmp$$" &&
    mv "$EVE_HOME/state/weights.tsv.tmp$$" "$EVE_HOME/state/weights.tsv"
  printf '%s: wrote %s/state/weights.tsv -- confirm something reads it\n' "$PROG" "$EVE_HOME"
fi

printf '%s: %s ranked, %s verified, %s waiting -> %s\n' \
  "$PROG" "$NROWS" "$NVERIFIED" "$NWAITING" "$OUT"
exit 0
