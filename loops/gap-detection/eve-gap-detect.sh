#!/bin/sh
#
# eve-gap-detect.sh - Tier 2 learning loop: gap detection.
#
# CONSUMER: you, reading $EVE_HOME/proposals/gaps-<date>.md, and the memories
# you write because of it. That is the whole consumer list. If you go two
# review cycles without writing a memory or running --ignore in response to
# this report, the loop has no consumer any more: turn it off (see README).
#
# PRODUCER: hooks/eve-recall.sh, which appends one line to
# $EVE_HOME/state/whiffs.log every time a substantive prompt retrieved nothing.
# The signal is free - every prompt already generates it.
#
# WRITES: $EVE_HOME/proposals/gaps-<date>.md (regenerable, marked generated)
#         $EVE_HOME/state/gap-ignore        (only via --ignore)
# NEVER WRITES: $EVE_HOME/memory/. Nothing automatic writes a memory.
#
# Standalone by design: this file duplicates ~30 lines of config handling that
# other Eve scripts also contain, so you can copy it out of the repo on its own
# and it still runs. POSIX sh; no bashisms, no jq, no network.
#
set -eu
# Note: `set -o pipefail` is not POSIX and is absent from dash. Every pipeline
# below is written so a failing stage yields empty output, not a wrong answer.

PROG=eve-gap-detect

usage() {
  cat <<'USAGE'
usage: eve-gap-detect.sh [options]

  --dry-run           print the report to stdout and write nothing (default is
                      to also write the proposal file)
  --since DAYS        only consider whiffs from the last DAYS days (default 30)
  --min-hits N        a term is a gap after N whiffs (default 3)
  --min-days N        ...spread over N distinct days (default 2)
  --no-probe          skip checking whether a memory already covers the term
  --ignore TERM       record TERM as deliberately-not-worth-documenting and exit
  --out FILE          write the proposal here instead of the default path
  -h, --help          this

Exit codes: 0 report produced (with or without gaps), 64 usage error.
USAGE
}

die_usage() { printf '%s: %s\n' "$PROG" "$1" >&2; usage >&2; exit 64; }

# ---------------------------------------------------------------- config ----
# Environment wins over the config file, which wins over the default. Config is
# parsed in-process; it is never sourced, so a stray line in it cannot execute.
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

MIN_HITS=$(cfg EVE_GAP_MIN_HITS 3)
MIN_DAYS=$(cfg EVE_GAP_MIN_DAYS 2)
SINCE_DAYS=$(cfg EVE_GAP_SINCE_DAYS 30)
PROBE=1
DRY=0
OUT=

while [ $# -gt 0 ]; do
  case $1 in
    --dry-run)   DRY=1 ;;
    --no-probe)  PROBE=0 ;;
    --since)     [ $# -ge 2 ] || die_usage "--since needs a value"; SINCE_DAYS=$2; shift ;;
    --min-hits)  [ $# -ge 2 ] || die_usage "--min-hits needs a value"; MIN_HITS=$2; shift ;;
    --min-days)  [ $# -ge 2 ] || die_usage "--min-days needs a value"; MIN_DAYS=$2; shift ;;
    --out)       [ $# -ge 2 ] || die_usage "--out needs a value"; OUT=$2; shift ;;
    --ignore)    [ $# -ge 2 ] || die_usage "--ignore needs a value"; IGNORE_TERM=$2; shift
                 mkdir -p "$EVE_HOME/state"
                 printf '%s\n' "$IGNORE_TERM" >> "$EVE_HOME/state/gap-ignore"
                 printf 'recorded: "%s" will be skipped in future reports (%s)\n' \
                   "$IGNORE_TERM" "$EVE_HOME/state/gap-ignore"
                 exit 0 ;;
    -h|--help)   usage; exit 0 ;;
    *)           die_usage "unknown option: $1" ;;
  esac
  shift
done

case $MIN_HITS$MIN_DAYS$SINCE_DAYS in *[!0-9]*) die_usage "numeric options must be numbers" ;; esac

