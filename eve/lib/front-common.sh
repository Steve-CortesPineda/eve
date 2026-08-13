# front-common.sh -- shared helpers for the Eve front layer.
#
# Sourced by bin/eve-front, bin/eve-sample and bin/eve-brief. Not executable,
# not a command. Contains no top-level side effects other than defining
# functions and, in front_cfg_load, assigning configuration variables.
#
# POSIX sh only. No bash 4 syntax (macOS ships bash 3.2), no `local`, no
# arrays, no `eval`, no timeout(1). Every function is safe to call twice.
#
# Function-scoped variables are prefixed with the initials of their function
# (fm_, ha_, aw_) because POSIX sh has no `local`. Do not remove the prefixes;
# they are the only thing keeping these helpers from clobbering their callers.

# Byte-deterministic character classes and sort order. Every tool this layer
# shells out to (tr, sort, awk, grep) changes behaviour with the locale.
LC_ALL=C
export LC_ALL

# --------------------------------------------------------------------------
# configuration
# --------------------------------------------------------------------------
#
# Precedence, highest first:
#
#   1. an environment variable that is already set (even to the empty string)
#   2. a KEY=value line in $EVE_HOME/config
#   3. the built-in default below
#
# The config file is read in-process, line by line, with a `case` that names
# every key it accepts. It is never sourced. A config file cannot execute
# code, and a key this layer does not understand is ignored rather than
# silently becoming a shell variable.
#
# EVE_HOME is environment-only: a config file cannot tell you where the config
# file is.

