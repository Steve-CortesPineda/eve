#!/bin/sh
#
# eve-reconcile.sh - Tier 2 learning loop: reality reconciliation.
#
# CONSUMER: you, reading $EVE_HOME/proposals/reconcile-<date>.md and deciding
# what to rewrite. Secondary consumer: the model, which sees an `eve:stale`
# marker inline when it opens or retrieves a file that failed verification.
# Those are the only two. If nobody reads the proposal file and you never run
# --apply, this loop is a cron job that warms your CPU: turn it off.
#
# PRODUCER: you, by putting check markers in memory files:
#
#     <!-- eve:check file /opt/harborlight/fixtures/manifests.jsonl -->
#     <!-- eve:check dir  /srv/harborlight -->
#     <!-- eve:check cmd  harborctl -->
#     <!-- eve:check host staging.harborlight.internal -->   (needs --net)
#     <!-- eve:check url  https://staging.harborlight.internal/healthz -->
#
# A memory with no markers is never checked. That is deliberate: the loop
# verifies claims you chose to make checkable, not everything you wrote.
#
# WRITES: $EVE_HOME/proposals/reconcile-<date>.md   (regenerable)
#         $EVE_HOME/state/reconcile-streaks.tsv     (consecutive-failure counts)
#         $EVE_HOME/state/reconcile-audit.log       (every write, with an undo)
#         $EVE_HOME/state/reconcile-backups/        (pre-edit copy of each file)
#         a single `eve:stale` comment line inside a memory file -- ONLY with
#         --apply, ONLY after a failure repeats, and always after a backup.
# NEVER: deletes a memory, edits frontmatter, changes prose, or removes a claim.
#
# IT DOES NOT EXECUTE ANYTHING FROM A MEMORY FILE. `cmd` resolves a name on
# PATH with `command -v`; it never runs the program. Memory files are ordinary
# files that any process -- or any prompt injection that got as far as a write
# tool -- can append to, so a marker is a request to LOOK, never to RUN.
#
# Standalone by design: no jq, no python, no network unless you ask for it.
# POSIX sh.
#
set -eu

PROG=eve-reconcile

usage() {
  cat <<'USAGE'
usage: eve-reconcile.sh [options]

  --dry-run        print the report, write nothing at all (not even streaks)
  --net            also run host/url checks (off by default: a laptop on the
                   wrong network would otherwise "discover" that production
                   has been decommissioned)
  --apply          allow the two automatic edits: add an eve:stale marker to a
                   check that has failed on N consecutive runs, and remove a
                   marker whose check now passes. Backed up and logged.
  --streak N       consecutive failing runs before --apply will mark (default 3)
  --min-gap SECS   minimum seconds between runs for a run to count toward a
                   streak (default 3600; stops `for i in 1 2 3` from being
                   mistaken for evidence)
  --list-stale     list files currently carrying an eve:stale marker, and exit
  --reset KEY      clear the streak for one check key, and exit
  --out FILE       write the proposal here
  -h, --help       this

Exit codes: 0 always (usage errors: 64).
USAGE
}

die_usage() { printf '%s: %s\n' "$PROG" "$1" >&2; usage >&2; exit 64; }

# ---------------------------------------------------------------- config ----
# Parsed in-process, never sourced. Environment beats file beats default.
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

STREAK_N=$(cfg EVE_RECONCILE_STREAK 3)
MIN_GAP=$(cfg EVE_RECONCILE_MIN_GAP_SECS 3600)
MAX_FAIL_PCT=$(cfg EVE_RECONCILE_MAX_FAIL_PCT 50)
CONTROL_HOST=$(cfg EVE_RECONCILE_CONTROL_HOST example.com)

