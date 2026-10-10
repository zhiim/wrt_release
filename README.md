# 京东云雅典娜最小 LibWrt 固件

本 fork 只构建京东云雅典娜 / RE-CS-02（AX6600）。源码为
[LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x) 的 `25.12-nss` 分支，
源码提交固定在 `wrt_core/compilecfg/jdcloud_ipq60xx_libwrt.ini` 的 `COMMIT_HASH`。
保留上游 Wi-Fi 固件、NSS 驱动与默认硬件设置，不运行原仓库的第三方软件包替换流程。
旧设备配置和模块文件仅作为历史参考，构建入口不再使用它们。

## 固件内容

| 功能 | 内容 |
| --- | --- |
| 基础路由 | LuCI（含中文）、Dropbear SSH、dnsmasq、DHCP/IPv6、PPPoE、firewall4 |
| Docker | docker、dockerd、containerd、runc、overlayfs、cgroups、namespaces、seccomp、iptables-nft |
| IPsec / XFRM | ip-full、kmod-ipsec、kmod-ipsec4、kmod-ipsec6 |
| IPsec 加密 | kmod-crypto-authenc、kmod-crypto-cbc、kmod-crypto-hmac、kmod-crypto-sha1；AES 已内置于内核 |
| EC20 串口 | kmod-usb-serial、kmod-usb-serial-wwan、kmod-usb-serial-option |
| EC20 网络 | kmod-usb-wdm、kmod-usb-net-qmi-wwan、uqmi、luci-proto-qmi；另含 ECM/RNDIS 驱动 |
| 基础存储/诊断 | eMMC/USB ext4 支持、block-mount、e2fsprogs、usbutils、picocom |

不包含 SmartDNS、MosDNS、AdGuardHome、OpenClash、PassWall、HomeProxy、
SSR Plus、Xray、sing-box、Mihomo、EasyTier、Lucky、iStore、Samba、CUPS 或 Dockerman。
“不要 DNS 工具”按不包含额外 DNS 应用理解；仍保留基础 dnsmasq，供局域网 DHCP/DNS 使用。
上游自动解析的硬件与 Docker 依赖会随源码/feeds 变化，不保证仅安装表中包名。

AES 在此源码的 `target/linux/generic/config-6.12` 中为 `CONFIG_CRYPTO_AES=y`，
不存在独立 `kmod-crypto-aes` 包。不要向 OpenWrt `.config` 添加不存在的包名。

## GitHub Actions 编译

1. 打开 **Actions → Build Athena LibWrt → Run workflow**。
2. 默认只编译并上传 Artifact；勾选 `publish` 才会发布 Release。
3. 也可运行 **Release Athena LibWrt**，它复用相同构建流程并发布 Release。
4. 下载 `athena-libwrt-*` Artifact，或者 Release 的固件文件。

Actions 只缓存 `dl` 和 `.ccache`，不复用 `staging_dir` 或修改构建时间戳。
配置阶段与固件 manifest 阶段都会检查必要的软件包；缺失就失败，不交付缺包固件。

## 本地编译

推荐 Ubuntu 24.04，至少预留 60 GB 磁盘空间。安装依赖：

```bash
sudo apt-get update
sudo apt-get install -y build-essential clang flex bison g++ gawk gcc-multilib \
  gettext git libncurses-dev libssl-dev python3 python3-setuptools rsync swig \
  unzip zlib1g-dev file wget curl zstd libelf-dev autoconf automake libtool \
  pkg-config cmake ninja-build ccache

git clone https://github.com/zhiim/wrt_release.git
cd wrt_release
./build.sh
```

本地使用 `libwrt/` 作为工作目录；Actions 使用 `action_build/`。
OpenWrt 构建应以普通用户执行。脚本支持从任意当前目录调用。

```bash
./build.sh config_preview               # 仅打印所选配置，不下载源码
./build.sh debug                        # 拉取源码、展开并验证配置，停止于 defconfig
./build.sh compile                      # 继续构建已配置的源码树，不再次更新 feeds
BUILD_JOBS=4 ./build.sh                 # 限制并发
./build.sh jdcloud_ipq60xx_libwrt        # 兼容原来的设备参数
```

此 fork 不提供其他机型或临时 add/remove fragments 入口。
需要改包时编辑以下文件，先运行 `debug` 验证，再运行 `compile`：

- `wrt_core/deconfig/jdcloud_ipq60xx_libwrt.config`：唯一硬件目标与存储/USB 控制器。
- `wrt_core/deconfig/compile_base.config`：基础路由与排除项。
- `wrt_core/deconfig/fragments/docker_deps.config`：Docker。
- `wrt_core/deconfig/fragments/vowifi.config`：XFRM/IPsec 和加密。
- `wrt_core/deconfig/fragments/ec20.config`：EC20 驱动与工具。

## 构建产物

`firmware/` 包含雅典娜固件、manifest、完整 `build.config`、`build-info.txt`、
`feeds.buildinfo`、`sha256sums` 和 `packages-athena.tar.gz`。
后者包含本次编译生成的 `.ipk` / `.apk` 包，尤其是与该固件内核 ABI 匹配的 kmod。
不要安装其他版本 OpenWrt/ImmortalWrt 源里的内核模块。

源码提交固定；feeds 按上游配置更新，并记录精确版本在 `feeds.buildinfo` 中。
升级源码时同步修改 `COMMIT_HASH`，并重新运行配置检查和完整构建。

## 刷入后的检查

Docker 上游默认数据路径为 `/opt/docker/`。启动 Docker 前，确认 `/opt` 已挂载到
用于存储容器数据的 eMMC/USB 分区；挂载点本身不能保证数据写入外部分区。

```sh
ip -V
ip xfrm state list
ip xfrm policy list
# 无已建立连接时 state/policy 为空是正常的；不应出现 Protocol not supported。
grep -E 'cbc\(aes\)|sha1|authenc' /proc/crypto

docker version
/etc/init.d/dockerd start
docker info
# 实际拉取运行会访问外部镜像仓库：
# docker run --rm hello-world

lsusb
ls /dev/ttyUSB* /dev/cdc-wdm* 2>/dev/null
dmesg | grep -Ei 'usb|option|qmi|wwan'
# AT 端口编号取决于模块 USB composition，用实际的端口替换：
# picocom -b 115200 /dev/ttyUSB2
# uqmi -d /dev/cdc-wdm0 --get-capabilities
```

`lsusb` 显示的文字名称不能说明驱动绑定是否成功；应检查 `ttyUSB*`、`cdc-wdm*`
和内核日志。这里配置正常工作模式下的 EC20 串口/QMI/ECM/RNDIS 支持，
不能修复模块固件故障、USB 供电不足或模块停在下载模式的问题。

本仓库提供 VoCat 所需的底层支持，不预装 VoCat 或 strongSwan，不保证 VOXI IMS 注册。
VoCat、9eSIM 配置和 UDP 4500 网络链路需另行部署测试。
刷机前仍需确认当前 U-Boot、GPT/分区布局与此上游的雅典娜镜像兼容。
