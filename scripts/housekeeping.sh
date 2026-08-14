#!/bin/sh
# housekeeping.sh -- prune Eve's machine residue by age.
#
# Installed as $EVE_HOME/bin/eve-housekeeping. Run it by hand, or from whatever
# already runs on a schedule on your box. It is safe to run every day and safe
# to never run at all.
#
# THE RULE THIS SCRIPT EXISTS TO OBEY
#
#   memory/ and kb/ are NEVER garbage-collected. Not by age, not by count, not
#   behind a flag, not with --force. Those two directories hold the only thing
#   in $EVE_HOME a human wrote, and a cleaner that can delete them is a cleaner
#   you cannot leave on a schedule. Everything this script touches is machine
#   residue: regenerable, or dead the moment the session that made it ended.
#
#   The rule is enforced three ways, because one way is a comment and three
#   ways is a design: (1) every prune target is a hardcoded subdirectory name,
#   never a path from the caller; (2) every candidate must also match a fixed
#   filename pattern; (3) is_knowledge_dir() refuses outright -- lexically AND
#   after resolving symlinks -- if a directory is, or is inside, memory/ or kb/.
#   That includes $EVE_HOME itself, so `--eve-home ~/.eve/memory` is a refusal
#   and not a disaster, and it includes a `sessions/` symlinked at `memory/`.
#
# WHAT GROWS, AND WHY IT IS NOT A DISK PROBLEM
#
#   state/seen-<session_id>   one per session, forever. Only ever read by the
#                             session that wrote it, so it is dead on exit.
#   sessions/YYYY-MM-DD.md    one per day.
#   proposals/*.md            one per loop run. Marked regenerable by the loops
#                             that write them; re-running the loop rebuilds one.
#
#   None of this is a disk problem -- a year of daily use is under 10 MB, and
#   the per-file caps in the hooks bound every individual file. It is a
#   tidiness problem, and directories with thousands of dead files are annoying
#   to read and slow to list. See docs/12-sizing.md for the measurements.
#
# WHY AGE AND NOT COUNT
#
#   "Keep the newest 200" deletes your busiest week first. Age is the only
#   retention rule that means the same thing on a quiet month and a loud one,
#   and it is the only one that is safe against a live session: a session
#   writing right now has a fresh mtime and cannot be selected.
#
# EXIT STATUS
#   0  nothing to do, or everything asked for was removed
#   1  something could not be removed (permissions, read-only volume)
#   2  refused: a path resolved into memory/ or kb/
#  64  usage error
#
# TEST IT BY HAND
#   ./housekeeping.sh --eve-home /tmp/eve-test --dry-run
#
# RUN IT ON A SCHEDULE
#   Optional. Nothing breaks if you never do -- see docs/12-sizing.md for the
#   measured cost of never running it, which is a few MB and about 11% of the
#   recall hook's time after a year. If you do schedule it, schedule --dry-run
#   first for a week and read what it says it would take.
#
#     cron:     17 4 * * 0  $HOME/.eve/bin/eve-housekeeping -q
#     launchd:  a StartCalendarInterval job running the same line
#     systemd:  a .timer alongside a oneshot .service
#
#   `-q` prints one line when it removed something and nothing when it did not,
#   which is the right amount of mail from a weekly job.

# `set -e` is deliberately absent. Each category is independent, and a failure
# to unlink one stale file is not a reason to skip the summary that tells you
# what the other four categories did. Failures are counted, not fatal.
set -u

EVE_HOME=${EVE_HOME:-"$HOME/.eve"}
DRY_RUN=0
QUIET=0
DO_BACKUPS=0

# Defaults. Conservative on purpose: every one of these is longer than the
# window in which the file is actually useful to anything.
#
#   state    14 days -- a seen-file is dead when its session ends. 14 days is
#                       two weeks of grace for a machine that was asleep.
#   session 180 days -- half a year of "what was I doing". Machine residue, but
#                       it is the only narrative record, so it gets the longest
#                       default of the three.
#   proposal 30 days -- an unreviewed proposal a month old is not a backlog
#                       item, it is a stale one. The loop regenerates it.
#   backup   90 days -- only with --backups. See the note at that block.
KEEP_STATE=14
KEEP_SESSION=180
KEEP_PROPOSAL=30
KEEP_BACKUP=90