DRY=0; NET=0; APPLY=0; OUT=
while [ $# -gt 0 ]; do
  case $1 in
    --dry-run)    DRY=1 ;;
    --net)        NET=1 ;;
    --apply)      APPLY=1 ;;
    --streak)     [ $# -ge 2 ] || die_usage "--streak needs a value"; STREAK_N=$2; shift ;;
    --min-gap)    [ $# -ge 2 ] || die_usage "--min-gap needs a value"; MIN_GAP=$2; shift ;;
    --out)        [ $# -ge 2 ] || die_usage "--out needs a value"; OUT=$2; shift ;;
    --list-stale) LIST=1 ;;
    --reset)      [ $# -ge 2 ] || die_usage "--reset needs a key"; RESET=$2; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            die_usage "unknown option: $1" ;;
  esac
  shift
done
case $STREAK_N$MIN_GAP$MAX_FAIL_PCT in *[!0-9]*) die_usage "numeric options must be numbers" ;; esac

MEMDIR="$EVE_HOME/memory"
STATE="$EVE_HOME/state"
STREAKS="$STATE/reconcile-streaks.tsv"
AUDIT="$STATE/reconcile-audit.log"
BACKUPS="$STATE/reconcile-backups"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%s 2>/dev/null || printf '0')
[ -n "$OUT" ] || OUT="$EVE_HOME/proposals/reconcile-$TODAY.md"

if [ ! -d "$MEMDIR" ]; then
  printf '%s: no memory directory at %s\n' "$PROG" "$MEMDIR"
  exit 0
fi

# --list-stale / --reset are read-mostly side doors; handle and leave.
if [ "${LIST:-0}" = 1 ]; then
  found=0
  # shellcheck disable=SC2044
  for f in "$MEMDIR"/*.md; do
    [ -f "$f" ] || continue
    if grep -q 'eve:stale' "$f" 2>/dev/null; then
      found=1
      printf '%s\n' "$(basename "$f")"
      sed -n 's/^[[:space:]]*<!--[[:space:]]*eve:stale[[:space:]]*/    /p' "$f" |
        sed 's/[[:space:]]*-->[[:space:]]*$//'
    fi
  done
  [ "$found" = 1 ] || printf 'No memory carries an eve:stale marker.\n'
  exit 0
fi
if [ -n "${RESET:-}" ]; then
  if [ -f "$STREAKS" ]; then
    awk -F'\t' -v k="$RESET" '$1 != k' "$STREAKS" > "$STREAKS.tmp$$" &&
      mv "$STREAKS.tmp$$" "$STREAKS"
  fi
  printf 'streak cleared for: %s\n' "$RESET"
  exit 0
fi

TMP=$(mktemp -d "${TMPDIR:-/tmp}/eve-reconcile.XXXXXX") ||
  { printf '%s: mktemp failed\n' "$PROG" >&2; exit 0; }
trap 'rm -rf "$TMP"' EXIT INT HUP TERM

