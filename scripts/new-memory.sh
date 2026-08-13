#!/bin/sh
# new-memory.sh -- scaffold one memory file from the template, and index it.
#
# POSIX sh. Uses awk, sed, tr, date -- nothing else. No network, no config,
# no state. It writes exactly two files: the new memory, and one line in the
# index. It never overwrites and never deletes.
#
#   scripts/new-memory.sh "Deploys are blocked after 18:00 UTC"
#   scripts/new-memory.sh -t reference "Carrier API throttles with an empty 200"
#   EVE_KB_ROOT="$HOME/kb" scripts/new-memory.sh -t decision "Drop offset paging"
#
# Store resolution, in order: -s DIR, $EVE_KB_ROOT, $EVE_HOME/memory,
# ~/.eve/memory if it exists, else the repo's memory/ dir.
# If the store has bucket directories (notes/, decisions/, projects/,
# research/) the file is placed in the bucket matching its type; otherwise the
# store is treated as flat.
#
# Exit codes: 0 wrote it, 1 refused (target exists, missing template), 64 usage.

set -eu

PROG=$(basename "$0")

usage() {
	cat <<'EOF'
usage: new-memory.sh [options] <title...>

The title is the memory's claim, written as a sentence. State the conclusion:
"Deploys are blocked after 18:00 UTC", not "Deploy notes".

options:
  -t, --type TYPE       feedback | project | decision | reference | note
                        (default: note; any lowercase-kebab value is accepted)
  -n, --id SLUG         filename stem; default is the slugified title
  -s, --store DIR       store root (default: $EVE_KB_ROOT, $EVE_HOME/memory,
                        ~/.eve/memory, else the repo's memory/)
  -i, --index FILE      index file (default: MEMORY.md / INDEX.md in the store)
  -T, --template FILE   template (default: TEMPLATE.md in the store, else the
                        repo's memory/TEMPLATE.md)
  -e, --edit            open the new file in $EDITOR
  -h, --help            this text

examples:
  new-memory.sh -t feedback "Show the failing assertion before proposing a fix"
  new-memory.sh -t project  "Manifest ingest has exactly one writer"
EOF
}

die() {
	printf '%s: %s\n' "$PROG" "$1" >&2
	exit "${2:-1}"
}

need_arg() {
	if [ "$2" -lt 2 ]; then
		die "missing argument to $1" 64
	fi
}

TYPE=note
SLUG=
STORE=
INDEX=
TEMPLATE=
OPEN_EDITOR=0

while [ $# -gt 0 ]; do
	case $1 in
	-t | --type)
		need_arg "$1" $#
		TYPE=$2
		shift 2
		;;
	-n | --id)
		need_arg "$1" $#
		SLUG=$2
		shift 2
		;;
	-s | --store)
		need_arg "$1" $#
		STORE=$2
		shift 2
		;;
	-i | --index)
		need_arg "$1" $#
		INDEX=$2
		shift 2
		;;
	-T | --template)
		need_arg "$1" $#
		TEMPLATE=$2
		shift 2
		;;
	-e | --edit)
		OPEN_EDITOR=1
		shift
		;;
	-h | --help)
		usage
		exit 0
		;;
	--)
		shift
		break
		;;
	-*)
		die "unknown option: $1 (try --help)" 64
		;;
	*)
		# Options may follow the title: `new-memory.sh "some title" --type feedback`
		# reads naturally and is what people type. Stash this word and keep
		# parsing instead of stopping here, which would silently make "--type"
		# and "feedback" part of the title.
		TITLE_WORDS="${TITLE_WORDS:+$TITLE_WORDS }$1"
		shift
		;;
	esac
done

