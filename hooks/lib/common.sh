# shellcheck shell=sh
# Eve shared hook library. Sourced by the hooks; never executed directly.
#
# Everything here is POSIX sh. No bash 4 syntax, no `local`, no arrays, no
# process substitution. Internal variables are prefixed `_eve_` because a
# sourced file shares the caller's namespace and `local` is not POSIX.
#
# Contract for every function here: it must not exit, must not write to stderr,
# and must return 0 even when it produced nothing. The hooks own their exit
# status; the library never takes it away from them.

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

# EVE_HOME is environment-only. A config file cannot tell you where the config
# file lives, so this is the one path the scripts hardcode a default for.
EVE_HOME="${EVE_HOME:-$HOME/.eve}"

EVE_MEMORY_DIR="$EVE_HOME/memory"
EVE_STATE_DIR="$EVE_HOME/state"
EVE_SESSIONS_DIR="$EVE_HOME/sessions"
EVE_BIN="$EVE_HOME/bin/eve"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------
#
# Read $EVE_HOME/config in-process, key by key, into shell variables.
#
# We do NOT `source` the config and we do NOT rely on inherited environment.
# Sourcing a file to get configuration is how you end up with a value that is
# assigned but never exported: the script works when you test it by hand,
# because your interactive shell already had the variable, and silently takes
# its default path everywhere else. Parsing explicitly means the value the
# script uses is the value the file contains, and `eve doctor` can print it.
#
# Precedence: an environment variable that is already set wins over the file.
# `eve_config_get` is deliberately a whitelist over known keys rather than an
# `eval` of `KEY=value`, so a stray line in the config file cannot execute.

