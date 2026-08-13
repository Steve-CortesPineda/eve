#!/bin/sh
# Eve hallucination eval — convenience wrapper.
#
#   sh evals/run.sh                       offline, reference answerer
#   sh evals/run.sh --answerer naive -v   a real but ungrounded retriever
#   sh evals/run.sh --cmd './my-agent'    your own agent
#
# All arguments are passed through to run.py. POSIX sh; the only dependency is
# python3, which ships with macOS and every mainstream Linux.

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if command -v python3 >/dev/null 2>&1; then
    py=python3
elif command -v python >/dev/null 2>&1 && python -c 'import sys; sys.exit(0 if sys.version_info[0]==3 else 1)' 2>/dev/null; then
    py=python
else
    echo "evals: python3 not found. Install python3 (macOS: xcode-select --install)." >&2
    exit 2
fi

exec "$py" "$here/run.py" "$@"