# Anything after `--` is title text, taken literally.
while [ $# -gt 0 ]; do
	TITLE_WORDS="${TITLE_WORDS:+$TITLE_WORDS }$1"
	shift
done

if [ -z "${TITLE_WORDS:-}" ]; then
	usage >&2
	exit 64
fi

# ---------------------------------------------------------------- title, slug

# Drop control characters and backslashes: the title is written into YAML
# front matter that a deliberately small parser has to read back.
TITLE=$(printf '%s' "$TITLE_WORDS" | tr -d '\\#\r\n\t' | sed 's/  */ /g; s/^ //; s/ $//')
if [ -z "$TITLE" ]; then
	die "empty title" 64
fi

if [ -z "$SLUG" ]; then
	SLUG=$(printf '%s' "$TITLE" |
		LC_ALL=C tr '[:upper:]' '[:lower:]' |
		LC_ALL=C sed 's/[^a-z0-9]/-/g; s/--*/-/g; s/^-//; s/-$//' |
		cut -c1-60 |
		sed 's/-*$//')
fi

case $SLUG in
'' | *[!a-z0-9-]*)
	die "could not build a filename from that title; pass -n <slug>" 64
	;;
esac

case $TYPE in
'' | *[!a-z0-9-]*)
	die "type must be lowercase letters, digits and dashes" 64
	;;
esac

TYPE_KNOWN=0
for known in feedback project decision reference note; do
	if [ "$TYPE" = "$known" ]; then
		TYPE_KNOWN=1
	fi
done

# ------------------------------------------------------------ store, template

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(dirname "$SCRIPT_DIR")

if [ -z "$STORE" ]; then
	if [ -n "${EVE_KB_ROOT:-}" ]; then
		STORE=$EVE_KB_ROOT
	elif [ -n "${EVE_HOME:-}" ]; then
		STORE=$EVE_HOME/memory
	elif [ -d "$HOME/.eve/memory" ]; then
		STORE=$HOME/.eve/memory
	else
		STORE=$REPO_DIR/memory
	fi
fi
case $STORE in
"~") STORE=$HOME ;;
"~/"*) STORE=$HOME/${STORE#"~/"} ;;
esac
if [ ! -d "$STORE" ]; then
	mkdir -p "$STORE"
fi
STORE=$(cd "$STORE" && pwd)

if [ -z "$TEMPLATE" ]; then
	if [ -f "$STORE/TEMPLATE.md" ]; then
		TEMPLATE=$STORE/TEMPLATE.md
	else
		TEMPLATE=$REPO_DIR/memory/TEMPLATE.md
	fi
fi
if [ ! -f "$TEMPLATE" ]; then
	die "template not found: $TEMPLATE (pass -T)"
fi

case $TYPE in
decision) BUCKET=decisions ;;
project) BUCKET=projects ;;
reference) BUCKET=research ;;
*) BUCKET=notes ;;
esac

if [ -d "$STORE/$BUCKET" ]; then
	TARGET_DIR=$STORE/$BUCKET
else
	TARGET_DIR=$STORE
fi

FILE=$TARGET_DIR/$SLUG.md
if [ -e "$FILE" ]; then
	die "refusing to overwrite $FILE"
fi

# ------------------------------------------------------------------- render

DATE=$(date +%Y-%m-%d)
TMP=$FILE.new.$$

cleanup() {
	if [ -n "${TMP:-}" ] && [ -f "$TMP" ]; then
		rm -f "$TMP"
	fi
}
trap cleanup EXIT INT TERM

# Values travel through the environment, not through -v: awk interprets
# backslash escapes in -v assignments, and a title is user text.
EVE_ID=$SLUG EVE_TITLE=$TITLE EVE_TYPE=$TYPE EVE_DATE=$DATE awk '
function repl(s, key, val,   out, p) {
	out = ""
	while ((p = index(s, key)) > 0) {
		out = out substr(s, 1, p - 1) val
		s = substr(s, p + length(key))
	}
	return out s
}
BEGIN {
	id    = ENVIRON["EVE_ID"]
	title = ENVIRON["EVE_TITLE"]
	type  = ENVIRON["EVE_TYPE"]
	date  = ENVIRON["EVE_DATE"]
	skip = 0
	pending = 0
}
/^<!-- eve:template-help/ { skip = 1; next }
skip == 1 {
	if (index($0, "-->") > 0) { skip = 0 }
	next
}
{
	line = $0
	line = repl(line, "{{ID}}", id)
	line = repl(line, "{{TITLE}}", title)
	line = repl(line, "{{TYPE}}", type)
	line = repl(line, "{{DATE}}", date)
	if (line ~ /^[ \t]*$/) { pending++; next }
	while (pending > 0) { print ""; pending-- }
	print line
}
' "$TEMPLATE" >"$TMP"