eve_load_config() {
	# Defaults first; the file and the environment override them below.
	_eve_d_disable=0
	_eve_d_limit=3
	_eve_d_maxchars=1200
	_eve_d_minprompt=12
	_eve_d_snippet=150
	_eve_d_candcap=300
	_eve_d_maxlines=400
	_eve_d_briefmax=800
	_eve_d_engine=awk
	_eve_d_debug=0
	_eve_d_whiff=1

	# File values land in _eve_f_* so environment can still win afterwards.
	_eve_f_disable=''
	_eve_f_limit=''
	_eve_f_maxchars=''
	_eve_f_minprompt=''
	_eve_f_snippet=''
	_eve_f_candcap=''
	_eve_f_maxlines=''
	_eve_f_briefmax=''
	_eve_f_engine=''
	_eve_f_debug=''
	_eve_f_whiff=''

	if [ -r "$EVE_HOME/config" ]; then
		# `|| [ -n "$_eve_line" ]` so a final line with no newline is not lost.
		while IFS= read -r _eve_line || [ -n "$_eve_line" ]; do
			case "$_eve_line" in
			'' | '#'*) continue ;;
			*=*) ;;
			*) continue ;;
			esac
			_eve_k=${_eve_line%%=*}
			_eve_v=${_eve_line#*=}
			# Trim surrounding whitespace and one layer of quotes.
			# `eve_trim_var` assigns instead of printing: see the note above
			# eve_load_config about why nothing on this path forks.
			eve_trim_var "$_eve_k"
			_eve_k=$_eve_r
			eve_trim_var "$_eve_v"
			_eve_v=$_eve_r
			case "$_eve_v" in
			\"*\") _eve_v=${_eve_v#\"}; _eve_v=${_eve_v%\"} ;;
			\'*\') _eve_v=${_eve_v#\'}; _eve_v=${_eve_v%\'} ;;
			esac
			case "$_eve_k" in
			EVE_DISABLE) _eve_f_disable=$_eve_v ;;
			EVE_RECALL_LIMIT) _eve_f_limit=$_eve_v ;;
			EVE_RECALL_MAX_CHARS) _eve_f_maxchars=$_eve_v ;;
			EVE_RECALL_MIN_PROMPT) _eve_f_minprompt=$_eve_v ;;
			EVE_SNIPPET_CHARS) _eve_f_snippet=$_eve_v ;;
			EVE_CANDIDATE_CAP) _eve_f_candcap=$_eve_v ;;
			EVE_MAX_LINES) _eve_f_maxlines=$_eve_v ;;
			EVE_BRIEF_MAX_CHARS) _eve_f_briefmax=$_eve_v ;;
			EVE_ENGINE) _eve_f_engine=$_eve_v ;;
			EVE_DEBUG) _eve_f_debug=$_eve_v ;;
			EVE_WHIFF_LOG) _eve_f_whiff=$_eve_v ;;
			*) : ;; # unknown key: ignore, never eval
			esac
		done <"$EVE_HOME/config"
	fi

	# Environment wins if the variable is SET (even to empty); else file; else
	# default. `${v+x}` is the POSIX "is set" test.
	eve_resolve "${EVE_DISABLE+x}" "${EVE_DISABLE:-}" "$_eve_f_disable" "$_eve_d_disable"
	EVE_DISABLE=$_eve_r
	eve_resolve "${EVE_RECALL_LIMIT+x}" "${EVE_RECALL_LIMIT:-}" "$_eve_f_limit" "$_eve_d_limit"
	eve_int_var "$_eve_r" "$_eve_d_limit"
	EVE_RECALL_LIMIT=$_eve_r
	eve_resolve "${EVE_RECALL_MAX_CHARS+x}" "${EVE_RECALL_MAX_CHARS:-}" "$_eve_f_maxchars" "$_eve_d_maxchars"
	eve_int_var "$_eve_r" "$_eve_d_maxchars"
	EVE_RECALL_MAX_CHARS=$_eve_r
	eve_resolve "${EVE_RECALL_MIN_PROMPT+x}" "${EVE_RECALL_MIN_PROMPT:-}" "$_eve_f_minprompt" "$_eve_d_minprompt"
	eve_int_var "$_eve_r" "$_eve_d_minprompt"
	EVE_RECALL_MIN_PROMPT=$_eve_r
	eve_resolve "${EVE_SNIPPET_CHARS+x}" "${EVE_SNIPPET_CHARS:-}" "$_eve_f_snippet" "$_eve_d_snippet"
	eve_int_var "$_eve_r" "$_eve_d_snippet"
	EVE_SNIPPET_CHARS=$_eve_r
	eve_resolve "${EVE_CANDIDATE_CAP+x}" "${EVE_CANDIDATE_CAP:-}" "$_eve_f_candcap" "$_eve_d_candcap"
	eve_int_var "$_eve_r" "$_eve_d_candcap"
	EVE_CANDIDATE_CAP=$_eve_r
	eve_resolve "${EVE_MAX_LINES+x}" "${EVE_MAX_LINES:-}" "$_eve_f_maxlines" "$_eve_d_maxlines"
	eve_int_var "$_eve_r" "$_eve_d_maxlines"
	EVE_MAX_LINES=$_eve_r
	eve_resolve "${EVE_BRIEF_MAX_CHARS+x}" "${EVE_BRIEF_MAX_CHARS:-}" "$_eve_f_briefmax" "$_eve_d_briefmax"
	eve_int_var "$_eve_r" "$_eve_d_briefmax"
	EVE_BRIEF_MAX_CHARS=$_eve_r
	eve_resolve "${EVE_ENGINE+x}" "${EVE_ENGINE:-}" "$_eve_f_engine" "$_eve_d_engine"
	EVE_ENGINE=$_eve_r
	eve_resolve "${EVE_DEBUG+x}" "${EVE_DEBUG:-}" "$_eve_f_debug" "$_eve_d_debug"
	EVE_DEBUG=$_eve_r
	eve_resolve "${EVE_WHIFF_LOG+x}" "${EVE_WHIFF_LOG:-}" "$_eve_f_whiff" "$_eve_d_whiff"
	EVE_WHIFF_LOG=$_eve_r

	export EVE_HOME EVE_DISABLE EVE_RECALL_LIMIT EVE_RECALL_MAX_CHARS
	export EVE_RECALL_MIN_PROMPT EVE_SNIPPET_CHARS EVE_CANDIDATE_CAP
	export EVE_MAX_LINES EVE_BRIEF_MAX_CHARS EVE_ENGINE EVE_DEBUG
	return 0
}

# The `*_var` helpers assign to $_eve_r instead of printing.
#
# This looks clumsier than `x=$(helper ...)` and it is deliberate. Every command
# substitution forks a subshell, and config resolution touches a dozen keys on a
# hook that runs before every single prompt. Written the readable way, parsing
# the config cost more than the retrieval it was configuring -- about 60 ms of
# pure fork overhead, which is the difference between a hook nobody notices and
# a hook that gets uninstalled. Measure the thing that runs every time.

