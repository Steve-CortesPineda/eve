#!/bin/sh
# Cloud Agent install step for Eve.
#
# WHY THIS EXISTS
#   Eve has no build and no project dependencies: recall is POSIX sh + awk, the
#   eval suite is Python 3 standard library only, the npm shim is pure dispatch,
#   and bin/eve runs straight from the clone. The default Cloud Agent image
#   already ships sh, awk, python3, node, jq, git and make, so there is nothing
#   to compile or fetch here.
#
#   The one tool CI relies on that is NOT in the base image is shellcheck -- the
#   `shellcheck` lint job in .github/workflows/ci.yml. Installing it lets an
#   agent run the exact lint CI runs. Everything else Eve needs is already
#   present, so this script installs shellcheck and nothing else.
#
# IDEMPOTENCE
#   Safe to run twice. If shellcheck is already installed it changes nothing and
#   says so, matching the rest of this repo's install/uninstall scripts.
set -eu

if command -v shellcheck >/dev/null 2>&1; then
	echo "shellcheck already present; nothing to install."
	shellcheck --version | sed -n 's/^version: /  shellcheck /p'
	exit 0
fi

echo "installing shellcheck (used by the CI lint job) ..."
sudo apt-get update
sudo apt-get install -y --no-install-recommends shellcheck
shellcheck --version | sed -n 's/^version: /  shellcheck /p'
