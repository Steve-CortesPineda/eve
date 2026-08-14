#!/bin/sh
# Eve retrieval-recall eval — convenience wrapper.
#
#   sh evals/recall/run.sh                    score the repo's bin/eve
#   sh evals/recall/run.sh -v                 print every query and its result
#   sh evals/recall/run.sh --eve /path/to/eve score a different build
#   sh evals/recall/run.sh --update-baseline  re-record the floor, deliberately
#
# Exit 0 pass, 1 regression against the committed baseline, 2 harness error.
# All arguments are passed through to run.py. POSIX sh; the only dependency is
# python3, which is the same dependency the sibling suite already has.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if command -v python3 >/dev/null 2>&1; then
	py=python3
elif command -v python >/dev/null 2>&1 &&
	python -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' 2>/dev/null; then
	py=python
else
	echo "evals/recall: python3 not found. Install python3 (macOS: xcode-select --install)." >&2
	exit 2
fi

exec "$py" "$here/run.py" "$@"