# eve_resolve <isset> <envval> <fileval> <default> -> $_eve_r
eve_resolve() {
	if [ -n "$1" ]; then
		_eve_r=$2
	elif [ -n "$3" ]; then
		_eve_r=$3
	else
		_eve_r=$4
	fi
}

# eve_int_var <value> <default> -> $_eve_r (value if all digits, else default)
eve_int_var() {
	case "${1:-}" in
	'' | *[!0-9]*) _eve_r=$2 ;;
	*) _eve_r=$1 ;;
	esac
}

# eve_trim_var <string> -> $_eve_r (leading/trailing spaces and tabs removed)
eve_trim_var() {
	_eve_r=$1
	while :; do
		case "$_eve_r" in
		' '* | '	'*) _eve_r=${_eve_r#?} ;;
		*) break ;;
		esac
	done
	while :; do
		case "$_eve_r" in
		*' ' | *'	') _eve_r=${_eve_r%?} ;;
		*) break ;;
		esac
	done
}

# Printing wrappers, for callers outside the per-prompt path (eve-doctor, the
# session hooks' one-off arithmetic). Convenience, not the hot path.
eve_int() {
	eve_int_var "${1:-}" "$2"
	printf '%s' "$_eve_r"
}

eve_trim() {
	eve_trim_var "$1"
	printf '%s' "$_eve_r"
}

# Is Eve switched off? Callers check this before doing any other work.
eve_disabled() {
	case "${EVE_DISABLE:-0}" in
	1 | true | yes | on) return 0 ;;
	*) return 1 ;;
	esac
}

# Does the store exist and hold at least one memory? A first run with no store
# must be silent, not an error.
#
# A glob, not `find | head | grep -q`: the pipeline is three processes to answer
# a question the shell can answer with none. When the glob matches nothing the
# shell leaves the pattern itself in $_eve_f and the -f test fails, which is the
# answer we want. The store is flat by contract, so a glob is also complete.
# Approximate size of the store, cached.
#
# The only caller is the dedupe window, which needs a ballpark rather than a
# census -- it is choosing how many recently-shown files to exclude. That
# distinction is what makes caching safe here and it is why this must not grow
# a second caller that needs an exact count.
#
# Globbing the directory costs ~55 ms at 2,000 files, and this runs on EVERY
# prompt, so an uncached walk is most of the per-prompt budget on a large store.
# The cache is invalidated by the directory's own mtime: adding or removing a
# file touches the directory, which is exactly when the count changes. Editing a
# file does not, and does not need to.
eve_store_count() {
	[ -d "$EVE_MEMORY_DIR" ] || {
		printf '0'
		return 0
	}
	_eve_cache=$EVE_STATE_DIR/store-count
	# `find -newer` avoids stat(1), whose format flags differ between BSD and GNU.
	if [ -f "$_eve_cache" ] &&
		[ -z "$(find "$EVE_MEMORY_DIR" -maxdepth 0 -newer "$_eve_cache" 2>/dev/null)" ]; then
		_eve_n=$(cat "$_eve_cache" 2>/dev/null) || _eve_n=''
		case $_eve_n in
		'' | *[!0-9]*) ;; # unreadable or corrupt: fall through and recount
		*)
			printf '%s' "$_eve_n"
			return 0
			;;
		esac
	fi

	_eve_n=0
	for _eve_f in "$EVE_MEMORY_DIR"/*.md; do
		[ -f "$_eve_f" ] || continue
		case "${_eve_f##*/}" in
		TEMPLATE.md | MEMORY.md | INDEX.md | README.md) continue ;;
		esac
		_eve_n=$((_eve_n + 1))
	done
	# Best-effort: a store we cannot write to still returns the right number.
	if eve_ensure_state 2>/dev/null; then
		printf '%s' "$_eve_n" >"$_eve_cache.tmp" 2>/dev/null &&
			mv "$_eve_cache.tmp" "$_eve_cache" 2>/dev/null || :
	fi
	printf '%s' "$_eve_n"
}