usage() {
	cat <<'USAGE'
Usage: eve-housekeeping [options]

Prunes Eve's machine residue by age. memory/ and kb/ are never touched.

  -n, --dry-run          list what would go; delete nothing
      --eve-home PATH    default $EVE_HOME, else ~/.eve
      --state-days N     state/seen-*, stale *.tmp, orphaned guard files (14)
      --session-days N   sessions/YYYY-MM-DD.md (180)
      --proposal-days N  proposals/*.md (30)
      --backups          also prune state/backups and state/reconcile-backups
      --backup-days N    age for the above (90)
      --older-than N     set all four to N
  -q, --quiet            print only the summary, and nothing if nothing went
  -h, --help             this

Config: any of EVE_KEEP_STATE_DAYS, EVE_KEEP_SESSION_DAYS,
EVE_KEEP_PROPOSAL_DAYS, EVE_KEEP_BACKUP_DAYS may be set in the environment or
in $EVE_HOME/config. Resolution order is environment, then the file, then the
default -- the same order the hooks use.

Exit: 0 clean, 1 a removal failed, 2 refused a path inside memory/ or kb/.
USAGE
}

need_arg() {
	[ "$2" -ge 2 ] || {
		printf 'eve-housekeeping: %s needs a value\n' "$1" >&2
		exit 64
	}
}

# A retention value that is not a plain non-negative integer is a typo, and a
# typo that silently becomes empty is worse than one that stops you: `find
# -mtime +""` drops the whole category without a word, so the run reports
# "nothing to prune" and you believe it.
#
# This validates and exits; it does NOT print the value. The first version did
# -- `KEEP=$(int_or_die "$2" --x)` -- and its `exit 64` killed the command
# substitution's subshell while the parent sailed on with an empty string.
# Caught only because the test asserted on the exit status as well as the
# message. Never put the failure path of a validator inside `$( )`.
int_or_die() { # VALUE NAME
	case "${1:-}" in
	'' | *[!0-9]*)
		printf 'eve-housekeeping: %s must be a whole number of days, got: %s\n' "$2" "${1:-}" >&2
		exit 64
		;;
	esac
	return 0
}

while [ $# -gt 0 ]; do
	case "$1" in
	-n | --dry-run) DRY_RUN=1; shift ;;
	-q | --quiet) QUIET=1; shift ;;
	--backups) DO_BACKUPS=1; shift ;;
	--eve-home) need_arg "$1" $#; EVE_HOME=$2; shift 2 ;;
	--eve-home=*) EVE_HOME=${1#--eve-home=}; shift ;;
	--state-days) need_arg "$1" $#; int_or_die "$2" --state-days; KEEP_STATE=$2; shift 2 ;;
	--state-days=*) _v=${1#--state-days=}; int_or_die "$_v" --state-days; KEEP_STATE=$_v; shift ;;
	--session-days) need_arg "$1" $#; int_or_die "$2" --session-days; KEEP_SESSION=$2; shift 2 ;;
	--session-days=*) _v=${1#--session-days=}; int_or_die "$_v" --session-days; KEEP_SESSION=$_v; shift ;;
	--proposal-days) need_arg "$1" $#; int_or_die "$2" --proposal-days; KEEP_PROPOSAL=$2; shift 2 ;;
	--proposal-days=*) _v=${1#--proposal-days=}; int_or_die "$_v" --proposal-days; KEEP_PROPOSAL=$_v; shift ;;
	--backup-days) need_arg "$1" $#; int_or_die "$2" --backup-days; KEEP_BACKUP=$2; shift 2 ;;
	--backup-days=*) _v=${1#--backup-days=}; int_or_die "$_v" --backup-days; KEEP_BACKUP=$_v; shift ;;
	--older-than)
		need_arg "$1" $#
		int_or_die "$2" --older-than
		KEEP_STATE=$2; KEEP_SESSION=$2; KEEP_PROPOSAL=$2; KEEP_BACKUP=$2
		shift 2
		;;
	--older-than=*)
		_v=${1#--older-than=}
		int_or_die "$_v" --older-than
		KEEP_STATE=$_v; KEEP_SESSION=$_v; KEEP_PROPOSAL=$_v; KEEP_BACKUP=$_v
		shift
		;;
	-h | --help) usage; exit 0 ;;
	*)
		printf 'eve-housekeeping: unknown option: %s\n' "$1" >&2
		usage >&2
		exit 64
		;;
	esac
done

# Normalise the same way install.sh and doctor.sh do, so paths printed here
# compare as equal strings with paths printed there.
case "$EVE_HOME" in /*) ;; *) EVE_HOME="$(pwd)/$EVE_HOME" ;; esac
EVE_HOME=$(printf '%s' "$EVE_HOME" | sed -e 's|//*|/|g' -e 's|/$||')

# ---------------------------------------------------------------------------
# The guard
# ---------------------------------------------------------------------------
#
# True if the path is, or is inside, a memory/ or kb/ directory. Checked
# against $EVE_HOME up front and against every prune directory before its find
# runs. Two checks of the same invariant, because the cost of the second one is
# a string comparison and the cost of being wrong is somebody's notes.

knowledge_path() {
	case "$1" in
	*/memory | */memory/* | */kb | */kb/*) return 0 ;;
	esac
	return 1
}

# The lexical check above is not enough on its own, and the reason is worth
# writing down. If `sessions/` is a symlink to `memory/`, the string
# "$EVE_HOME/sessions" says nothing about where it lands. What saves you in that
# case is that `find symlink -maxdepth 1` does not descend -- but `find symlink/`
# WITH a trailing slash does, and that is a one-character difference between a
# no-op and deleting somebody's memories. Verified by hand on this platform:
#
#   $ find "$T/sessions"  -maxdepth 1 -type f -name '*.md' | wc -l   ->  0
#   $ find "$T/sessions/" -maxdepth 1 -type f -name '*.md' | wc -l   ->  2
#
# So do not rely on it. Resolve the physical directory and check that instead;
# then the guard holds no matter how find is spelled.
physical_path() {
	_p=$(cd "$1" 2>/dev/null && pwd -P) || _p=''
	[ -n "$_p" ] || _p=$1
	printf '%s' "$_p"
}

is_knowledge_dir() { # lexical OR physical
	knowledge_path "$1" && return 0
	knowledge_path "$(physical_path "$1")" && return 0
	return 1
}

if is_knowledge_dir "$EVE_HOME"; then
	printf 'eve-housekeeping: refusing to run: %s is inside a memory/ or kb/ tree.\n' "$EVE_HOME" >&2
	printf '  Those hold the only files a human wrote. Point --eve-home at the store root.\n' >&2
	exit 2
fi

[ -d "$EVE_HOME" ] || {
	[ "$QUIET" = 1 ] || printf 'eve-housekeeping: no store at %s, nothing to do\n' "$EVE_HOME"
	exit 0
}

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
#
# Read the file directly rather than sourcing it: a config file is data, and a
# stray line in it must not be able to run. Same whitelist-by-key approach as
# hooks/lib/common.sh. Environment wins over the file; a flag has already won
# over both, so a key is only consulted when its variable still holds the
# built-in default.

cfg_file_get() { # KEY -> value or empty
	[ -r "$EVE_HOME/config" ] || return 0
	sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$EVE_HOME/config" 2>/dev/null |
		sed -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//" |
		tail -1
	return 0
}

resolve_days() { # VARNAME KEYNAME DEFAULT
	eval "_cur=\$$1"
	[ "$_cur" = "$3" ] || return 0 # a flag set it; nothing else gets a vote
	eval "_env=\${$2-}"
	if [ -n "${_env:-}" ]; then
		_v=$_env
	else
		_v=$(cfg_file_get "$2")
	fi
	case "${_v:-}" in
	'' | *[!0-9]*) return 0 ;; # absent or junk: keep the default
	esac
	eval "$1=\$_v"
	return 0
}

resolve_days KEEP_STATE EVE_KEEP_STATE_DAYS 14
resolve_days KEEP_SESSION EVE_KEEP_SESSION_DAYS 180
resolve_days KEEP_PROPOSAL EVE_KEEP_PROPOSAL_DAYS 30
resolve_days KEEP_BACKUP EVE_KEEP_BACKUP_DAYS 90

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

tilde() {
	case "$1" in
	"$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
	*) printf '%s' "$1" ;;
	esac
}

human() { # bytes -> "4.1 MB"
	awk -v b="${1:-0}" 'BEGIN {
    if (b >= 1048576)   printf "%.1f MB", b / 1048576
    else if (b >= 1024) printf "%.0f KB", b / 1024
    else                printf "%d B", b
  }' 2>/dev/null || printf '%s B' "${1:-0}"
}

TMPD=''
cleanup() {
	[ -n "$TMPD" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"
	return 0
}
trap cleanup EXIT HUP INT TERM
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/eve-hk.XXXXXX") || {
	printf 'eve-housekeeping: cannot create a temp dir\n' >&2
	exit 1
}

TOTAL_FILES=0
TOTAL_BYTES=0
TOTAL_KB=0
FAILED=0

row() { # label count bytes note
	[ "$QUIET" = 1 ] && return 0
	printf '  %-26s %6s files  %9s  %s\n' "$1" "$2" "$(human "$3")" "$4"
	return 0
}

# Two different true answers to "how much is this?", and the gap between them is
# the whole story of a directory full of tiny files.
#
#   sum_bytes   the content. What `wc -c` says.
#   sum_kb      the blocks. What the filesystem actually hands back, because a
#               41-byte marker file still occupies a whole allocation unit.
#
# At Eve's file sizes the second number is several times the first, so the
# summary prints both rather than picking one and being quietly misleading.
sum_bytes() { # < list.nul
	xargs -0 wc -c 2>/dev/null |
		awk '$2 != "total" { s += $1 } END { printf "%d", s + 0 }' 2>/dev/null ||
		printf '0'
}

sum_kb() { # < list.nul  -> kilobytes of allocated blocks
	xargs -0 du -k 2>/dev/null |
		awk '{ s += $1 } END { printf "%d", s + 0 }' 2>/dev/null ||
		printf '0'
}

# How deep prune() looks. 1 for the flat directories, which is every category
# except the backup trees; those nest one level per run, so they set it to 2 and
# put it back. Bounded rather than unlimited on purpose: a runaway depth is how
# a cleaner ends up somewhere nobody expected.
PRUNE_DEPTH=1

# prune <label> <dir> <days> <note> <find-name-args...>
# The only function in this file that deletes anything.
#
# The name pattern is passed by the caller as literal find arguments and every
# call site below hardcodes it. A directory is never taken from user input; it
# is always "$EVE_HOME/<fixed name>".
prune() {
	_label=$1
	_dir=$2
	_days=$3
	_note=$4
	shift 4

	[ -d "$_dir" ] || return 0

	# Defence in depth: the caller passes a fixed subdirectory, and we check it
	# anyway -- lexically and physically, so a `sessions/` symlinked at `memory/`
	# is refused rather than merely happening not to match.
	if is_knowledge_dir "$_dir"; then
		printf 'eve-housekeeping: refusing to prune %s -- it resolves into a memory/ or kb/ tree.\n' \
			"$(tilde "$_dir")" >&2
		exit 2
	fi

	_list="$TMPD/list.nul"
	# -type f: a symlink is type l and is therefore never selected, so a symlink
	# planted in state/ cannot be used to reach a file outside it.
	# -mtime +N: strictly older than N days. Both BSD and GNU find agree here.
	find "$_dir" -maxdepth "$PRUNE_DEPTH" -type f "$@" -mtime +"$_days" -print0 >"$_list" 2>/dev/null || :
	[ -s "$_list" ] || return 0

	_n=$(tr -dc '\0' <"$_list" 2>/dev/null | wc -c | tr -d ' ') || _n=0
	case "$_n" in '' | *[!0-9]*) _n=0 ;; esac
	[ "$_n" -gt 0 ] || return 0
	_b=$(sum_bytes <"$_list")
	_kb=$(sum_kb <"$_list")

	row "$_label" "$_n" "$_b" "$_note"
	TOTAL_FILES=$((TOTAL_FILES + _n))
	TOTAL_BYTES=$((TOTAL_BYTES + _b))
	TOTAL_KB=$((TOTAL_KB + _kb))

	if [ "$DRY_RUN" = 0 ]; then
		xargs -0 rm -f <"$_list" 2>/dev/null || :
		# Trust nothing: recount rather than trusting rm's exit status, which is
		# 0 for -f even when a file survived on a read-only volume.
		_left=$(find "$_dir" -maxdepth "$PRUNE_DEPTH" -type f "$@" -mtime +"$_days" -print 2>/dev/null | wc -l | tr -d ' ') || _left=0
		case "$_left" in '' | *[!0-9]*) _left=0 ;; esac
		if [ "$_left" -gt 0 ]; then
			printf 'eve-housekeeping: %s files remain in %s after removal\n' "$_left" "$(tilde "$_dir")" >&2
			FAILED=$((FAILED + _left))
		fi
	fi
	rm -f "$_list" 2>/dev/null || :
	return 0
}

# Report a category without touching it, so the summary is honest about what it
# chose to leave behind.
report_only() { # label dir find-args...
	_label=$1
	_dir=$2
	_note=$3
	shift 3
	[ -d "$_dir" ] || return 0
	_l="$TMPD/keep.nul"
	find "$_dir" -type f "$@" -print0 >"$_l" 2>/dev/null || :
	[ -s "$_l" ] || return 0
	_n=$(tr -dc '\0' <"$_l" 2>/dev/null | wc -c | tr -d ' ') || _n=0
	case "$_n" in '' | *[!0-9]*) _n=0 ;; esac
	[ "$_n" -gt 0 ] || return 0
	_b=$(sum_bytes <"$_l")
	[ "$QUIET" = 1 ] || printf '  %-26s %6s files  %9s  %s\n' "$_label" "$_n" "$(human "$_b")" "$_note"
	rm -f "$_l" 2>/dev/null || :
	return 0
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

if [ "$QUIET" = 0 ]; then
	if [ "$DRY_RUN" = 1 ]; then
		printf 'eve-housekeeping  (dry run -- nothing will be deleted)\n'
	else
		printf 'eve-housekeeping\n'
	fi
	printf 'store: %s\n\n' "$(tilde "$EVE_HOME")"
fi

# state/ -- pure residue.
#
# seen-* is the per-session dedupe window; it is meaningless once that session
# is gone. *.tmp is a truncation that was interrupted. guard-active.<pid> is a
# marker whose process is long dead -- age is the portable way to know that,
# since a pid is reused and checking one belonging to somebody else is worse
# than waiting two weeks.
#
# Deliberately NOT pruned: whiffs.log (the input to `eve gaps`), recall.log,
# weights.tsv, gap-ignore, brief.md, install.log. Every one of those is either
# already bounded by the code that writes it or is a single small file that
# carries state you would miss.
prune 'state/seen-*' "$EVE_HOME/state" "$KEEP_STATE" "older than $KEEP_STATE days" -name 'seen-*'
prune 'state/*.tmp*' "$EVE_HOME/state" "$KEEP_STATE" "interrupted writes" -name '*.tmp*'
prune 'state/guard-active.*' "$EVE_HOME/state" "$KEEP_STATE" "orphaned markers" -name 'guard-active.*'

# sessions/ -- one file per day, written by eve-session-end.sh.
prune 'sessions/*.md' "$EVE_HOME/sessions" "$KEEP_SESSION" "older than $KEEP_SESSION days" -name '*.md'

# proposals/ -- loop output. The loops mark these regenerable; re-running the
# loop rebuilds one for the current data, which is the only version worth having.
prune 'proposals/*.md' "$EVE_HOME/proposals" "$KEEP_PROPOSAL" "older than $KEEP_PROPOSAL days" -name '*.md'

# Backups are opt-in, and that is not timidity.
#
# state/backups/ and state/reconcile-backups/ hold pre-edit copies of files a
# human wrote. They are the last thing standing between a bad automated edit and
# a lost memory. A cleaner that removes them by default is a cleaner that makes
# the worst day worse, so this needs --backups every time; there is no config
# key that turns it on permanently.
if [ "$DO_BACKUPS" = 1 ]; then
	prune 'state/reconcile-backups' "$EVE_HOME/state/reconcile-backups" "$KEEP_BACKUP" \
		"older than $KEEP_BACKUP days" -name '*'
	# sync-agents.sh writes one timestamped directory per run, so this tree is
	# one level deeper than the others and is reported as a single row. A row per
	# timestamp is 52 rows a year of output nobody reads.
	PRUNE_DEPTH=2
	prune 'state/backups' "$EVE_HOME/state/backups" "$KEEP_BACKUP" \
		"older than $KEEP_BACKUP days" -name '*'
	PRUNE_DEPTH=1
	# An emptied timestamp directory is residue too. rmdir refuses a non-empty
	# one, which is exactly the check we want -- no -empty test, no -delete, and
	# nothing that could take a directory that still holds something.
	if [ "$DRY_RUN" = 0 ] && [ -d "$EVE_HOME/state/backups" ]; then
		for _d in "$EVE_HOME/state/backups"/*; do
			[ -d "$_d" ] || continue
			rmdir "$_d" 2>/dev/null || :
		done
	fi
else
	report_only 'state/backups (kept)' "$EVE_HOME/state/backups" 'opt in with --backups' -name '*'
	report_only 'state/reconcile-backups' "$EVE_HOME/state/reconcile-backups" 'opt in with --backups' -name '*'
fi

# The line that matters most in this output.
if [ "$QUIET" = 0 ]; then
	_m=0
	_k=0
	[ -d "$EVE_HOME/memory" ] && _m=$(find "$EVE_HOME/memory" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
	[ -d "$EVE_HOME/kb" ] && _k=$(find "$EVE_HOME/kb" -type f 2>/dev/null | wc -l | tr -d ' ')
	case "$_m" in '' | *[!0-9]*) _m=0 ;; esac
	case "$_k" in '' | *[!0-9]*) _k=0 ;; esac
	printf '\n  never touched: memory/ (%s files), kb/ (%s files)\n' "$_m" "$_k"
	printf '                 knowledge is not garbage-collected, at any age.\n'
fi

if [ "$TOTAL_FILES" = 0 ]; then
	[ "$QUIET" = 0 ] && printf '\nnothing to prune. Everything is inside its retention window.\n'
	exit 0
fi

RECLAIM="$(human "$TOTAL_BYTES") of content, $(human "$((TOTAL_KB * 1024))") of disk blocks"

if [ "$DRY_RUN" = 1 ]; then
	if [ "$QUIET" = 1 ]; then
		printf 'eve-housekeeping: would remove %s files, %s\n' "$TOTAL_FILES" "$RECLAIM"
	else
		printf '\n[dry run] nothing was deleted. Drop --dry-run to remove %s files\n' "$TOTAL_FILES"
		printf '          (%s).\n' "$RECLAIM"
	fi
	exit 0
fi

if [ "$QUIET" = 1 ]; then
	printf 'eve-housekeeping: removed %s files, %s\n' "$TOTAL_FILES" "$RECLAIM"
else
	printf '\nremoved %s files (%s).\n' "$TOTAL_FILES" "$RECLAIM"
fi

[ "$FAILED" -gt 0 ] && exit 1
exit 0
