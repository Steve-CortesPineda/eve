#!/bin/sh
# uninstall.sh -- remove Eve's wiring from Claude Code. Keeps your memories.
#
# What this removes:
#   - Eve's three hook entries from settings.json (nothing else in that file)
#   - the <!-- eve:begin --> ... <!-- eve:end --> block from CLAUDE.md
#
# What this does NOT remove, ever:
#   - anything under $EVE_HOME. Your memories are yours. The path is printed at
#     the end along with the exact command to delete it yourself if you want to.
#
# Why the default is surgical removal rather than restoring the backup: the
# backup is a snapshot from install time, and you have probably edited
# settings.json since. Restoring it would silently discard those edits. Pass
# --restore-settings if you really do want the pristine file back.

set -eu

REPO_DIR=$(cd "$(dirname "$0")" && pwd)

EVE_HOME=${EVE_HOME:-"$HOME/.eve"}
CLAUDE_DIR=${CLAUDE_CONFIG_DIR:-"$HOME/.claude"}
ASSUME_YES=0
DRY_RUN=0
RESTORE=0

usage() {
	cat <<'USAGE'
Usage: ./uninstall.sh [options]

Options:
  --eve-home PATH      Eve's home (default: ~/.eve or $EVE_HOME).
  --claude-dir PATH    Claude Code config dir (default: ~/.claude).
  --restore-settings   Restore settings.json from settings.json.eve.bak instead
                       of removing only Eve's entries. This discards any change
                       you made to that file since installing.
  -y, --yes            Answer yes to every prompt.
  -n, --dry-run        Print the plan, change nothing.
  -h, --help           This text.

Your memories under $EVE_HOME are never touched.
USAGE
}

while [ $# -gt 0 ]; do
	case "$1" in
	--eve-home)
		[ $# -ge 2 ] || { echo "uninstall: --eve-home needs a path" >&2; exit 64; }
		EVE_HOME=$2
		shift 2
		;;
	--eve-home=*)
		EVE_HOME=${1#--eve-home=}
		shift
		;;
	--claude-dir)
		[ $# -ge 2 ] || { echo "uninstall: --claude-dir needs a path" >&2; exit 64; }
		CLAUDE_DIR=$2
		shift 2
		;;
	--claude-dir=*)
		CLAUDE_DIR=${1#--claude-dir=}
		shift
		;;
	--restore-settings)
		RESTORE=1
		shift
		;;
	-y | --yes)
		ASSUME_YES=1
		shift
		;;
	-n | --dry-run)
		DRY_RUN=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	*)
		echo "uninstall: unknown option: $1" >&2
		exit 64
		;;
	esac
done