front_cfg_load() {
	EVE_HOME=${EVE_HOME:-"$HOME/.eve"}

	if [ -f "$EVE_HOME/config" ] && [ -r "$EVE_HOME/config" ]; then
		# `|| [ -n "$fcl_line" ]` so a final line with no trailing newline is
		# still processed.
		while IFS= read -r fcl_line || [ -n "$fcl_line" ]; do
			case $fcl_line in
			'' | '#'*) continue ;;
			*'='*) ;;
			*) continue ;;
			esac
			fcl_key=${fcl_line%%=*}
			fcl_val=${fcl_line#*=}
			fcl_val=$(front_trim "$fcl_val")

			case $fcl_key in
			EVE_DISABLE) [ -n "${EVE_DISABLE+x}" ] || EVE_DISABLE=$fcl_val ;;
			EVE_DEBUG) [ -n "${EVE_DEBUG+x}" ] || EVE_DEBUG=$fcl_val ;;
			EVE_MAX_LINES) [ -n "${EVE_MAX_LINES+x}" ] || EVE_MAX_LINES=$fcl_val ;;
			EVE_SAMPLE_ROOTS) [ -n "${EVE_SAMPLE_ROOTS+x}" ] || EVE_SAMPLE_ROOTS=$fcl_val ;;
			EVE_SAMPLE_FILES) [ -n "${EVE_SAMPLE_FILES+x}" ] || EVE_SAMPLE_FILES=$fcl_val ;;
			EVE_SAMPLE_GIT) [ -n "${EVE_SAMPLE_GIT+x}" ] || EVE_SAMPLE_GIT=$fcl_val ;;
			EVE_SAMPLE_APPS) [ -n "${EVE_SAMPLE_APPS+x}" ] || EVE_SAMPLE_APPS=$fcl_val ;;
			EVE_SAMPLE_PATHS) [ -n "${EVE_SAMPLE_PATHS+x}" ] || EVE_SAMPLE_PATHS=$fcl_val ;;
			EVE_SAMPLE_MAX_PATHS) [ -n "${EVE_SAMPLE_MAX_PATHS+x}" ] || EVE_SAMPLE_MAX_PATHS=$fcl_val ;;
			EVE_SAMPLE_MAX_DEPTH) [ -n "${EVE_SAMPLE_MAX_DEPTH+x}" ] || EVE_SAMPLE_MAX_DEPTH=$fcl_val ;;
			EVE_SAMPLE_IGNORE) [ -n "${EVE_SAMPLE_IGNORE+x}" ] || EVE_SAMPLE_IGNORE=$fcl_val ;;
			EVE_SAMPLE_LOG_MAX_LINES) [ -n "${EVE_SAMPLE_LOG_MAX_LINES+x}" ] || EVE_SAMPLE_LOG_MAX_LINES=$fcl_val ;;
			EVE_FRONT_HOURS) [ -n "${EVE_FRONT_HOURS+x}" ] || EVE_FRONT_HOURS=$fcl_val ;;
			EVE_FRONT_MAX_CHARS) [ -n "${EVE_FRONT_MAX_CHARS+x}" ] || EVE_FRONT_MAX_CHARS=$fcl_val ;;
			EVE_FRONT_STATE_MEMORY) [ -n "${EVE_FRONT_STATE_MEMORY+x}" ] || EVE_FRONT_STATE_MEMORY=$fcl_val ;;
			EVE_FRONT_COMPOSER) [ -n "${EVE_FRONT_COMPOSER+x}" ] || EVE_FRONT_COMPOSER=$fcl_val ;;
			esac
		done <"$EVE_HOME/config"
	fi

	# built-in defaults
	: "${EVE_DISABLE:=0}"
	: "${EVE_DEBUG:=0}"
	: "${EVE_MAX_LINES:=400}"
	: "${EVE_SAMPLE_ROOTS:=}"
	: "${EVE_SAMPLE_FILES:=1}"
	: "${EVE_SAMPLE_GIT:=1}"
	: "${EVE_SAMPLE_APPS:=0}"
	: "${EVE_SAMPLE_PATHS:=full}"
	: "${EVE_SAMPLE_MAX_PATHS:=12}"
	: "${EVE_SAMPLE_MAX_DEPTH:=8}"
	: "${EVE_SAMPLE_IGNORE:=.git:node_modules:.venv:venv:__pycache__:target:dist:build:.next:.tox:vendor:.terraform:Pods:.gradle:.mypy_cache:.pytest_cache:coverage}"
	: "${EVE_SAMPLE_LOG_MAX_LINES:=2000}"
	: "${EVE_FRONT_HOURS:=12}"
	: "${EVE_FRONT_MAX_CHARS:=500}"
	: "${EVE_FRONT_STATE_MEMORY:=working-state}"
	: "${EVE_FRONT_COMPOSER:=}"

	# Numeric keys are clamped rather than trusted. A typo in the config file
	# should not make find enumerate an entire home directory.
	EVE_SAMPLE_MAX_PATHS=$(front_int "$EVE_SAMPLE_MAX_PATHS" 12 1 200)
	EVE_SAMPLE_MAX_DEPTH=$(front_int "$EVE_SAMPLE_MAX_DEPTH" 8 1 32)
	EVE_SAMPLE_LOG_MAX_LINES=$(front_int "$EVE_SAMPLE_LOG_MAX_LINES" 2000 100 100000)
	EVE_FRONT_HOURS=$(front_int "$EVE_FRONT_HOURS" 12 1 720)
	EVE_FRONT_MAX_CHARS=$(front_int "$EVE_FRONT_MAX_CHARS" 500 80 8000)
	EVE_MAX_LINES=$(front_int "$EVE_MAX_LINES" 400 20 100000)

	EVE_STATE_DIR="$EVE_HOME/state"
	EVE_ACTIVITY_LOG="$EVE_STATE_DIR/activity.log"
	EVE_SAMPLE_MARKER="$EVE_STATE_DIR/sampler.marker"
	EVE_BRIEF_FILE="$EVE_STATE_DIR/brief.md"
}

