#!/usr/bin/env bash
# Minimal upstream setup. No custom feeds, proxy downloads or Docker replacement.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_URL=${1:?Missing source URL}
REPO_BRANCH=${2:?Missing source branch}
BUILD_PATH=${3:?Missing build directory}
COMMIT_HASH=${4:?Missing pinned commit}
[[ $BUILD_PATH == /* ]] || BUILD_PATH="$(pwd)/$BUILD_PATH"
[[ $COMMIT_HASH =~ ^[0-9a-f]{40}$ ]] || { echo 'COMMIT_HASH must pin a full source commit' >&2; exit 2; }
if [[ ! -d $BUILD_PATH ]]; then
    git clone --depth=1 --single-branch --branch "$REPO_BRANCH" "$REPO_URL" "$BUILD_PATH"
fi
[[ $(git -C "$BUILD_PATH" remote get-url origin) == "$REPO_URL" ]] || {
    echo 'Build directory belongs to another source repository' >&2
    exit 1
}
# Preserve local source edits instead of resetting or cleaning them silently.
git -C "$BUILD_PATH" diff --quiet
git -C "$BUILD_PATH" diff --cached --quiet
if ! git -C "$BUILD_PATH" cat-file -e "$COMMIT_HASH^{commit}" 2>/dev/null; then
    git -C "$BUILD_PATH" fetch --depth=1 origin "$COMMIT_HASH"
fi
git -C "$BUILD_PATH" checkout --detach "$COMMIT_HASH"
cd "$BUILD_PATH"
make prereq
./scripts/feeds update -a
for feed in nss_packages packages luci; do
    [[ -s "feeds/$feed.index" ]] || {
        echo "Empty package index for feed $feed; aborting instead of building an incomplete image" >&2
        exit 1
    }
done
./scripts/feeds install -a
./scripts/feeds list -s > feeds.buildinfo
{
    printf 'Source: %s\nBranch: %s\nCommit: %s\n' "$REPO_URL" "$REPO_BRANCH" "$(git rev-parse HEAD)"
    printf 'Configuration repository: %s\n' "$(git -C "$SCRIPT_DIR/.." rev-parse HEAD)"
    printf 'Build UTC: %s\n' "$(date -u +%FT%TZ)"
} > build-info.txt