WHIFFS="$EVE_HOME/state/whiffs.log"
MEMDIR="$EVE_HOME/memory"
TODAY=$(date +%Y-%m-%d)
[ -n "$OUT" ] || OUT="$EVE_HOME/proposals/gaps-$TODAY.md"

if [ ! -f "$WHIFFS" ]; then
  printf '%s: no whiff log at %s\n' "$PROG" "$WHIFFS"
  printf 'Nothing to analyse. The recall hook writes this file; if it exists and is\n'
  printf 'empty, retrieval is finding something for every prompt, which is the\n'
  printf 'outcome you wanted.\n'
  exit 0
fi

# ----------------------------------------------------------- portability ----
days_ago() { # days_ago N -> YYYY-MM-DD, or empty if neither date(1) dialect works
  date -v-"$1"d +%Y-%m-%d 2>/dev/null && return 0
  date -d "$1 days ago" +%Y-%m-%d 2>/dev/null && return 0
  printf ''
}
SINCE=$(days_ago "$SINCE_DAYS")

TMP=$(mktemp -d "${TMPDIR:-/tmp}/eve-gaps.XXXXXX") || { printf '%s: mktemp failed\n' "$PROG" >&2; exit 0; }
trap 'rm -rf "$TMP"' EXIT INT HUP TERM

# ---------------------------------------------------------------- ignore ----
: > "$TMP/ignore"
if [ -f "$EVE_HOME/state/gap-ignore" ]; then
  sed -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$EVE_HOME/state/gap-ignore" |
    tr 'A-Z' 'a-z' | sort -u > "$TMP/ignore" || : > "$TMP/ignore"
fi
IGNORED=$(wc -l < "$TMP/ignore" | tr -d ' ')

# ------------------------------------------------------------- aggregate ----
# One pass. Emits two record kinds on stdout:
#   T <term> <hits> <days> <first> <last>
#   S <signature> <hits> <days>
# A "signature" is the sorted set of significant terms in one whiff line,
# capped at four. Two prompts that whiffed on the same underlying question
# collapse to the same signature; that is the clustering.
# The stopword list is assembled one line at a time on purpose. It is passed to
# awk with -v, and the awk that ships on macOS (BWK awk) rejects a -v value
# containing a literal newline: "awk: newline in string". Written as a single
# quoted paragraph this aggregation died on every stock Mac, stderr went to
# /dev/null, and the report printed "None above threshold" in a confident tone.
# The check further down that refuses to report an empty result when the input
# was not empty exists because of that afternoon.
STOPWORDS='the a an and or but not is are was were be been being do does did done'
STOPWORDS="$STOPWORDS have has had can could should would will shall may might must"
STOPWORDS="$STOPWORDS i we you he she it they them this that these those there here"
STOPWORDS="$STOPWORDS what when where why how which who whom whose to of in on at by"
STOPWORDS="$STOPWORDS for from with without into onto about after before during under"
STOPWORDS="$STOPWORDS over again further then once all any both each few more most"
STOPWORDS="$STOPWORDS other some such no nor only own same so than too very just now"
STOPWORDS="$STOPWORDS get got set use used using need needs make made work works new"
STOPWORDS="$STOPWORDS old like want please help thing things way ways doesnt dont"
STOPWORDS="$STOPWORDS cant wont im ive ill lets let us my our your their his her its"
STOPWORDS="$STOPWORDS also still even much many lot really actually basically"
STOPWORDS="$STOPWORDS per via out off yet ago one two see run day days"