# front_trim VALUE -- strip surrounding blanks, then one layer of matching
# quotes. Inline `#` is NOT treated as a comment: a path may contain one.
front_trim() {
	ft_v=$1
	while :; do
		case $ft_v in
		' '* | '	'*) ft_v=${ft_v#?} ;;
		*) break ;;
		esac
	done
	while :; do
		case $ft_v in
		*' ' | *'	') ft_v=${ft_v%?} ;;
		*) break ;;
		esac
	done
	case $ft_v in
	'"'*'"')
		ft_v=${ft_v#\"}
		ft_v=${ft_v%\"}
		;;
	"'"*"'")
		ft_v=${ft_v#\'}
		ft_v=${ft_v%\'}
		;;
	esac
	printf '%s' "$ft_v"
}

# front_int VALUE DEFAULT MIN MAX
front_int() {
	fi_v=$1
	case $fi_v in
	'' | *[!0-9]*) fi_v=$2 ;;
	esac
	[ "$fi_v" -ge "$3" ] 2>/dev/null || fi_v=$3
	[ "$fi_v" -le "$4" ] 2>/dev/null || fi_v=$4
	printf '%s' "$fi_v"
}

# --------------------------------------------------------------------------
# time and filesystem
# --------------------------------------------------------------------------

front_now_epoch() {
	fne_v=$(date +%s 2>/dev/null || printf '0')
	case $fne_v in
	'' | *[!0-9]*) fne_v=0 ;;
	esac
	printf '%s' "$fne_v"
}

front_now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || printf 'unknown'; }

# front_file_mtime PATH -- epoch seconds, or 0.
#
# BSD (`stat -f %m`) and GNU (`stat -c %Y`) disagree on flags AND on what an
# unrecognised format string does: GNU's -f means "filesystem", and it does not
# always fail on an unknown directive, so "try BSD first" can return the
# literal text "%m". Both results are therefore validated as digits, which
# makes the order of the attempts irrelevant.
front_file_mtime() {
	fm_v=$(stat -f '%m' "$1" 2>/dev/null || true)
	case $fm_v in
	'' | *[!0-9]*) fm_v=$(stat -c '%Y' "$1" 2>/dev/null || true) ;;
	esac
	case $fm_v in
	'' | *[!0-9]*) fm_v=0 ;;
	esac
	printf '%s' "$fm_v"
}

# front_stat_style -- "gnu", "bsd" or "none". Probed once per process against a
# file that is known to exist, and validated as digits for the reason above.
front_stat_style() {
	if [ -n "${FRONT_STAT_STYLE:-}" ]; then
		printf '%s' "$FRONT_STAT_STYLE"
		return 0
	fi
	fss_probe=${1:-/}
	FRONT_STAT_STYLE=none
	fss_v=$(stat -c '%Y' "$fss_probe" 2>/dev/null || true)
	case $fss_v in
	'' | *[!0-9]*) ;;
	*) FRONT_STAT_STYLE=gnu ;;
	esac
	if [ "$FRONT_STAT_STYLE" = none ]; then
		fss_v=$(stat -f '%m' "$fss_probe" 2>/dev/null || true)
		case $fss_v in
		'' | *[!0-9]*) ;;
		*) FRONT_STAT_STYLE=bsd ;;
		esac
	fi
	printf '%s' "$FRONT_STAT_STYLE"
}

# front_age_human SECONDS -- "just now", "25m", "3h", "2d".
front_age_human() {
	ha_s=$1
	case $ha_s in
	'' | *[!0-9]*) ha_s=0 ;;
	esac
	if [ "$ha_s" -lt 120 ]; then
		printf 'just now'
	elif [ "$ha_s" -lt 5400 ]; then
		printf '%dm ago' "$((ha_s / 60))"
	elif [ "$ha_s" -lt 172800 ]; then
		printf '%dh ago' "$((ha_s / 3600))"
	else
		printf '%dd ago' "$((ha_s / 86400))"
	fi
}