if [ ! -s "$TMP" ]; then
	die "template rendered empty: $TEMPLATE"
fi

mv "$TMP" "$FILE"
TMP=

# -------------------------------------------------------------------- index

STORE_PARENT=$(dirname "$STORE")
if [ -z "$INDEX" ]; then
	for cand in "$STORE/MEMORY.md" "$STORE/INDEX.md" "$STORE/index.md" \
		"$STORE_PARENT/INDEX.md" "$STORE_PARENT/MEMORY.md"; do
		if [ -f "$cand" ]; then
			INDEX=$cand
			break
		fi
	done
fi
if [ -z "$INDEX" ]; then
	INDEX=$STORE/MEMORY.md
fi
if [ ! -f "$INDEX" ]; then
	printf '# Memory index\n\nOne line per memory: the claim, not the topic.\n' >"$INDEX"
fi

INDEX_DIR=$(cd "$(dirname "$INDEX")" && pwd)
case $FILE in
"$INDEX_DIR"/*) REL=${FILE#"$INDEX_DIR"/} ;;
*) REL=$FILE ;;
esac

LINE="- [$TITLE]($REL) — $TYPE, created $DATE"
INDEXED=no

if grep -F "]($REL)" "$INDEX" >/dev/null 2>&1; then
	INDEXED=already
else
	ITMP=$INDEX.new.$$
	EVE_LINE=$LINE EVE_MARK="<!-- eve:section type=$TYPE -->" awk '
	BEGIN {
		line = ENVIRON["EVE_LINE"]
		mark = ENVIRON["EVE_MARK"]
		insec = 0; done = 0; pending = 0
	}
	{
		if (substr($0, 1, 3) == "## ") {
			if (insec == 1 && done == 0) { print line; done = 1 }
			insec = 0
		}
		if (index($0, mark) > 0) { insec = 1 }
		if ($0 ~ /^[ \t]*$/) { pending++; next }
		while (pending > 0) { print ""; pending-- }
		print
		last = $0
	}
	END {
		if (insec == 1 && done == 0) { print line; done = 1 }
		if (done == 0) {
			# No section marker for this type: append at the end, joining an
			# existing list rather than orphaning the line after a blank.
			if (substr(last, 1, 2) != "- ") { print "" }
			print line
		}
	}
	' "$INDEX" >"$ITMP"

	if [ -s "$ITMP" ]; then
		mv "$ITMP" "$INDEX"
		INDEXED=yes
	else
		rm -f "$ITMP"
		die "index rewrite produced an empty file; $INDEX left unchanged"
	fi
fi

# -------------------------------------------------------------------- report

printf 'wrote    %s\n' "$FILE"
case $INDEXED in
yes) printf 'indexed  %s\n' "$INDEX" ;;
already) printf 'indexed  %s (line already present)\n' "$INDEX" ;;
*) printf 'indexed  no\n' ;;
esac
if [ "$TYPE_KNOWN" -eq 0 ]; then
	printf 'note     type "%s" is not one of feedback/project/decision/reference/note\n' "$TYPE"
fi
printf 'next     fill in Why and How to apply; a memory without them gets misapplied\n'

if [ "$OPEN_EDITOR" -eq 1 ]; then
	if [ -z "${EDITOR:-}" ]; then
		die "-e given but EDITOR is not set"
	fi
	# Word splitting is intentional: EDITOR may carry flags.
	# shellcheck disable=SC2086
	$EDITOR "$FILE"
fi