awk -v since="$SINCE" -v stopwords="$STOPWORDS" '
BEGIN {
  FS = "\t"
  n = split(stopwords, sw, /[ \t\n]+/)
  for (i = 1; i <= n; i++) if (sw[i] != "") stop[sw[i]] = 1
  kept = 0; total = 0
}
{ sub(/\r$/, "") }
/^[[:space:]]*#/ { next }
/^[[:space:]]*$/ { next }
{
  total++
  ts = ""; terms = ""
  if (NF >= 3) { ts = $1; for (i = 3; i <= NF; i++) terms = terms " " $i }
  else if (NF == 2) { ts = $1; terms = $2 }
  else { terms = $0 }

  # tolerate a log with no tabs but a leading timestamp
  if (ts == "" && terms ~ /^[[:space:]]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) {
    sub(/^[[:space:]]*/, "", terms)
    ts = terms; sub(/[[:space:]].*$/, "", ts)
    sub(/^[^[:space:]]+[[:space:]]*/, "", terms)
  }
  day = "?"
  if (ts ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) day = substr(ts, 1, 10)
  if (since != "" && day != "?" && day < since) next
  kept++

  low = tolower(terms)
  gsub(/[^a-z0-9]+/, " ", low)
  ntok = split(low, tok, " ")
  split("", seen); nu = 0; split("", uniq)
  for (i = 1; i <= ntok; i++) {
    t = tok[i]
    if (length(t) < 3) continue
    if (t in stop) continue
    if (t in seen) continue
    seen[t] = 1; uniq[++nu] = t
  }
  if (nu == 0) next

  for (i = 1; i <= nu; i++) {
    t = uniq[i]
    hits[t]++
    if (day != "?") {
      if (!((t SUBSEP day) in daymark)) { daymark[t SUBSEP day] = 1; days[t]++ }
      if (!(t in first) || day < first[t]) first[t] = day
      if (!(t in last)  || day > last[t])  last[t]  = day
    }
  }

  # Cluster on term PAIRS, not on the whole line.
  #
  # The first version of this signed each whiff with its full sorted term set.
  # That looks tidier and clusters nothing: two people asking the same question
  # in different words share two or three words, never all of them, so every
  # signature had a count of one and the section was permanently empty. Pairs
  # recur. "webhook+retry" is the question; "webhook retry storm after an
  # outage" is one phrasing of it.
  #
  # Cap by order of appearance, then sort each pair when naming it.
  #
  # Sorting the whole term list first and then taking the first six is the
  # obvious way to write this and it is quietly biased: on any prompt with more
  # than six significant words, every term late in the alphabet is discarded.
  # In the fixture that undercounted "webhook" by more than half while
  # "backfill" was never once dropped. The cap has to be alphabet-blind; only
  # the pair NAME needs an order, so that a+b and b+a are the same cluster.
  cap = (nu > 6) ? 6 : nu   # bounds pairs per line at 15
  for (i = 1; i <= cap; i++) {
    for (j = i + 1; j <= cap; j++) {
      a = uniq[i]; b = uniq[j]
      sig = (a < b) ? a "+" b : b "+" a
      sighits[sig]++
      if (day != "?" && !((sig SUBSEP day) in sigday)) { sigday[sig SUBSEP day] = 1; sigdays[sig]++ }
    }
  }
}
END {
  printf "M\t%d\t%d\n", total, kept
  for (t in hits) printf "T\t%s\t%d\t%d\t%s\t%s\n", t, hits[t], days[t] + 0,
    (t in first ? first[t] : "-"), (t in last ? last[t] : "-")
  for (s in sighits) printf "S\t%s\t%d\t%d\n", s, sighits[s], sigdays[s] + 0
}
' "$WHIFFS" > "$TMP/agg" 2>"$TMP/err" || : > "$TMP/agg"

TOTAL=$(awk -F'\t' '$1=="M"{print $2; exit}' "$TMP/agg"); [ -n "$TOTAL" ] || TOTAL=0
KEPT=$(awk -F'\t'  '$1=="M"{print $3; exit}' "$TMP/agg"); [ -n "$KEPT" ]  || KEPT=0

