#!/usr/bin/env bash
# Fail on silently dropped Kconfig entries, wrong profiles or unwanted software.
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
BUILD_PATH=${1:?Usage: validate-config.sh BUILD_PATH [MANIFEST]}
CONFIG_PATH="$BUILD_PATH/.config"
grep -qx 'CONFIG_HAVE_DOT_CONFIG=y' "$CONFIG_PATH" || {
    echo 'Run make defconfig first; an unexpanded configuration stub cannot be validated' >&2
    exit 1
}
TARGET=CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-cs-02
grep -qx "$TARGET=y" "$CONFIG_PATH" || { echo 'Athena target missing' >&2; exit 1; }
if grep -Eq '^CONFIG_TARGET_(MULTI_PROFILE|ALL_PROFILES|PER_DEVICE_ROOTFS)=y' "$CONFIG_PATH"; then
    echo 'Only a single Athena profile is allowed' >&2
    exit 1
fi

for fragment in "$SCRIPT_DIR/deconfig/jdcloud_ipq60xx_libwrt.config" \
    "$SCRIPT_DIR/deconfig/compile_base.config" \
    "$SCRIPT_DIR/deconfig/fragments/docker_deps.config" \
    "$SCRIPT_DIR/deconfig/fragments/vowifi.config" \
    "$SCRIPT_DIR/deconfig/fragments/ec20.config"; do
    while IFS= read -r entry; do
        [[ $entry =~ ^CONFIG_[A-Za-z0-9_-]+=y$ ]] || continue
        grep -qxF "$entry" "$CONFIG_PATH" || {
            echo "Required option missing after defconfig: $entry" >&2
            exit 1
        }
    done < "$fragment"
done

# CONFIG_CRYPTO_AES is Linux's symbol, not an OpenWrt CONFIG_KERNEL_* symbol.
grep -qx 'CONFIG_CRYPTO_AES=y' "$BUILD_PATH/target/linux/generic/config-6.12" || {
    echo 'AES is no longer built into the kernel; review the crypto configuration' >&2
    exit 1
}
grep -qx 'CONFIG_OVERLAY_FS=y' "$BUILD_PATH/target/linux/generic/config-6.12" || {
    echo 'Overlayfs is no longer built into the kernel; review Docker storage support' >&2
    exit 1
}
if grep -Eq '^CONFIG_PACKAGE_(adguardhome|smartdns|mosdns|mihomo|sing-box|xray-core|easytier|luci-app-(adguardhome|smartdns|mosdns|openclash|passwall2?|homeproxy|ssr-plus|easytier|lucky|samba4|cupsd|istorex|quickfile|dockerman))=[ym]$' "$CONFIG_PATH"; then
    echo 'Unwanted DNS/proxy/NAS application selected' >&2
    exit 1
fi

if [[ -n ${2:-} ]]; then
    MANIFEST=$2
    # These packages must be installed in the image, not just built as modules.
    while IFS= read -r entry; do
        [[ $entry =~ ^CONFIG_PACKAGE_(.+)=y$ ]] || continue
        package=${BASH_REMATCH[1]}
        awk -v package="$package" '$1 == package {found=1} END {exit !found}' "$MANIFEST" || {
            echo "Required package absent from firmware manifest: $package" >&2
            exit 1
        }
    done < <(cat "$SCRIPT_DIR/deconfig/fragments/"{docker_deps,vowifi,ec20}.config)
fi
echo 'Validated: Athena only, Docker, XFRM/IPsec, AES-CBC/SHA1 and EC20.'