eve_store_ready() {
	[ -d "$EVE_MEMORY_DIR" ] || return 1
	for _eve_f in "$EVE_MEMORY_DIR"/*.md; do
		[ -f "$_eve_f" ] || continue
		case "${_eve_f##*/}" in
		TEMPLATE.md | MEMORY.md | INDEX.md | README.md) continue ;;
		esac
		return 0
	done
	return 1
}

# Enumerate the actual memories, NUL-separated, for `xargs -0`.
#
# TEMPLATE.md, MEMORY.md and INDEX.md live in the store and are not memories:
# the template is a scaffold full of {{PLACEHOLDERS}} and the other two are
# indexes. Counting them makes a fresh install report a store that is not empty,
# and ranking them lets the store retrieve a description of itself instead of an
# answer. `eve search` skips exactly these names. Any list that disagrees with
# that one is a bug -- which is why this is a function and not four copies of a
# find command.
eve_find_memories() {
	find "$EVE_MEMORY_DIR" -maxdepth 1 -type f -name '*.md' \
		! -name 'TEMPLATE.md' ! -name 'MEMORY.md' \
		! -name 'INDEX.md' ! -name 'README.md' \
		-print0 2>/dev/null
	return 0
}

# ---------------------------------------------------------------------------
# JSON on stdin
# ---------------------------------------------------------------------------
#
# Claude Code hands the hook a JSON object on stdin. Field names are treated as
# best effort: a missing field yields an empty string and a clean exit, never a
# broken session.
#
# Parser fallback chain: jq -> python3 -> sed. Each tier is tried only if the
# previous one is absent or produced nothing usable. Values are flattened to a
# single line (newlines/tabs become spaces) so callers can treat every field as
# one line; nothing Eve does with these fields needs the line structure.

eve_have_jq() {
	command -v jq >/dev/null 2>&1
}

# python3 on macOS can be a Command Line Tools stub that pops a GUI installer
# when executed. A hook must never trigger that, so we only trust python3 if it
# is not the stub path, or if the tools are actually installed.
eve_have_python3() {
	_eve_py=$(command -v python3 2>/dev/null) || return 1
	[ -n "$_eve_py" ] || return 1
	case "$_eve_py" in
	/usr/bin/python3)
		[ "$(uname -s 2>/dev/null)" != "Darwin" ] && return 0
		xcode-select -p >/dev/null 2>&1
		;;
	*) return 0 ;;
	esac
}

# eve_json_get <json-text> <field>
# Prints the field's string value on one line, or nothing.
eve_json_get() {
	_eve_json=$1
	_eve_field=$2
	_eve_out=''

	if eve_have_jq; then
		_eve_out=$(printf '%s' "$_eve_json" |
			jq -r --arg k "$_eve_field" \
				'(.[$k] // "") | if type == "string" then . else "" end | gsub("[\n\r\t]+"; " ")' \
				2>/dev/null) || _eve_out=''
		if [ -n "$_eve_out" ]; then
			printf '%s' "$_eve_out"
			return 0
		fi
	fi

	if eve_have_python3; then
		_eve_out=$(printf '%s' "$_eve_json" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    v = d.get(sys.argv[1], "")
    if isinstance(v, str):
        sys.stdout.write(" ".join(v.split()))
except Exception:
    pass
' "$_eve_field" 2>/dev/null) || _eve_out=''
		if [ -n "$_eve_out" ]; then
			printf '%s' "$_eve_out"
			return 0
		fi
	fi

	# Last resort.
	#
	# `sed -E` (ERE), not BRE: BRE alternation is spelled `\|` and that is a GNU
	# extension. BSD sed does not fail loudly on it, it simply never matches, so
	# a BRE version of this passes review, passes a Linux test run, and silently
	# returns nothing on every Mac. Both seds accept -E.
	#
	# Limits, accepted deliberately: POSIX sed has no non-greedy match, so with
	# a duplicated key this finds the last occurrence rather than the first, and
	# only the common escapes are undone. The job of tier three is to degrade,
	# not to be exact.
	_eve_out=$(printf '%s' "$_eve_json" | tr '\n' ' ' |
		sed -E -n 's/.*"'"$_eve_field"'"[[:space:]]*:[[:space:]]*"(([^"\]|\\.)*)".*/\1/p' 2>/dev/null |
		sed -e 's/\\n/ /g' -e 's/\\r/ /g' -e 's/\\t/ /g' -e 's/\\"/"/g' -e 's/\\\\/\\/g' 2>/dev/null) || _eve_out=''
	printf '%s' "$_eve_out"
	return 0
}

# ---------------------------------------------------------------------------
# Small portable helpers
# ---------------------------------------------------------------------------

# BSD `stat -f %m` and GNU `stat -c %Y` both exist and mean different things to
# each other: GNU's -f is --file-system and will happily succeed with a
# non-numeric answer. So validate the output rather than the exit status.
eve_file_mtime() {
	_eve_m=$(stat -f %m "$1" 2>/dev/null) || _eve_m=''
	case "$_eve_m" in
	'' | *[!0-9]*) _eve_m=$(stat -c %Y "$1" 2>/dev/null) || _eve_m='' ;;
	esac
	case "$_eve_m" in
	'' | *[!0-9]*) _eve_m=0 ;;
	esac
	printf '%s' "$_eve_m"
}