# Sanity check on the premise, before any conclusion is drawn from the result.
# "No gaps found" and "the analysis did not run" produce the same empty output,
# and only one of them is good news. If the log had usable lines and the
# aggregation produced no record, say so and stop: a loop that reports a clean
# bill of health when its own analysis crashed is worse than a loop that fails.
if [ "$TOTAL" -eq 0 ] && grep -qv -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$WHIFFS" 2>/dev/null; then
  printf '%s: the whiff log has lines but the analysis produced nothing.\n' "$PROG" >&2
  printf 'This is a bug in this script or an incompatible awk, not an empty result.\n' >&2
  if [ -s "$TMP/err" ]; then
    printf 'awk said: %s\n' "$(sed -n '1p' "$TMP/err")" >&2
  fi
  printf 'Refusing to report "no gaps" from an analysis that did not run.\n' >&2
  exit 0
fi

# thresholds + ignore list
awk -F'\t' -v mh="$MIN_HITS" -v md="$MIN_DAYS" '$1=="T" && $3+0>=mh && $4+0>=md {print}' "$TMP/agg" |
  sort -t"$(printf '\t')" -k3,3nr -k4,4nr > "$TMP/terms.all" || : > "$TMP/terms.all"
if [ -s "$TMP/ignore" ]; then
  awk -F'\t' 'NR==FNR{ig[$0]=1;next} !($2 in ig)' "$TMP/ignore" "$TMP/terms.all" > "$TMP/terms" || cp "$TMP/terms.all" "$TMP/terms"
else
  cp "$TMP/terms.all" "$TMP/terms"
fi
awk -F'\t' -v mh="$MIN_HITS" -v md="$MIN_DAYS" '$1=="S" && $3+0>=mh && $4+0>=md {print}' "$TMP/agg" |
  sort -t"$(printf '\t')" -k3,3nr > "$TMP/sigs" || : > "$TMP/sigs"

# ----------------------------------------------------------------- probe ----
# A gap that a memory now answers is not a gap - it is a whiff from before you
# wrote the file. Probing through `eve search` (not grep) is deliberate: the
# question is "would retrieval find it", not "does the string appear somewhere".
: > "$TMP/open"; : > "$TMP/closed"
probes=0
PROBER=none
[ "$PROBE" -eq 1 ] && {
  if [ -x "$EVE_HOME/bin/eve" ]; then PROBER=search
  elif [ -d "$MEMDIR" ]; then PROBER=substring
  fi
}
while IFS='	' read -r kind term hits days first last; do
  [ "$kind" = "T" ] || continue
  cover=
  if [ "$PROBER" != none ] && [ "$probes" -lt 20 ]; then
    probes=$((probes + 1))
    if [ "$PROBER" = search ]; then
      cover=$("$EVE_HOME/bin/eve" search --query "$term" --limit 1 --format tsv 2>/dev/null |
              awk -F'\t' 'NR==1 && NF>=3 {print $3; exit}' || true)
    else
      # Word-bounded, because the unbounded version reported "rate" as covered
      # on the strength of the word "separate". A probe that cannot tell a word
      # from a substring will retire real gaps, which is the expensive failure:
      # a missed gap is quiet, and you never learn what you did not write down.
      cover=$(grep -rilE "(^|[^A-Za-z0-9])$(printf '%s' "$term" |
                sed 's/[^A-Za-z0-9]/./g')([^A-Za-z0-9]|\$)" "$MEMDIR" 2>/dev/null |
              sed -n '1p' || true)
    fi
  fi
  if [ -n "$cover" ]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$term" "$hits" "$days" "$first" "$last" "$(basename "$cover")" >> "$TMP/closed"
  else
    printf '%s\t%s\t%s\t%s\t%s\n' "$term" "$hits" "$days" "$first" "$last" >> "$TMP/open"
  fi
done < "$TMP/terms"

NOPEN=$(wc -l < "$TMP/open" | tr -d ' ')
NCLOSED=$(wc -l < "$TMP/closed" | tr -d ' ')
NSIG=$(wc -l < "$TMP/sigs" | tr -d ' ')

