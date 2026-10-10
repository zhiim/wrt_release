#!/usr/bin/env bash
# This fork builds only JDCloud Athena (RE-CS-02), using upstream LibWrt.
set -euo pipefail
REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BASE_PATH="$REPO_ROOT/wrt_core"
DEVICE=jdcloud_ipq60xx_libwrt

usage() {
    echo "Usage: $0 [jdcloud_ipq60xx_libwrt] [debug|compile|config_preview]"
    echo '  default: prepare sources, configure, download and build Athena firmware'
    echo '  debug: prepare sources and validate defconfig, then stop'
    echo '  compile: build an already configured source tree (used by Actions)'
    echo '  config_preview: print configuration without downloading or building'
}
if [[ ${1:-} == "$DEVICE" ]]; then shift; fi
MODE=${1:-build}
[[ $# -le 1 ]] || { usage >&2; exit 2; }
case "$MODE" in
    build|debug|compile|config_preview) ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac
if [[ -n ${ADD_CONFIG_FRAGMENTS:-}${REMOVE_CONFIG_FRAGMENTS:-} ]]; then
    echo 'This fork has a fixed minimal configuration; edit the tracked fragments instead.' >&2
    exit 2
fi
INI_FILE="$BASE_PATH/compilecfg/$DEVICE.ini"
ini() { awk -F= -v key="$1" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "$INI_FILE"; }
REPO_URL=$(ini REPO_URL)
REPO_BRANCH=$(ini REPO_BRANCH)
COMMIT_HASH=$(ini COMMIT_HASH)
BUILD_PATH="$REPO_ROOT/$(ini BUILD_DIR)"
if [[ ${GITHUB_ACTIONS:-false} == true || -d "$REPO_ROOT/action_build" ]]; then
    BUILD_PATH="$REPO_ROOT/action_build"
fi
CONFIG_FILES=("$BASE_PATH/deconfig/$DEVICE.config" "$BASE_PATH/deconfig/compile_base.config")
IFS=, read -r -a FRAGMENTS <<< "$(ini CONFIG_FRAGMENTS)"
for fragment in "${FRAGMENTS[@]}"; do
    CONFIG_FILES+=("$BASE_PATH/deconfig/fragments/$fragment.config")
done
if [[ $MODE == config_preview ]]; then
    printf 'Device: JDCloud Athena (RE-CS-02)\nSource: %s [%s] @ %s\n' "$REPO_URL" "$REPO_BRANCH" "$COMMIT_HASH"
    cat "${CONFIG_FILES[@]}"
    exit 0
fi
if [[ $MODE != compile ]]; then
    bash "$BASE_PATH/update.sh" "$REPO_URL" "$REPO_BRANCH" "$BUILD_PATH" "$COMMIT_HASH"
    cat "${CONFIG_FILES[@]}" > "$BUILD_PATH/.config"
    make -C "$BUILD_PATH" defconfig
fi
bash "$BASE_PATH/validate-config.sh" "$BUILD_PATH"
[[ $MODE != debug ]] || exit 0

JOBS=${BUILD_JOBS:-$(nproc)}
[[ $JOBS =~ ^[1-9][0-9]*$ ]] || { echo 'BUILD_JOBS must be a positive integer' >&2; exit 2; }
TARGET_DIR="$BUILD_PATH/bin/targets/qualcommax/ipq60xx"
# Remove only stale image output, retaining matching .ipk/.apk packages.
if [[ -d $TARGET_DIR ]]; then
    find "$TARGET_DIR" -maxdepth 1 -type f \( -name '*.bin' -o -name '*.manifest' -o -name '*.itb' -o -name '*.json' \) -delete
fi
make -C "$BUILD_PATH" download -j"$JOBS"
make -C "$BUILD_PATH" -j"$JOBS" || make -C "$BUILD_PATH" -j1 V=s
shopt -s nullglob
MANIFESTS=("$TARGET_DIR/"*jdcloud_re-cs-02*.manifest)
SYSUPGRADES=("$TARGET_DIR/"*jdcloud_re-cs-02*sysupgrade.bin)
[[ ${#MANIFESTS[@]} -eq 1 && ${#SYSUPGRADES[@]} -eq 1 ]] || {
    echo 'Expected exactly one Athena manifest and sysupgrade image' >&2
    exit 1
}
bash "$BASE_PATH/validate-config.sh" "$BUILD_PATH" "${MANIFESTS[0]}"
FIRMWARE_DIR="$REPO_ROOT/firmware"
rm -rf -- "$FIRMWARE_DIR"
mkdir -p "$FIRMWARE_DIR"
for file in "$TARGET_DIR/"*jdcloud_re-cs-02*; do
    [[ ! -f $file ]] || cp -- "$file" "$FIRMWARE_DIR/"
done
cp -- "$BUILD_PATH/.config" "$FIRMWARE_DIR/build.config"
cp -- "$BUILD_PATH/build-info.txt" "$FIRMWARE_DIR/build-info.txt"
cp -- "$BUILD_PATH/feeds.buildinfo" "$FIRMWARE_DIR/feeds.buildinfo"
# Save the packages built with this exact kernel to avoid feed/kernel mismatches.
PACKAGE_LIST=$(mktemp)
trap 'rm -f -- "$PACKAGE_LIST"' EXIT
(cd "$BUILD_PATH/bin" && find . -type f \( -name '*.ipk' -o -name '*.apk' \) -print | LC_ALL=C sort) > "$PACKAGE_LIST"
[[ -s $PACKAGE_LIST ]] || { echo 'No matching packages found' >&2; exit 1; }
tar -C "$BUILD_PATH/bin" -czf "$FIRMWARE_DIR/packages-athena.tar.gz" -T "$PACKAGE_LIST"
(cd "$FIRMWARE_DIR" && sha256sum ./* > sha256sums)
printf 'Firmware and matching packages: %s\n' "$FIRMWARE_DIR"