case "$EVE_HOME" in /*) ;; *) EVE_HOME="$(pwd)/$EVE_HOME" ;; esac
case "$CLAUDE_DIR" in /*) ;; *) CLAUDE_DIR="$(pwd)/$CLAUDE_DIR" ;; esac
# Same normalisation install.sh applies, so printed paths match what was
# registered.
EVE_HOME=$(printf '%s' "$EVE_HOME" | sed -e 's|//*|/|g' -e 's|/$||')
CLAUDE_DIR=$(printf '%s' "$CLAUDE_DIR" | sed -e 's|//*|/|g' -e 's|/$||')

SETTINGS="$CLAUDE_DIR/settings.json"
SETTINGS_BAK="$CLAUDE_DIR/settings.json.eve.bak"
CLAUDE_MD="$CLAUDE_DIR/CLAUDE.md"

TMPD=""
cleanup() {
	[ -n "$TMPD" ] && [ -d "$TMPD" ] && rm -rf "$TMPD"
	return 0
}
trap cleanup EXIT HUP INT TERM
TMPD=$(mktemp -d "${TMPDIR:-/tmp}/eve-uninstall.XXXXXX")

say() { printf '%s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
note() { printf '   %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }

ask() {
	_q=$1
	_def=$2
	if [ "$ASSUME_YES" -eq 1 ] || [ ! -t 0 ]; then
		if [ "$_def" = "y" ]; then return 0; else return 1; fi
	fi
	if [ "$_def" = "y" ]; then _hint="[Y/n]"; else _hint="[y/N]"; fi
	printf '   %s %s ' "$_q" "$_hint"
	read -r _ans || _ans=""
	case "$_ans" in
	"")
		if [ "$_def" = "y" ]; then return 0; else return 1; fi
		;;
	[Yy] | [Yy][Ee][Ss]) return 0 ;;
	*) return 1 ;;
	esac
}

have_python3() {
	_py=$(command -v python3 2>/dev/null) || return 1
	[ -n "$_py" ] || return 1
	if [ "$(uname -s)" = "Darwin" ] && [ "$_py" = "/usr/bin/python3" ]; then
		[ -d /Library/Developer/CommandLineTools/usr/bin ] ||
			[ -d /Applications/Xcode.app ] || return 1
	fi
	python3 -c 'import json,sys' >/dev/null 2>&1
}

say "Eve uninstaller"
say "  EVE_HOME:   $EVE_HOME   (will not be touched)"
say "  Claude dir: $CLAUDE_DIR"
[ "$DRY_RUN" -eq 1 ] && say "  mode:       DRY RUN (nothing will be written)"

# --------------------------------------------------------------------------
# 1. settings.json
# --------------------------------------------------------------------------

step "1/3  settings.json"

strip_with_jq() {
	jq \
		--arg re '(^|/)eve-(recall|session-start|session-end|guard)\.sh' \
		'
    def strip($arr; $re):
      ($arr // [])
      | map(select(type == "object"))
      | map(.hooks = ((.hooks // []) | map(select(((.command // "") | test($re)) | not))))
      | map(select(((.hooks // []) | length) > 0));

    if type != "object" then error("settings.json is not a JSON object") else . end
    | if ((.hooks // null) | type) == "object" then
        .hooks |= with_entries(.value = strip(.value; $re))
        | .hooks |= with_entries(select((.value | length) > 0))
      else . end
    | if ((.hooks // null) | type) == "object" and ((.hooks | length) == 0)
      then del(.hooks) else . end
  ' "$1" >"$2" 2>"$TMPD/jq.err"
}

strip_with_python() {
	EVE_IN=$1 EVE_OUT=$2 python3 - <<'PY' 2>"$TMPD/py.err"
import json, os, re, sys

src, dst = os.environ["EVE_IN"], os.environ["EVE_OUT"]
pat = re.compile(r'(^|/)eve-(recall|session-start|session-end|guard)\.sh')

with open(src) as fh:
    data = json.load(fh)
if not isinstance(data, dict):
    sys.exit("settings.json is not a JSON object")

hooks = data.get("hooks")
if isinstance(hooks, dict):
    out = {}
    for event, groups in hooks.items():
        kept_groups = []
        for g in groups or []:
            if not isinstance(g, dict):
                kept_groups.append(g)
                continue
            kept = [h for h in (g.get("hooks") or [])
                    if not pat.search(str(h.get("command", "")))]
            if kept:
                g = dict(g)
                g["hooks"] = kept
                kept_groups.append(g)
        if kept_groups:
            out[event] = kept_groups
    if out:
        data["hooks"] = out
    else:
        data.pop("hooks", None)

with open(dst, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
PY
}

if [ ! -f "$SETTINGS" ]; then
	note "not present: $SETTINGS -- nothing to remove"
elif [ "$RESTORE" -eq 1 ]; then
	if [ ! -f "$SETTINGS_BAK" ]; then
		warn "no backup at $SETTINGS_BAK; falling back to removing Eve's entries only"
		RESTORE=0
	elif [ "$DRY_RUN" -eq 1 ]; then
		note "would restore $SETTINGS from $SETTINGS_BAK"
	# --restore-settings is itself the consent; the prompt only exists for the
	# interactive case. Asking again and then defaulting to "no" would make the
	# flag unusable from a script, which is how a flag becomes a lie.
	elif [ "$ASSUME_YES" -eq 1 ] ||
		ask "Restore $SETTINGS from the install-time backup? Edits made since then are lost." n; then
		cp "$SETTINGS" "$SETTINGS.eve-preuninstall"
		cp "$SETTINGS_BAK" "$SETTINGS"
		note "restored $SETTINGS from $SETTINGS_BAK"
		note "the file as it was a moment ago: $SETTINGS.eve-preuninstall"
	else
		note "declined; removing Eve's entries only"
		RESTORE=0
	fi
fi

if [ -f "$SETTINGS" ] && [ "$RESTORE" -eq 0 ]; then
	if [ "$DRY_RUN" -eq 1 ]; then
		note "would remove Eve's hook entries from $SETTINGS"
	else
		stripped="$TMPD/settings.stripped.json"
		ok=0
		if command -v jq >/dev/null 2>&1 && strip_with_jq "$SETTINGS" "$stripped" && [ -s "$stripped" ]; then
			ok=1
		elif have_python3 && strip_with_python "$SETTINGS" "$stripped" && [ -s "$stripped" ]; then
			ok=1
		fi
		if [ "$ok" -eq 1 ]; then
			if cmp -s "$stripped" "$SETTINGS"; then
				note "no Eve entries found in $SETTINGS"
			else
				mv "$stripped" "$SETTINGS"
				note "removed Eve's hook entries from $SETTINGS"
			fi
		else
			[ -s "$TMPD/jq.err" ] && warn "$(cat "$TMPD/jq.err")"
			warn "could not edit JSON automatically."
			say ""
			say "   MANUAL STEP: open $SETTINGS and delete any hook entry whose"
			say "   \"command\" ends in one of:"
			say "     eve-recall.sh  eve-session-start.sh  eve-session-end.sh  eve-guard.sh"
			say "   Leave every other entry alone."
			say ""
		fi
	fi
fi

[ -f "$SETTINGS_BAK" ] && note "backup kept at $SETTINGS_BAK (delete it yourself when happy)"

# --------------------------------------------------------------------------
# 2. CLAUDE.md
# --------------------------------------------------------------------------

step "2/3  CLAUDE.md"

if [ ! -f "$CLAUDE_MD" ]; then
	note "not present: $CLAUDE_MD"
elif ! grep -q '^<!-- eve:begin -->$' "$CLAUDE_MD"; then
	note "no Eve block in $CLAUDE_MD"
elif [ "$DRY_RUN" -eq 1 ]; then
	note "would remove the <!-- eve:begin --> ... <!-- eve:end --> block from $CLAUDE_MD"
else
	out="$TMPD/CLAUDE.md"
	# Drop the sentinels and everything between them, then trim trailing blank
	# lines so an uninstall/reinstall cycle does not accumulate whitespace.
	awk '
    /^<!-- eve:begin -->$/ { skip = 1; next }
    /^<!-- eve:end -->$/   { skip = 0; next }
    skip != 1 { print }
  ' "$CLAUDE_MD" | awk '
    { lines[NR] = $0 }
    END {
      last = NR
      while (last > 0 && lines[last] ~ /^[ \t]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }
  ' >"$out"
	mv "$out" "$CLAUDE_MD"
	note "removed the Eve block from $CLAUDE_MD (nothing outside the sentinels changed)"
fi

# --------------------------------------------------------------------------
# 3. what stays
# --------------------------------------------------------------------------

step "3/3  your data"

if [ -d "$EVE_HOME" ]; then
	mem=0
	[ -d "$EVE_HOME/memory" ] &&
		mem=$(find "$EVE_HOME/memory" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
	note "kept $mem memory file(s) in $EVE_HOME/memory"
	note "kept session logs and state in $EVE_HOME"
	note "nothing under $EVE_HOME was read, moved, or deleted by this script."
	say ""
	say "   If you also want the store gone, that is your call to make, not mine:"
	say "     rm -rf \"$EVE_HOME\""
else
	note "$EVE_HOME does not exist; nothing to keep"
fi

if [ "$DRY_RUN" -eq 0 ] && [ -d "$EVE_HOME/state" ]; then
	printf '%s\tuninstall\tsettings=%s\tclaude_md=%s\trestore=%s\n' \
		"$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$SETTINGS" "$CLAUDE_MD" "$RESTORE" \
		>>"$EVE_HOME/state/install.log" 2>/dev/null || true
fi

say ""
say "-------------------------------------------------------------------"
say "Eve is unwired. Start a new Claude Code session for it to take effect;"
say "hooks are read at session start, so the current session still has them."
say "Reinstall any time with: $REPO_DIR/install.sh"