# front_abs_path PATH -- absolute path with symlinks in the parent resolved by
# the shell. realpath and `readlink -f` are not portable to stock macOS.
front_abs_path() {
	fap_p=$1
	if [ -d "$fap_p" ]; then
		(cd "$fap_p" 2>/dev/null && pwd) || printf '%s' "$fap_p"
	else
		fap_d=$(dirname "$fap_p")
		fap_b=$(basename "$fap_p")
		fap_d=$( (cd "$fap_d" 2>/dev/null && pwd) || printf '%s' "$fap_d")
		printf '%s/%s' "$fap_d" "$fap_b"
	fi
}

# front_resolve_link PATH -- follow symlinks (bounded) and return an absolute
# path. `readlink -f` and realpath are not portable to stock macOS; plain
# readlink is. Used to tell "the core engine" apart from "a symlink pointing
# back at me", which is the difference between a passthrough and a fork bomb.
front_resolve_link() {
	frl_p=$1
	frl_hops=0
	while [ -L "$frl_p" ] && [ "$frl_hops" -lt 10 ]; do
		frl_t=$(readlink "$frl_p" 2>/dev/null) || break
		case $frl_t in
		/*) frl_p=$frl_t ;;
		*) frl_p=$(dirname "$frl_p")/$frl_t ;;
		esac
		frl_hops=$((frl_hops + 1))
	done
	front_abs_path "$frl_p"
}

# front_tilde PATH -- collapse $HOME to ~ for display.
front_tilde() {
	case $1 in
	"$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
	"$HOME") printf '~' ;;
	*) printf '%s' "$1" ;;
	esac
}

# front_tmp DIR -- a writable temp path inside DIR (same filesystem, so the
# mv that follows is atomic). mktemp is not POSIX; fall back to $$.
front_tmp() {
	ftp_d=$1
	mktemp "$ftp_d/.eve-front.XXXXXX" 2>/dev/null || {
		ftp_f="$ftp_d/.eve-front.$$.$(front_now_epoch)"
		: >"$ftp_f" 2>/dev/null || return 1
		printf '%s' "$ftp_f"
	}
}

# front_trim_file PATH MAXLINES -- keep the last MAXLINES lines. Write to a
# temp file and rename, so a reader never sees a half-written log.
front_trim_file() {
	ftf_f=$1
	ftf_max=$2
	[ -f "$ftf_f" ] || return 0
	ftf_n=$(wc -l <"$ftf_f" 2>/dev/null || printf '0')
	ftf_n=$(front_trim "$ftf_n")
	case $ftf_n in
	'' | *[!0-9]*) return 0 ;;
	esac
	[ "$ftf_n" -gt "$ftf_max" ] || return 0
	ftf_t=$(front_tmp "$(dirname "$ftf_f")") || return 0
	if tail -n "$ftf_max" "$ftf_f" >"$ftf_t" 2>/dev/null; then
		mv "$ftf_t" "$ftf_f" 2>/dev/null || rm -f "$ftf_t" 2>/dev/null || true
	else
		rm -f "$ftf_t" 2>/dev/null || true
	fi
}

# front_tsv_clean -- stdin to stdout with tabs and CR turned into spaces, so a
# path can never forge a field boundary in the activity log.
front_tsv_clean() { tr '\t\r' '  '; }

# front_have CMD
front_have() { command -v "$1" >/dev/null 2>&1; }

# The memories, one path per line. TEMPLATE.md, MEMORY.md and INDEX.md live in
# the store without being memories -- the template is a scaffold full of
# {{PLACEHOLDERS}}, the other two are indexes. Counting them makes a fresh
# install report a store that is not empty, and picking one as the doctor's
# probe subject produces a retrieval "failure" that is really a counting bug.
# `eve search` and hooks/lib/common.sh skip exactly these names. Keep the three
# lists identical.
front_find_memories() {
	find "$EVE_HOME/memory" -maxdepth 1 -type f -name '*.md' \
		! -name 'TEMPLATE.md' ! -name 'MEMORY.md' \
		! -name 'INDEX.md' ! -name 'README.md' \
		-print 2>/dev/null
	return 0
}

front_warn() { printf '%s\n' "$*" >&2; }
