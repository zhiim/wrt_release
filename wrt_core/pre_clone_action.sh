#!/usr/bin/env bash
# Configure the same fixed Athena profile in the Actions build directory.
set -euo pipefail
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ -n ${1:-} && $1 != jdcloud_ipq60xx_libwrt ]]; then
    echo 'Only JDCloud Athena LibWrt is supported' >&2
    exit 2
fi
GITHUB_ACTIONS=true bash "$REPO_ROOT/build.sh" debug