# ---------------------------------------------------------------- report ----
slugify() { printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//'; }

report() {
  printf '<!-- generated by eve-gap-detect.sh on %s; regenerable, edit nothing here -->\n\n' "$TODAY"
  printf '# What this memory does not know - %s\n\n' "$TODAY"
  printf 'Source: `%s` (%s lines, %s inside the window)\n' "$WHIFFS" "$TOTAL" "$KEPT"
  printf 'Window: %s  Thresholds: >=%s whiffs on >=%s distinct days' \
    "${SINCE:-all time}" "$MIN_HITS" "$MIN_DAYS"
  [ "$IGNORED" -gt 0 ] && printf '  (%s term(s) on the ignore list)' "$IGNORED"
  printf '\n'
  case $PROBER in
    search)    printf 'Coverage probe: `eve search` (asks the question retrieval would ask)\n' ;;
    substring) printf 'Coverage probe: word-bounded grep -- `bin/eve` was not executable, so\n'
               printf 'coverage below is "the word appears in a file", not "retrieval finds it".\n' ;;
    none)      printf 'Coverage probe: skipped (--no-probe). Nothing here is checked against\n'
               printf 'the store, so a term you documented last week will still be listed.\n' ;;
  esac
  printf '\n'

  printf '## Open gaps\n\n'
  if [ "$NOPEN" -eq 0 ]; then
    printf 'None above threshold. Either retrieval is covering the questions you\n'
    printf 'actually ask, or the window is too short. Lower --min-hits before you\n'
    printf 'conclude anything.\n\n'
  else
    printf '| term | whiffs | days | first | last | write it |\n'
    printf '|---|---|---|---|---|---|\n'
    while IFS='	' read -r term hits days first last; do
      printf '| %s | %s | %s | %s | %s | `eve add %s` |\n' \
        "$term" "$hits" "$days" "$first" "$last" "$(slugify "$term")"
    done < "$TMP/open"
    printf '\n'
  fi

  printf '## Recurring question shapes\n\n'
  if [ "$NSIG" -eq 0 ]; then
    printf 'No repeated combination of terms cleared the threshold. Single-term\n'
    printf 'gaps above are still worth reading.\n\n'
  else
    printf 'Pairs of terms that whiffed together. A pair is closer to the question\n'
    printf 'you were actually asking than either word alone, so write the memory\n'
    printf 'against the pair and the two single-term rows above close with it.\n\n'
    printf '| terms | whiffs | days |\n'
    printf '|---|---|---|\n'
    while IFS='	' read -r kind sig hits days; do
      [ "$kind" = "S" ] || continue
      printf '| %s | %s | %s |\n' "$(printf '%s' "$sig" | tr '+' ' ')" "$hits" "$days"
    done < "$TMP/sigs"
    printf '\n'
  fi

  if [ "$NCLOSED" -gt 0 ]; then
    printf '## Probably already closed\n\n'
    printf 'These whiffed, but retrieval now finds a memory for them - most likely\n'
    printf 'you wrote the file after the whiff. Verify one before trusting the rest.\n\n'
    printf '| term | whiffs | now answered by |\n'
    printf '|---|---|---|\n'
    while IFS='	' read -r term hits days first last cover; do
      printf '| %s | %s | %s |\n' "$term" "$hits" "$cover"
    done < "$TMP/closed"
    printf '\n'
  fi

  printf '## What to do with this\n\n'
  printf 'Pick at most two open gaps and write the memory. Not all of them - a\n'
  printf 'report you act on partially is a working loop; a report you read and\n'
  printf 'admire is a write-only producer.\n\n'
  printf 'For a gap you have decided is not worth documenting:\n\n'
  printf '    eve-gap-detect.sh --ignore "<term>"\n\n'
  printf 'That is what makes this converge instead of nagging forever.\n'
}

if [ "$DRY" -eq 1 ]; then
  report
  printf '\n[dry run] nothing written. Drop --dry-run to write %s\n' "$OUT"
else
  mkdir -p "$(dirname "$OUT")"
  report > "$OUT.tmp$$" && mv "$OUT.tmp$$" "$OUT"
  printf '%s: %s open gap(s), %s cluster(s), %s likely closed -> %s\n' \
    "$PROG" "$NOPEN" "$NSIG" "$NCLOSED" "$OUT"
fi
exit 0