# Age of a file in seconds; a huge number if it does not exist, so callers can
# compare against a freshness window without a special case.
eve_file_age() {
	[ -f "$1" ] || {
		printf '%s' 999999999
		return 0
	}
	_eve_mt=$(eve_file_mtime "$1")
	_eve_nw=$(date +%s 2>/dev/null) || _eve_nw=0
	case "$_eve_nw" in '' | *[!0-9]*) _eve_nw=0 ;; esac
	if [ "$_eve_nw" -gt "$_eve_mt" ]; then
		printf '%s' "$((_eve_nw - _eve_mt))"
	else
		printf '%s' 0
	fi
}

# Collapse $HOME to ~ so injected paths are short and not machine-identifying.
eve_tilde() {
	case "$1" in
	"$HOME"/*) printf '~%s' "${1#"$HOME"}" ;;
	*) printf '%s' "$1" ;;
	esac
}

# Make an untrusted string safe to use as a filename component. Session ids
# arrive from JSON; without this a crafted id containing `/` or `..` would let
# a state write escape $EVE_HOME/state.
#
# The common case -- a uuid -- is already clean and takes the fork-free path.
# The scrubbing branch exists for the case that matters, not the case that
# happens.
eve_safe_id() {
	_eve_id=${1:-}
	if [ -z "$_eve_id" ]; then
		printf 'nosid'
		return 0
	fi
	case "$_eve_id" in
	*[!A-Za-z0-9._-]*) ;; # needs scrubbing, fall through
	*)
		if [ "${#_eve_id}" -le 64 ]; then
			printf '%s' "$_eve_id"
			return 0
		fi
		;;
	esac
	_eve_id=$(printf '%s' "$_eve_id" | tr -c 'A-Za-z0-9._-' '_' 2>/dev/null | cut -c1-64)
	[ -n "$_eve_id" ] || _eve_id=nosid
	printf '%s' "$_eve_id"
}

eve_ensure_state() {
	[ -d "$EVE_STATE_DIR" ] || mkdir -p "$EVE_STATE_DIR" 2>/dev/null || return 1
	return 0
}

# EVE_DEBUG=1 appends one line to state/recall.log. Off by default; the log is
# bounded so leaving it on cannot fill a disk.
eve_debug() {
	[ "${EVE_DEBUG:-0}" = "1" ] || return 0
	eve_ensure_state || return 0
	printf '%s %s\n' "$(date +%Y-%m-%dT%H:%M:%S 2>/dev/null)" "$*" \
		>>"$EVE_STATE_DIR/recall.log" 2>/dev/null || return 0
	_eve_n=$(wc -l <"$EVE_STATE_DIR/recall.log" 2>/dev/null | tr -d ' ') || _eve_n=0
	case "$_eve_n" in '' | *[!0-9]*) _eve_n=0 ;; esac
	if [ "$_eve_n" -gt 2000 ]; then
		tail -500 "$EVE_STATE_DIR/recall.log" >"$EVE_STATE_DIR/recall.log.tmp" 2>/dev/null &&
			mv "$EVE_STATE_DIR/recall.log.tmp" "$EVE_STATE_DIR/recall.log" 2>/dev/null
	fi
	return 0
}

# ---------------------------------------------------------------------------
# Retrieval
# ---------------------------------------------------------------------------
#
# Hooks never implement scoring. There is exactly one retrieval entry point,
# `$EVE_HOME/bin/eve search`, so that what the hook injects and what you see
# when you run `eve search` at a terminal are produced by the same code. If
# they were two implementations they would drift, and you would be debugging
# the wrong one.
#
# eve_recall <query> <limit> <exclude-csv> <format>
eve_recall() {
	[ -x "$EVE_BIN" ] || {
		eve_debug "recall: no executable at $EVE_BIN"
		return 0
	}
	"$EVE_BIN" search \
		--query "$1" \
		--limit "$2" \
		--exclude "$3" \
		--format "$4" 2>/dev/null || return 0
	return 0
}

# ---------------------------------------------------------------------------
# Output budget
# ---------------------------------------------------------------------------
#
# eve_cap_block <max-chars> [header-lines]
#
# Reads a wrapped block on stdin and prints it back under a character budget.
# Rules: never truncate mid-line (a half sentence is worse than an absent one),
# always keep the opening and closing tags together, and print nothing at all
# rather than an empty wrapper -- an <eve-memory> block containing only its own
# preamble is pure context cost, and it is worse than silence because it tells
# the model a lookup happened and found nothing.
#
# `header-lines` (default 1) is how many leading lines are structural rather
# than content: the recall block spends its first two lines on the open tag and
# the "this is DATA" framing, so it passes 2, and content is counted from there.
#
# This duplicates a cap that `eve search --format hook` already applies. That is
# deliberate: the injection budget is the one number whose violation is paid on
# every single prompt, so it is enforced at the boundary that does the injecting
# as well as at the boundary that does the formatting.
eve_cap_block() {
	_eve_max=${1:-1200}
	_eve_hdr=${2:-1}
	_eve_in=$(cat 2>/dev/null) || _eve_in=''
	[ -n "$_eve_in" ] || return 0
	printf '%s\n' "$_eve_in" | awk -v max="$_eve_max" -v hdr="$_eve_hdr" '
    # Literal (not regex) find-and-replace, so a tag containing regex
    # metacharacters cannot be mis-handled.
    function lit(s, find, repl,   out, p) {
      if (find == "") return s
      out = ""
      while ((p = index(s, find)) > 0) {
        out = out substr(s, 1, p - 1) repl
        s = substr(s, p + length(find))
      }
      return out s
    }
    function astext(t) { sub(/^</, "", t); sub(/>$/, "", t); return "(" t ")" }
    # A memory file is an ordinary file. Anything with write access to the store
    # can put the literal string "</eve-memory>" in one, and if that reaches the
    # model unaltered it reads as the end of the quoted block -- everything after
    # it looks like it came from the harness rather than from a file. Neutralise
    # the tags wherever they appear in CONTENT; the real wrapper is emitted by
    # this function and only by this function.
    function defang(s) {
      if (opener != "") s = lit(s, opener, astext(opener))
      if (closer != "") s = lit(s, closer, astext(closer))
      return s
    }
    { line[NR] = $0 }
    END {
      if (NR == 0) exit 0
      if (hdr < 1) hdr = 1
      opener = (line[1] ~ /^<[a-zA-Z]/) ? line[1] : ""
      closer = ""
      last = NR
      if (line[NR] ~ /^<\//) { closer = line[NR]; last = NR - 1 }
      for (i = hdr + 1; i <= last; i++) line[i] = defang(line[i])

      # The structural lines are all-or-nothing: a block without its framing is
      # not a smaller block, it is a broken one.
      total = 0
      for (i = 1; i <= hdr && i <= last; i++) total += length(line[i]) + 1
      if (closer != "") total += length(closer) + 1
      if (total > max) exit 0

      kept = 0
      body = ""
      for (i = hdr + 1; i <= last; i++) {
        l = length(line[i]) + 1
        if (total + l > max) continue  # drop this line whole, a later one may fit
        total += l
        body = body line[i] "\n"
        kept++
      }
      if (last > hdr && kept == 0) exit 0   # no content survived: emit nothing

      for (i = 1; i <= hdr && i <= last; i++) printf "%s\n", line[i]
      printf "%s", body
      if (closer != "") printf "%s\n", closer
    }
  ' 2>/dev/null || return 0
	return 0
}