# ------------------------------------------------------- collect markers ----
# One record per marker: file <TAB> lineno <TAB> kind <TAB> arg
: > "$TMP/checks"
: > "$TMP/unsafe"
for f in "$MEMDIR"/*.md; do
  [ -f "$f" ] || continue
  grep -n 'eve:check' "$f" 2>/dev/null | while IFS= read -r hit; do
    ln=${hit%%:*}
    body=${hit#*:}
    # <!-- eve:check KIND ARG -->  ->  "KIND ARG"
    spec=$(printf '%s' "$body" |
      sed -n 's/.*<!--[[:space:]]*eve:check[[:space:]]\{1,\}\(.*\)-->.*/\1/p' |
      sed 's/[[:space:]]*$//')
    [ -n "$spec" ] || continue
    kind=${spec%%[! ]*}; kind=${spec%% *}
    arg=${spec#* }
    [ "$arg" != "$spec" ] || arg=''
    case $kind in file|dir|cmd|host|url) ;; *)
      printf '%s\t%s\t%s\n' "$(basename "$f")" "$ln" "unknown kind: $spec" >> "$TMP/unsafe"; continue ;;
    esac
    [ -n "$arg" ] || {
      printf '%s\t%s\t%s\n' "$(basename "$f")" "$ln" "empty argument: $spec" >> "$TMP/unsafe"; continue; }
    # Reject anything that looks like it wants a shell. Nothing here is ever
    # passed to a shell, so this is belt and braces -- but a marker containing
    # a backtick is a signal about the file, not a check worth running.
    case $arg in
      *'$('*|*'`'*|*';'*|*'|'*|*'&'*|*'>'*|*'<'*|*'*'*|*'?'*)
        printf '%s\t%s\t%s\n' "$(basename "$f")" "$ln" "shell metacharacter in argument: $spec" >> "$TMP/unsafe"
        continue ;;
    esac
    if [ "$kind" = cmd ]; then
      case $arg in
        */*|*' '*|'')
          printf '%s\t%s\t%s\n' "$(basename "$f")" "$ln" "cmd takes a bare name: $spec" >> "$TMP/unsafe"
          continue ;;
      esac
    fi
    printf '%s\t%s\t%s\t%s\n' "$f" "$ln" "$kind" "$arg" >> "$TMP/checks"
  done
done

NCHECKS=$(wc -l < "$TMP/checks" | tr -d ' ')
NUNSAFE=$(wc -l < "$TMP/unsafe" | tr -d ' ')
if [ "$NCHECKS" -eq 0 ]; then
  printf '%s: no eve:check markers in %s\n' "$PROG" "$MEMDIR"
  printf 'Add one to a memory that asserts something checkable, e.g.\n'
  printf '    <!-- eve:check cmd harborctl -->\n'
  [ "$NUNSAFE" -eq 0 ] || printf '(%s marker(s) were rejected as malformed; run with markers fixed)\n' "$NUNSAFE"
  exit 0
fi

# ----------------------------------------------------- premise sanity ----
# Everything below decides whether a FAILURE means anything. Repeating a probe
# three times does not make it true; it makes it consistently wrong. Before a
# single failure is believed, the run has to establish that the machine it is
# running on is capable of passing.
PREMISE=ok
PREMISE_WHY=
[ -d / ] || { PREMISE=broken; PREMISE_WHY="the root directory did not test as a directory"; }
command -v sh >/dev/null 2>&1 || { PREMISE=broken; PREMISE_WHY="sh is not on PATH"; }

NET_OK=0
NET_WHY='network checks not requested (--net)'
if [ "$NET" -eq 1 ]; then
  if command -v curl >/dev/null 2>&1 || command -v host >/dev/null 2>&1 ||
     command -v nslookup >/dev/null 2>&1 || command -v ping >/dev/null 2>&1; then
    if resolve_probe_out=$( (host "$CONTROL_HOST" || nslookup "$CONTROL_HOST" ||
                             ping -c1 -W1 "$CONTROL_HOST") 2>/dev/null ); then
      NET_OK=1; NET_WHY="control host $CONTROL_HOST resolved"
    else
      NET_WHY="control host $CONTROL_HOST did not resolve -- treating this machine as offline"
    fi
    unset resolve_probe_out
  else
    NET_WHY='no curl/host/nslookup/ping available'
  fi
fi

# ------------------------------------------------------------ run checks ----
# status is one of: pass fail skip
: > "$TMP/results"
run_check() { # kind arg -> prints "pass|fail|skip<TAB>detail"
  _kind=$1; _arg=$2
  case $_kind in
    file)
      case $_arg in "~/"*) _arg="$HOME/${_arg#\~/}" ;; esac
      if [ -f "$_arg" ]; then printf 'pass\texists'; else printf 'fail\tno such file'; fi ;;
    dir)
      case $_arg in "~/"*) _arg="$HOME/${_arg#\~/}" ;; esac
      if [ -d "$_arg" ]; then printf 'pass\texists'; else printf 'fail\tno such directory'; fi ;;
    cmd)
      # Resolves the name. Does not run it, with or without arguments.
      if command -v "$_arg" >/dev/null 2>&1; then printf 'pass\ton PATH'; else printf 'fail\tnot on PATH'; fi ;;
    host)
      if [ "$NET_OK" -eq 0 ]; then printf 'skip\t%s' "$NET_WHY"; return 0; fi
      if (host "$_arg" || nslookup "$_arg" || ping -c1 -W1 "$_arg") >/dev/null 2>&1
      then printf 'pass\tresolves'; else printf 'fail\tdoes not resolve'; fi ;;
    url)
      if [ "$NET_OK" -eq 0 ]; then printf 'skip\t%s' "$NET_WHY"; return 0; fi
      if ! command -v curl >/dev/null 2>&1; then printf 'skip\tno curl'; return 0; fi
      if curl -sS -o /dev/null -I --max-time 8 "$_arg" >/dev/null 2>&1
      then printf 'pass\tresponded'; else printf 'fail\tno response'; fi ;;
    *) printf 'skip\tunknown kind' ;;
  esac
}

while IFS='	' read -r file ln kind arg; do
  [ -n "${kind:-}" ] || continue
  if [ "$PREMISE" != ok ]; then
    res="skip	premise check failed"
  else
    res=$(run_check "$kind" "$arg")
  fi
  st=${res%%	*}; detail=${res#*	}
  key="$(basename "$file")|$kind|$arg"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$st" "$key" "$file" "$ln" "$kind" "$arg" "$detail" >> "$TMP/results"
done < "$TMP/checks"

NPASS=$(awk -F'\t' '$1=="pass"' "$TMP/results" | wc -l | tr -d ' ')
NFAIL=$(awk -F'\t' '$1=="fail"' "$TMP/results" | wc -l | tr -d ' ')
NSKIP=$(awk -F'\t' '$1=="skip"' "$TMP/results" | wc -l | tr -d ' ')
NRUN=$((NPASS + NFAIL))

# Mass failure means the premise is wrong, not that the world changed. A laptop
# with an unmounted volume, a fresh checkout, the wrong machine: all of these
# fail most checks at once. One claim going stale is news; all of them going
# stale at the same instant is a story about the observer.
INCONCLUSIVE=0
if [ "$PREMISE" != ok ]; then
  INCONCLUSIVE=1; PREMISE_WHY=${PREMISE_WHY:-unknown}
elif [ "$NRUN" -gt 0 ] && [ $((NFAIL * 100 / NRUN)) -gt "$MAX_FAIL_PCT" ]; then
  INCONCLUSIVE=1
  PREMISE_WHY="$NFAIL of $NRUN checks failed in one run (over ${MAX_FAIL_PCT}%), which is a statement about this machine, not about your memories"
fi

# ------------------------------------------------------------- streaks ----
# reconcile-streaks.tsv: key <TAB> streak <TAB> last_run_epoch <TAB> first_fail_date
: > "$TMP/streaks.new"
# Deliberately NOT `touch "$STREAKS"`. The first version created the file here
# so the readers below had something to read, which meant --dry-run left a new
# file on disk. "Dry run" has to mean zero writes or it means nothing, and the
# readers already tolerate a missing file.
if [ "$DRY" -eq 0 ]; then mkdir -p "$STATE" 2>/dev/null || :; fi

# Each reader is total: missing file, unreadable file, no matching row -- all
# produce empty output and exit 0. Under `set -eu` a reader that can fail is a
# reader that ends the run, and awk exits 2 on a file that is not there. That
# is how removing one stray `touch` turned a clean dry run into a silent abort
# two thirds of the way down the script, with a zero-length report and an exit
# status nobody was looking at.
streak_field() { # streak_field FIELD_NO KEY
  [ -f "$STREAKS" ] || return 0
  awk -F'\t' -v k="$2" -v n="$1" '$1==k{print $n; exit}' "$STREAKS" 2>/dev/null || :
}
streak_of()    { streak_field 2 "$1"; }
lastrun_of()   { streak_field 3 "$1"; }
firstfail_of() { streak_field 4 "$1"; }

: > "$TMP/ripe"      # failures that have cleared the streak gate
: > "$TMP/pending"   # failures still accumulating
: > "$TMP/recovered" # passes that used to fail

while IFS='	' read -r st key file ln kind arg detail; do
  [ -n "${st:-}" ] || continue
  prev=$(streak_of "$key"); [ -n "$prev" ] || prev=0
  prevrun=$(lastrun_of "$key"); [ -n "$prevrun" ] || prevrun=0
  first=$(firstfail_of "$key"); [ -n "$first" ] || first=$TODAY

  case $st in
    fail)
      if [ "$INCONCLUSIVE" -eq 1 ]; then
        new=$prev; runstamp=$prevrun          # frozen: this run proves nothing
      elif [ "$prev" -gt 0 ] && [ $((NOW - prevrun)) -lt "$MIN_GAP" ]; then
        new=$prev; runstamp=$prevrun          # too soon to count as a second look
      else
        new=$((prev + 1)); runstamp=$NOW
        [ "$prev" -gt 0 ] || first=$TODAY
      fi
      # A zero-streak row is not a fact worth storing; it is a row that makes
      # the state file look like something happened when nothing did.
      if [ "$new" -gt 0 ]; then
        printf '%s\t%s\t%s\t%s\n' "$key" "$new" "$runstamp" "$first" >> "$TMP/streaks.new"
      fi
      if [ "$new" -ge "$STREAK_N" ]; then
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$file" "$ln" "$kind" "$arg" "$detail" "$new" >> "$TMP/ripe"
      else
        printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$key" "$file" "$ln" "$kind" "$arg" "$detail" "$new" >> "$TMP/pending"
      fi ;;
    pass)
      [ "$prev" -gt 0 ] && printf '%s\t%s\t%s\t%s\t%s\n' "$key" "$file" "$ln" "$kind" "$arg" >> "$TMP/recovered"
      ;;                                      # streak dropped: no row written
    skip)
      # Preserve the row untouched. A skipped check is not evidence either way,
      # and losing the streak because you ran without --net would mean the gate
      # never closes on a network claim.
      [ "$prev" -gt 0 ] &&
        printf '%s\t%s\t%s\t%s\n' "$key" "$prev" "$prevrun" "$first" >> "$TMP/streaks.new" ;;
  esac
done < "$TMP/results"

NRIPE=$(wc -l < "$TMP/ripe" | tr -d ' ')
NPEND=$(wc -l < "$TMP/pending" | tr -d ' ')
NREC=$(wc -l < "$TMP/recovered" | tr -d ' ')

# ---------------------------------------------------------------- edits ----
: > "$TMP/applied"
audit() { # audit ACTION FILE DETAIL UNDO
  mkdir -p "$STATE"
  printf '%s\t%s\t%s\t%s\tundo: %s\n' \
    "$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null)" "$1" "$2" "$3" "$4" >> "$AUDIT"
}
# At most one backup per file per run, taken before this run's first edit to
# it. The first version stamped the name with whole seconds and took a copy per
# edit: two edits to one file inside the same second wrote the same filename,
# so the second copy silently overwrote the first with the already-modified
# file. The audit log still printed an undo command, and the command still ran,
# and it restored the file to the wrong state. An undo that cannot be trusted
# is worse than no undo, because it is the thing you reach for in a hurry.
: > "$TMP/backedup"
backup_once() { # backup_once FILE -> path
  _f=$1
  _rec=$(awk -F'\t' -v f="$_f" '$1==f{print $2; exit}' "$TMP/backedup" 2>/dev/null) || _rec=
  if [ -n "$_rec" ]; then printf '%s' "$_rec"; return 0; fi
  mkdir -p "$BACKUPS"
  _b="$BACKUPS/$(basename "$_f").$(date +%Y%m%dT%H%M%S).$$.bak"
  cp "$_f" "$_b" || return 1
  printf '%s\t%s\n' "$_f" "$_b" >> "$TMP/backedup"
  printf '%s' "$_b"
}

if [ "$APPLY" -eq 1 ] && [ "$DRY" -eq 0 ] && [ "$INCONCLUSIVE" -eq 0 ]; then
  # 1. mark ripe failures.
  #
  # Descending by line number within each file, because every insertion shifts
  # every line below it. Written in ascending order, the second marker for a
  # file lands one line late, the third two lines late, and each marker ends up
  # attached to a claim it is not about -- which is the one outcome worse than
  # not marking at all.
  sort -t'	' -k2,2 -k3,3nr "$TMP/ripe" > "$TMP/ripe.sorted" 2>/dev/null || cp "$TMP/ripe" "$TMP/ripe.sorted"
  while IFS='	' read -r key file ln kind arg detail streak; do
    [ -n "${file:-}" ] || continue
    # Literal matching. A path is not a regular expression, and a memory file
    # is allowed to contain one; `grep -F` twice beats a pattern built from
    # someone else's string.
    if grep -F 'eve:stale' "$file" 2>/dev/null | grep -qF " $kind $arg failed"; then
      continue                                                   # already marked
    fi
    bak=$(backup_once "$file") || continue
    awk -v ln="$ln" -v day="$TODAY" -v k="$kind" -v a="$arg" -v n="$streak" '
      { print }
      NR == ln { printf "<!-- eve:stale %s %s %s failed %s consecutive runs; claim above is unverified -->\n", day, k, a, n }
    ' "$file" > "$file.tmp$$" && mv "$file.tmp$$" "$file" || { rm -f "$file.tmp$$"; continue; }
    audit "mark-stale" "$(basename "$file")" "$kind $arg (streak $streak)" "cp '$bak' '$file'   # restores the file to its state before this run"
    printf 'marked\t%s\t%s %s\n' "$(basename "$file")" "$kind" "$arg" >> "$TMP/applied"
  done < "$TMP/ripe.sorted"

  # 2. unmark recovered checks -- the loop closes in both directions, which is
  #    what makes the marker trustworthy rather than a stain that accumulates.
  #    Deletion by content, not by line number, so ordering does not matter.
  while IFS='	' read -r key file ln kind arg; do
    [ -n "${file:-}" ] || continue
    grep -F 'eve:stale' "$file" 2>/dev/null | grep -qF " $kind $arg failed" || continue
    bak=$(backup_once "$file") || continue
    awk -v pat=" $kind $arg failed" 'index($0, "eve:stale") && index($0, pat) { next } { print }' \
      "$file" > "$file.tmp$$" && mv "$file.tmp$$" "$file" ||
      { rm -f "$file.tmp$$"; continue; }
    audit "unmark-stale" "$(basename "$file")" "$kind $arg now passes" "cp '$bak' '$file'   # restores the file to its state before this run"
    printf 'unmarked\t%s\t%s %s\n' "$(basename "$file")" "$kind" "$arg" >> "$TMP/applied"
  done < "$TMP/recovered"
fi
NAPPLIED=$(wc -l < "$TMP/applied" | tr -d ' ')

# ---------------------------------------------------------------- report ----
report() {
  printf '<!-- generated by eve-reconcile.sh on %s; regenerable -->\n\n' "$TODAY"
  printf '# Claims checked against reality - %s\n\n' "$TODAY"
  printf '%s checks in %s memories: %s passed, %s failed, %s skipped.\n' \
    "$NCHECKS" "$(awk -F'\t' '{print $1}' "$TMP/checks" | sort -u | wc -l | tr -d ' ')" \
    "$NPASS" "$NFAIL" "$NSKIP"
  printf 'Network checks: %s\n' "$NET_WHY"
  printf 'Streak gate: %s consecutive failing runs, at least %ss apart.\n\n' "$STREAK_N" "$MIN_GAP"

  if [ "$INCONCLUSIVE" -eq 1 ]; then
    printf '## RUN INCONCLUSIVE - no failure below was counted\n\n'
    printf '%s.\n\n' "$PREMISE_WHY"
    printf 'Streaks were left exactly as they were and no edit was made. Repeating a\n'
    printf 'probe whose premise is broken does not converge on the truth, it converges\n'
    printf 'on a confident wrong answer -- three runs from the same broken state is a\n'
    printf 'streak of three, and a streak is what this loop treats as permission to\n'
    printf 'write. Fix the machine, then run again.\n\n'
  fi

  printf '## Failing, gate cleared (%s)\n\n' "$NRIPE"
  if [ "$NRIPE" -eq 0 ]; then
    printf 'Nothing has failed often enough to act on.\n\n'
  else
    printf '| memory | check | detail | runs |\n|---|---|---|---|\n'
    while IFS='	' read -r key file ln kind arg detail streak; do
      printf '| %s | `%s %s` | %s | %s |\n' "$(basename "$file")" "$kind" "$arg" "$detail" "$streak"
    done < "$TMP/ripe"
    printf '\n'
    if [ "$APPLY" -eq 1 ]; then
      printf 'Marked in place (backed up; see the audit log).\n\n'
    else
      printf 'Not marked: --apply was not passed. Read the memory first. A failing\n'
      printf 'check means the claim needs a human decision -- rewrite it, supersede\n'
      printf 'it, or fix the world it describes -- and this loop can only do the\n'
      printf 'smallest, most reversible part of that.\n\n'
    fi
  fi

  printf '## Failing, still accumulating (%s)\n\n' "$NPEND"
  if [ "$NPEND" -eq 0 ]; then
    printf 'None.\n\n'
  else
    printf '| memory | check | detail | runs so far |\n|---|---|---|---|\n'
    while IFS='	' read -r key file ln kind arg detail streak; do
      printf '| %s | `%s %s` | %s | %s of %s |\n' \
        "$(basename "$file")" "$kind" "$arg" "$detail" "$streak" "$STREAK_N"
    done < "$TMP/pending"
    printf '\nA single failing run is a bad network, a half-finished checkout, a\n'
    printf 'volume that was not mounted yet. It is not news.\n\n'
  fi

  if [ "$NREC" -gt 0 ]; then
    printf '## Recovered (%s)\n\n' "$NREC"
    printf 'These failed before and pass now. Their streaks are reset%s.\n\n' \
      "$([ "$APPLY" -eq 1 ] && printf ' and any stale marker was removed' || printf '')"
    while IFS='	' read -r key file ln kind arg; do
      printf -- '- %s: `%s %s`\n' "$(basename "$file")" "$kind" "$arg"
    done < "$TMP/recovered"
    printf '\n'
  fi

  if [ "$NUNSAFE" -gt 0 ]; then
    printf '## Markers not run (%s)\n\n' "$NUNSAFE"
    while IFS='	' read -r base ln why; do
      printf -- '- %s:%s %s\n' "$base" "$ln" "$why"
    done < "$TMP/unsafe"
    printf '\nNothing in a memory file is executed. A marker that looks like it wants\n'
    printf 'a shell is reported and skipped.\n\n'
  fi

  if [ "$NAPPLIED" -gt 0 ]; then
    printf '## Edits made (%s)\n\n' "$NAPPLIED"
    while IFS='	' read -r what base what2; do
      printf -- '- %s %s (%s)\n' "$what" "$base" "$what2"
    done < "$TMP/applied"
    printf '\nEvery edit above copied the file first. `%s` has the undo command for\n' "$AUDIT"
    printf 'each one, as a literal command line you can paste.\n\n'
  fi
}

if [ "$DRY" -eq 1 ]; then
  report
  printf '\n[dry run] no proposal file, no streak update, no edits.\n'
  printf 'Streaks shown above are what IS on disk, not what this run would write.\n'
else
  mkdir -p "$STATE" "$(dirname "$OUT")"
  if [ -s "$TMP/streaks.new" ]; then
    sort -u "$TMP/streaks.new" > "$STREAKS.tmp$$" && mv "$STREAKS.tmp$$" "$STREAKS"
  else
    : > "$STREAKS"
  fi
  report > "$OUT.tmp$$" && mv "$OUT.tmp$$" "$OUT"
  printf '%s: %s pass, %s fail (%s gate-cleared, %s pending), %s skipped -> %s\n' \
    "$PROG" "$NPASS" "$NFAIL" "$NRIPE" "$NPEND" "$NSKIP" "$OUT"
  [ "$INCONCLUSIVE" -eq 1 ] && printf '%s: run was inconclusive; streaks unchanged\n' "$PROG"
fi
exit 0
