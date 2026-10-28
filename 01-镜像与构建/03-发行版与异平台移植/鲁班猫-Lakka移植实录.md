---
title: 鲁班猫 × Lakka 移植实录
summary: 把 Lakka 移植到鲁班猫的完整过程，含出图、改设备树与故障索引
board: [鲁班猫]
os: Lakka
tags: [发行版, 移植, LibreELEC]
updated: 2026-10-27
formats: [md]
---

# LubanCat × Lakka 移植实录

这份文档记录的是把 Lakka（LibreELEC 的一个发行版）移植到野火鲁班猫系列板卡上，从零到四颗芯片可用、并上机验证的完整过程。写法按当时的实际操作顺序展开，每一步都写了目的、动了哪些文件、跑了什么命令，以及踩过的坑和判断依据。

读者假设是会写代码、能读日志，但没接触过 LibreELEC 构建系统的人。如果只是想出图，看第 8、9 章；想改设备树，看第 15 章；遇到某个故障想知道为什么，直接跳第 11 章的现象索引。

---

## 0. 先看这里

### 0.1 最终成果

| 芯片 | DEVICE | 板卡（UBOOT_SYSTEM） | 上机状态 |
|---|---|---|---|
| RK3588 | `RK3588` | lubancat-5、lubancat-5-v2、lubancat-5io、lubancat-4 | 四块都能进系统、HDMI 正常；串口 shell、首次扩容、SSH 在 lubancat-5 上逐项确认 |
| RK3588S | `RK3588`（同一设备目录） | lubancat-4、lubancat-4-v1 | 4 验证过；4-V1 只做了构建 |
| RK3576 | `RK3576` | lubancat-3、lubancat-3io | 3 验证过；3IO 只做了构建 |
| RK3566 | `RK3566` | lubancat-0（Zero N）、lubancat-1、lubancat-1n | 0、1 验证过；1N 只做了构建 |
| RK3568 | `RK3568` | lubancat-2、lubancat-2-v1、-2-v2、-2-v3、lubancat-2n | 2 验证过；2-V2 验证过 MIPI 屏，音频待查 |

四颗芯片共用同一套 vendor 链：鲁班猫的 U-Boot 2017.09、BSP 内核 6.1.99、rkbin（DDR/ATF/OP-TEE）、libmali 用户态 GPU 驱动。一套源码同时服务四颗芯片，是这条路线最省事的地方。

### 0.2 环境约定

下文所有路径都以构建机为准：

```
构建机      dev@10.255.200.141        Ubuntu，4 核，/home 约 390G
仓库        /home/dev/Lakka-LibreELEC 分支 lubancat
厂商 SDK    /home/dev/LubanCat_SDK    只读参考，不参与编译
串口        1500000 8N1，设备节点 /dev/ttyFIQ0
```

仓库的远端有两个：`fork` 指向 `git@github.com:raidenkl/Lakka-LibreELEC.git`（能推），`origin` 是 gh-proxy 的上游只读镜像（只能拉）。

### 0.3 版本 pin

想复现的话，这四个 commit 决定了全部行为：

| 组件 | commit / 版本 | 位置 |
|---|---|---|
| U-Boot | `8f53f800da2c25d0c6ba414fb45902a01675703a` | `devices/<DEVICE>/packages/u-boot/package.mk` |
| 内核 | `1bc19c520831b6d0ca7d7afb4639189a2064e9bc`（6.1.99） | `devices/<DEVICE>/linux/lubancat-6.1/linux.aarch64.conf` 配合设备目录 |
| rkbin | `58a39b47f77a26a1e110fa1a1ce80bcfcb0b3505` | `devices/<DEVICE>/packages/rkbin/package.mk` |
| libmali | RK3588 用 `valhall-g610-g24p0-gbm`，RK3576/RK356x 用 `bifrost-g52-g13p0-gbm`，都是 1.9-1 的 deb | `devices/<DEVICE>/packages/libmali/package.mk` |

---

## 1. 先把 LibreELEC 的「芯片 / 板卡」模型弄清楚

这一步不写代码，但不搞清楚后面会反复迷路。

LibreELEC 里两个概念容易混：

- **DEVICE**：芯片级，对应目录 `projects/<PROJECT>/devices/<DEVICE>/`，决定构建目录名（`build.Lakka-<DEVICE>.aarch64`）、镜像文件名前缀、内核配置、u-boot 包、GPU 驱动包。
- **UBOOT_SYSTEM**：板卡级，**没有独立目录**，只在 `scripts/uboot_helper` 里占一条记录，决定两件事——用哪个 u-boot defconfig、用哪个内核 dtb。

板卡表长这样（`scripts/uboot_helper` 是个 Python 字典）：

```python
'RK3568': {
  'lubancat-2-v2': {
    'dtb': 'rk3568-lubancat-2-v2.dtb',
    'config': 'lubancat-rk3568-pcie_defconfig',
    'rockchip_legacy_boot': '1'
  },
},
```

对应关系可以从脚本直接查，不用猜：

```sh
./scripts/uboot_helper Rockchip                      # 列项目下所有芯片
./scripts/uboot_helper Rockchip RK3568               # 列该芯片所有板卡
./scripts/uboot_helper Rockchip RK3568 lubancat-2-v2 dtb
./scripts/uboot_helper Rockchip RK3568 lubancat-2-v2 config
```

**这里有一个静默故障要记住**：`scripts/mkimage` 只会把**当前板卡的那一个 dtb** 拷进 boot 分区，文件名来自 `uboot_helper`。如果 `dtb` 字段写错（比如写成 `rk3568-lubancat-2v2.dtb`），构建不会报错，只是镜像里少个文件，上电时 u-boot 找不到 FDT。所以第 8 步的构建脚本里加了「镜像里的 dtb 名 / model 字符串必须匹配」的断言，别跳过它。

---

## 2. 准备构建机

### 2.1 目的

让 `make image` 能跑到最后。LibreELEC 在 `scripts/image` 开头无条件调 `scripts/checkdeps`，缺任何一个依赖都直接退出，而且报错信息只列「provided by xxx」，不告诉你怎么装。

### 2.2 必需依赖

`checkdeps` 检查的表在 `scripts/checkdeps` 里的 `dep_map` / `file_map` / `perl_map` 三张，按它来装最省事：

```sh
sudo apt-get install -y \
  bc bzip2 curl diffutils file gawk gcc g++ gperf git gzip lzop make patch \
  perl patchutils rdfind rsync sed tar unzip wget xz-utils zip zstd \
  libc6-dev libncurses5-dev libjson-perl libparse-yapp-perl libxml-parser-perl \
  device-tree-compiler python2 u-boot-tools
```

后四个是 vendor 启动链额外要的（`device-tree-compiler` 编 dtb、`python2` 给厂商脚本、`u-boot-tools` 提供 mkimage）。

包名在不同发行版上会漂移：Ubuntu 22.04 之后 `libncurses5-dev` 改叫 `libncurses-dev`，`python2` 可能已经不在默认源里。参考的宿主是 Ubuntu 20.04，换系统时对着 `scripts/checkdeps` 的表逐项核。

### 2.3 没有 sudo 怎么办

构建机上 sudo 要密码，所以走了「把 Ubuntu 包解到 `$HOME`」这条路，做成免 sudo 垫片：

```sh
~/bin/{zstd,zstdcat,unzstd,rdfind}     # 从 pool 解出来的二进制或占位脚本
~/perl5/{JSON.pm,Parse/Yapp/Driver.pm} # 包装 core 模块的 JSON::PP
```

`rdfind` 和那两个 Perl 模块在全树里其实从来没被真正调用过，垫片只是为了让 `checkdeps` 通过——这一点当时用全树 grep 确认过，不是拍脑袋。

**注意一个反复踩的点**：这些垫片靠 `PATH` 生效，而**非交互 ssh 不读 `.bashrc`**。所以每次跑构建都必须显式传环境：

```sh
env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB" \
  ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2 -y
```

忘了这条，`checkdeps` 会在镜像组装的最后一分钟才失败，前面几个小时白跑。

### 2.4 国内网络

GitHub 直连不稳定时，构建会卡在源码获取上。仓库里有 `projects/Rockchip/tools/setup-cn-network.sh` 做三件事：

```sh
./projects/Rockchip/tools/setup-cn-network.sh            # 装上
./projects/Rockchip/tools/setup-cn-network.sh --check    # 只检查
./projects/Rockchip/tools/setup-cn-network.sh -u         # 撤掉
```

1. `git config --global url."https://gh-proxy.com/https://github.com/".insteadOf "https://github.com/"` —— 对 `git clone`、`git fetch` 和它们拉起的子进程全部生效，CMake 的 `FetchContent` 也走这条（`melondsds` 有 11 个依赖全靠它）。
2. `git config --global http.version HTTP/1.1` + `http.postbuffer=1048576000` —— 代理下 HTTP/2 的流截断会让 `git fetch` 报 `RPC failed; curl 56 GnuTLS recv error (-9)`。
3. `~/bin/wget` 包装器 —— 对 GitHub 主机依次尝试 `gh-proxy` → `ghfast` → 原地址；对非 GitHub 主机，HTTPS 失败后降级 HTTP。

**包装器本身有过一个很隐蔽的 bug，值得单独说**：早期版本按数组下标替换 URL，但镜像分支传的是剥掉 `-c`/`--tries` 的另一份参数数组，长度更短，导致下标错位——原来的 GitHub URL 没被替换掉，wget 收到两个 URL，把两份内容依次写进同一个 `-O` 文件。现象是下载文件**大小恰好是正确值的两倍**（29,021,920 = 2 × 14,510,960），然后 `Incorrect checksum` 失败。修法是按内容匹配替换：

```sh
for i in "${!a[@]}"; do
  case "${a[$i]}" in http://*|https://*) a[$i]="$u";; esac
done
```

顺带把 `-c` 全面禁掉：wget 内部重试 + `-O` 会把重试的响应追加到已写文件，是同一类风险的第二个来源。

### 2.5 源码缓存的两个格式（预置源码时会用到）

LibreELEC 缓存命中判定分两种，混了就会一直重下：

- **git 源**：`sources/<pkg>/<pkg>-<sha>.tar.xz`（顶层目录必须同名）+ `.tar.xz.gitstamp`（内容是 `PKG_URL|PKG_VERSION`），两件套。
- **归档源**：`sources/<pkg>/<pkg>` + `<pkg>.url`（内容 = `PKG_URL`）+ `<pkg>.sha256`，三件套。

git 源还要注意子模块：`scripts/get_git` 会跑 `git submodule update --init --recursive`。手工灌源时如果只 `fetch` + `checkout`，子模块目录是空的，编译到那一步才报 `No targets specified and no makefile found`（`picodrive` 的 `cpu/cyclone` 就是这么挂的）。判定方法是：tarball 里有 `.gitmodules`，但 `path=` 指向的目录没有文件。

---

## 3. 为什么选这套 vendor 链

这条路线在动手前定死，后面没再改过：

```
U-Boot 2017.09（LubanCat fork，带 make.sh/fit.sh，能直接出 Rockchip FIT 引导链）
  + 内核 6.1.99（LubanCat BSP，一套源码同时覆盖 RK3588 / RK3576 / RK356x）
  + rkbin（DDR 训练 blob、BL31、OP-TEE）
  + libmali 用户态 blob（RK3588 = G610 valhall，RK3576/356x = G52 bifrost）
```

当时考虑过的替代方案是「6.1 内核 + mesa/panthor」，结论是不成立，理由记在这里免得后人重走：

- panthor 是 Valhall（G610/G710）的 DRM 驱动，2024 年随 Linux 6.10 进主线，依赖 6.7~6.10 的 DRM 基础设施（`drm_gpuvm`、调度器改动）。6.1 里没有，只能靠社区回移分支，都已经停更。
- 即便凑出来，panthor 的价值是开源可维护、Wayland 零拷贝、支持桌面 GL，不是更高帧率。GLES 峰值仍是 blob 领先，Vulkan 上 PanVK 明显不如 ARM 官方 blob。
- 真要上开源栈，正确组合是 mainline 6.14/6.18 + panthor + Mesa，但主线缺 HDMI（4K 到 6.13 才补齐）、缺 rkvdec 硬解、缺 rkmpp、缺 NPU——这正好是 Lakka 需要的部分。

所以最终只维护一套配置。这条判断在 RK3576/RK356x 上继续沿用，效果是四颗芯片的移植工作量基本只有「设备目录 + 板卡表」。

---

## 4. 建第一个芯片的设备目录

以 RK3588 为样板，后面三颗芯片都是照它复制改的。

### 4.1 目录结构

```
projects/Rockchip/devices/RK3588/
├── options                              # 芯片级变量：CPU、内核、GPU、cmdline、核心清单
├── bootloader/config                    # u-boot 的 kconfig fragment
├── linux/lubancat-6.1/linux.aarch64.conf# 内核配置（编译时真正读的就是这份）
├── packages/
│   ├── u-boot/package.mk                # vendor make.sh 驱动 + fragment 合并 + DDR blob
│   ├── rkbin/package.mk                 # DDR/ATF/OP-TEE 的源码包
│   ├── libmali/package.mk               # GPU blob（含 vendor 的 Khronos 头）
│   └── rk-serial-console/               # 串口 root shell（第 11.3 节解释为什么需要）
├── tools/                               # build-board.sh 用到的本芯片脚本 + rkfw 打包工具
├── README.md / BUILD_GUIDE.md / CORES.md
```

一个芯片目录 42~45 个文件，其中大头是 `tools/rkfw/`（`afptool`、`rkImageMaker` 两个静态 x86-64 二进制，各约 2 MB）。

### 4.2 `options` 里每个变量在管什么

```sh
TARGET_CPU="cortex-a76.cortex-a55"   # RK3588；RK3576 用 cortex-a72.cortex-a53；RK356x 用 cortex-a55
TARGET_CPU_FLAGS="+crc+crypto"
LINUX="lubancat-6.1"                 # 决定内核源码包与 conf 目录名
KERNEL_TARGET="Image"
ROCKCHIP_LEGACY_BOOT="1"
MALI_FAMILY="g610"                   # RK3576/RK356x = g52
GRAPHIC_DRIVERS="mali"
OPENGLES="libmali"
EXTRA_CMDLINE="console=tty1 console=ttyFIQ0 coherent_pool=2M cma=64M"
ADDITIONAL_PACKAGES+=" pciutils rk-serial-console rk-audio-default"
EXCLUDE_LIBRETRO_CORES="${EXCLUDE_LIBRETRO_CORES:-} ..."
```

三个容易出错的地方：

1. **`TARGET_CPU` 必须在 `config/arch.aarch64` 的白名单里**。白名单原来只有 `cortex-a35/a53/a57/a72/a73/a75/a76.cortex-a55`，加 RK356x 时用了 `cortex-a55`，得先补进白名单（归到 `armv8-a` 那组，不要放 `armv8.2-a`，否则会带上板子没有的指令）。不补的话 `-march` 展开为空，整棵树编译失败。
2. **`EXTRA_CMDLINE` 里 `console=` 的顺序是有意义的**：内核取**最后一个** `console=` 作为 `/dev/console`（交互控制台、initramfs shell 都在这上面）。要串口能登录，`ttyFIQ0` 必须排最后。
3. **`EXCLUDE_LIBRETRO_CORES` 必须保留 `${EXCLUDE_LIBRETRO_CORES:-}` 前缀**，否则命令行追加的环境变量会被覆盖，冒烟构建就失效了。

### 4.3 `bootloader/config`：fragment 曾经从未生效

这个文件是 u-boot 的 kconfig 片段，内容不多：

```sh
CONFIG_BOOTDELAY=5
# CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_USE_PARTITION is not set
CONFIG_SYS_MMCSD_RAW_MODE_U_BOOT_SECTOR=0x4000
CONFIG_CMD_SYSBOOT=y
CONFIG_CMD_FAT=y
CONFIG_CMD_FS_GENERIC=y
```

坑有两层：

- **第一层**：厂商的 u-boot 包直接调 `./make.sh`，不像主线包那样自动把 fragment 合进 defconfig。所以这个文件写了半年也没被读过（`.config` 里 `BOOTDELAY=0`、`USE_PARTITION=y`，和文件里写的完全相反）。修法是在 `make_target()` 里 `cat` 进 `configs/<board>_defconfig`。
- **第二层**：fragment 生效之后，里面如果写了 `# CONFIG_VIDEO is not set` / `# CONFIG_DISPLAY is not set`，u-boot 链接会以 `Error 139`（SIGSEGV）结束。原因是厂商树强制编译 `drivers/video/drm/{dw_hdmi_qp.c,dw-dp.c}`，关掉 DISPLAY 后一堆 `undefined reference to drm_scdc_readb / drm_do_get_edid / ...`，ld.bfd 在大符号表上直接崩。**LubanCat 的 u-boot 树里绝不能关 VIDEO/DISPLAY**，fragment 收敛成上面那几行最小集就好。

### 4.4 `packages/u-boot/package.mk` 做的四件事

```sh
uboot_cfg="$(.../uboot_helper ... config)"; uboot_cfg="${uboot_cfg%_defconfig}"
export KCFLAGS="-Wno-error"
# 1) 把 bootloader/config 合进 defconfig（用 .lakka-pristine 保证幂等）
# 2) 需要时改 DDR blob
# 3) 选 TRUST ini（RK3566 回落到 RK3568TRUST.ini）
./make.sh CROSS_COMPILE="${TARGET_KERNEL_PREFIX}" "${uboot_cfg}" "${uboot_ini}" "${trust_ini}"
```

- **defconfig 名字要剥掉 `_defconfig` 后缀**：厂商 `make.sh` 自己拼 `configs/${ARG_BOARD}_defconfig`，而 `uboot_helper` 按主线语义返回完整文件名。不剥就会出现 `No configs/xxx_defconfig_defconfig`。
- **fragment 合并必须幂等**：同一芯片的几块板常常共用一个 defconfig（`lubancat-5` 与 `lubancat-5-v2` 都用 `lubancat-5-rk3588-pcie_defconfig`），而源码树是跨板复用的，直接 `cat >>` 第二次构建就会把每行 fragment 追加两遍。做法是留一份 `.lakka-pristine` 副本，每次从副本重建。
- **`KCFLAGS="-Wno-error"` 是必须的**：U-Boot 2017.09 的 `Makefile` 里硬编码了 `KBUILD_CFLAGS += -fshort-wchar -Werror`，没有开关；GCC 13 比厂商当年用的编译器新，`-Waddress`、`-Wmaybe-uninitialized` 直接从警告变致命错误。`KCFLAGS` 在 `-Werror` 之后追加，`-Wno-error` 会把它们降回警告，而显式的 `-Werror=implicit-function-declaration` 之类仍然有效。

### 4.5 内核配置从哪来

这一点很多人会搞错：**编译时读的不是 `arch/arm64/configs/lubancat_linux_*_defconfig`**，那个文件只是随源码带进来的厂商原文件，从不参与编译。

真正的输入是设备目录里那份：

```
projects/Rockchip/devices/RK3588/linux/lubancat-6.1/linux.aarch64.conf
```

调用链是这样的（想验证可以自己跟一遍）：

```
config/functions:1396   kernel_config_path()   → 优先找 devices/$DEVICE/linux/$LINUX/linux.aarch64.conf
packages/linux/package.mk:87   PKG_KERNEL_CFG_FILE=$(kernel_config_path)
packages/linux/package.mk:163  cp ${PKG_KERNEL_CFG_FILE} ${PKG_BUILD}/.config
然后 make olddefconfig 把 900 多行扩成 228 KB 的完整 .config
```

生成方法就是拿厂商 defconfig 加两处改动：

```sh
cp /home/dev/LubanCat_SDK/kernel-6.1/arch/arm64/configs/lubancat_linux_rk356x_defconfig \
   projects/Rockchip/devices/RK3566/linux/lubancat-6.1/linux.aarch64.conf
```

RK3588 那份 930 行，RK356x 那份 987 行，加上后面两处改动后分别是 930+ 和 997 行。`CONFIG_LOCALVERSION` 保持厂商原值（`"-rk3588"` / `"-rk3576"` / `"-rk356x"`），不要自己改——模块路径 `usr/lib/kernel-overlays/base/lib/modules/6.1.99-rk3588` 跟它绑定。

---

## 5. 内核配置只允许两处偏离厂商

厂商 defconfig 直接编出来的镜像在 Lakka 上必然起不来，不是「可能」，是「必然」。这两处改动是整条移植链里最不能省的。

### 5.1 `CONFIG_SQUASHFS_ZSTD=y`

`projects/Rockchip/options` 里设了 `SQUASHFS_COMPRESSION="zstd"`，`scripts/image` 用 `mksquashfs -comp zstd` 打 SYSTEM 分区。而厂商 defconfig 里只有 `CONFIG_ZSTD_DECOMPRESS=y`，没有 `CONFIG_SQUASHFS_ZSTD`。

现象很好认，内核日志会一字不差地打出来：

```
[    7.401073] Run /init as init process
[    7.445582] Checking disk(s): UUID=1410-3421 ...
[    7.651679] loop0: detected capacity change from 0 to 1837288
[    7.654340] Filesystem uses "zstd" compression. This is not supported
```

然后每秒重试一次，十几秒后放弃，永远到不了 `switch_root`。**看起来像「内核卡死在 7.4 秒」，其实是 initramfs 挂不上根分区**——当时查了两轮才定位到，因为不带 `ignore_loglevel` 时这几行被 `quiet` 吞了。

改完的验证有四项，建议都做：

```sh
grep '^CONFIG_SQUASHFS_ZSTD=y' $BUILD/.stamps/../../build/linux-*/.config
# 日志里应出现 CC fs/squashfs/zstd_wrapper.o
nm build/linux-*/vmlinux | grep squashfs_zstd_comp_ops
# 更强的一条：SYSTEM 分区头 32 字节里 offset 20 = 0600（压缩 id 6 = zstd）
```

### 5.2 `# CONFIG_WERROR is not set`

厂商 defconfig 是 `CONFIG_WERROR=y`，而 Lakka 的工具链是 GCC 13。老 vendor 驱动里 `&ptr->member[0]` 这种「地址恒不为 NULL」的写法会触发 `-Waddress`，被 `-Werror` 升级成致命错误：

```
drivers/net/wireless/rockchip_wlan/aic8800_usb/.../aicwf_wext_linux.c:403:25:
  error: the comparison will always evaluate as 'true' for the address of 'bssid'
  will never be NULL [-Werror=address]
```

`CONFIG_WERROR` 在 `Makefile:868` 追加 `-Werror`，位置在 `KCFLAGS` 之后，所以命令行加 `-Wno-error` 压不住，只能改配置。

### 5.3 改完怎么重编

改 `linux.aarch64.conf` 后不需要 `scripts/clean linux`——`pre_make_target()` 每次都会重新 `cp` 配置。但 kbuild 会检测到命令行变化而全量重编，实测 **25 分钟**（4 核）。

如果只是改了内核**源码或补丁**（不是 config），删掉这个 stamp 就行：

```sh
rm -f build.Lakka-<DEVICE>.aarch64/.stamps/linux/build_target
```

然后重跑 `build-board.sh`，其余包全部命中缓存，约 9 分钟出内核 + 11 分钟出图。

---

## 6. u-boot 与引导布局

### 6.1 FIT 链和 legacy 链的区别

`projects/Rockchip/bootloader/install` 里有个 `case "${DEVICE}" in`，四条分支分两种：

- `RK3588|RK3576|RK3566|RK3568` 走 **FIT 链**：厂商 `make.sh` 已经产出了 SPL loader 和 `uboot.img`（FIT 容器，内含 U-Boot + BL31/BL32），install 脚本只负责把这两个文件摆到容器里的正确偏移。
- 其它芯片（RK3288/3328/3399 等）走 **legacy 链**：用 rkbin 的 `mkimage -T rksd` 造 idbloader，`loaderimage` 打 uboot，`trust_merger` 单独合 trust.img。

新芯片能不能走 FIT 链，判据是 defconfig 里有没有 `CONFIG_ROCKCHIP_FIT_IMAGE_PACK=y`。rk3566/rk3568 的两个 LubanCat defconfig 都有，所以和 RK3576 完全同构，`install` 里的 case 只要加一行。

### 6.2 布局

容器内部偏移和磁盘偏移是两回事，容易看混：

```
容器偏移 0      → 磁盘 32 KiB (LBA 64)    : loader（idblock: ddr + spl）
容器偏移 16320  → 磁盘 8 MiB  (LBA 16384) : uboot.img（FIT: u-boot + bl31/bl32）
容器本身由 projects/Rockchip/bootloader/mkimage 用 dd bs=32k seek=1 写到磁盘 32 KiB
16320 × 512 = 8 MiB − 32 KiB
```

再往后：

```
16 MiB        boot 分区（FAT32，卷标 LAKKA），含 KERNEL / SYSTEM / dtb / extlinux
0x408000      rootfs（ext4，grow）
```

这套数字和厂商 `parameter-extboot.txt` 的 `0x00004000@0x00004000(uboot)`、`0x00040000@0x00008000(boot)` 对得上，也就是说我们的布局跟官方一致，只是我们用 MBR、官方用 GPT。

验证方式不是看日志，而是拿字节说话：

```sh
dd if=target/xxx.img bs=1 skip=32768   count=4 status=none | xxd -p   # 4c445220  "LDR "
dd if=target/xxx.img bs=1 skip=8388608 count=4 status=none | xxd -p   # d00dfeed  FIT
```

`build-board.sh` 把这两条做成了断言，每次出图自动跑。

### 6.3 DDR blob 怎么选

rkbin 为每个频点提供一个 blob，`RKBOOT/<DEVICE>MINIALL.ini` 里有两处引用（`Path1=` 和 `FlashData=`），改的时候要用文件名通配一次换掉，否则只改一处会出现「loader 里两个不同频点」的诡异状态。

四颗芯片的默认值（都已上机验证）：

| 芯片 | 默认频点 | blob |
|---|---|---|
| RK3588 | 1848 MHz | `rk3588_ddr_lp4_1848MHz_lp5_2400MHz_v1.18.bin` |
| RK3576 | 1560 MHz | `rk3576_ddr_lp4_1560MHz_lp5_2736MHz_v1.09.bin` |
| RK3566 | 1056 MHz（厂商默认） | `rk3566_ddr_1056MHz_v1.23.bin` |
| RK3568 | 1560 MHz（厂商默认） | `rk3568_ddr_1560MHz_v1.23.bin` |

注意 rk356x 的文件名**没有 `lp4_` 片段**，所以 RK3576 那套 sed 正则套过来是空操作——`DDR_FREQ` 会静默失效。RK356x 的包改成 `${soc}_ddr_[0-9]*MHz` 通配，并且**只在显式传 `DDR_FREQ` 时才改**，默认完全跟随厂商 ini。

实验其他频点：

```sh
DDR_FREQ=2112 ./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5
```

验证落地不能只看日志那行，要确认 loader 里真的是新 blob：

```sh
# 日志
grep "DDR blob ->" /tmp/lakka-build-lubancat-5.log
# 更硬的办法：把新 blob 的特征字节窗口拿去 loader 里搜
python3 - <<'EOF'
loader = open(".../rk3576_spl_loader_v1.09.107.bin","rb").read()
blob   = open(".../rk3576_ddr_lp4_1560MHz_lp5_2736MHz_v1.09.bin","rb").read()
print("1560 blob contained:", blob[0x1000:0x1100] in loader)
EOF
```

### 6.4 TRUST ini 的坑

rkbin 里**没有 `RK3566TRUST.ini`**，只有 `RK3566TRUST_ULTRA.ini`。而 RK3566/RK3568 是一对孪生芯片：两个 defconfig 都 `select CONFIG_ROCKCHIP_RK3568`，`make.sh` 解析出的 `RKCHIP` 都是 `RK3568`，厂商给这一对共用同一份 BL31/BL32。所以 RK3566 回落到 `RK3568TRUST.ini` 是对的，包里的写法：

```sh
local trust_ini="${rkbin}/RKTRUST/${DEVICE}TRUST.ini"
[ -f "${trust_ini}" ] || trust_ini="${rkbin}/RKTRUST/RK3568TRUST.ini"
[ -f "${trust_ini}" ] || die "u-boot: no TRUST ini for ${DEVICE}"
```

这条已经在 lubancat-0/1 上验证过，不是理论推导。

---

## 7. 装进镜像的东西：哪些包、装到哪

### 7.1 GPU 驱动（libmali）

`libmali` 包直接取 ARM 的 deb 包，用 `dpkg-deb -x` 解开——LibreELEC 的 `scripts/extract` 里没有 deb 分支，不自己处理就会解成一个空目录。

这个包有两个历史 bug，都是新克隆构建必挂的类型：

1. **`PKG_URL` 指向 deb，`PKG_SHA256` 却是早期本地组装的 tarball 的哈希**。原作者把 `include/` 和固件塞进 tarball 里改了 sha，但忘了改 URL。修法是统一成 deb，同时把 24 个 Khronos 头（`EGL/`、`GLES/`、`GLES2/`、`GLES3/`、`KHR/`）vendor 进包目录 `include/`，因为 deb 里没有 `usr/include`。
2. **固件装错目录**：`mali_csffw.bin` 原来被装到 `${INSTALL}/usr/lib/firmware/`，而 LibreELEC 要求这个路径是**指向 `/run/kernel-overlays/firmware` 的符号链接**，实体固件要放 `usr/lib/kernel-overlays/base/lib/firmware/`。直接创建真实目录会让 `scripts/image:274` 的 `ln -sT` 报 `File exists`，镜像组装失败。改成：

```sh
${INSTALL}/$(get_full_firmware_dir)/mali_csffw.bin
${INSTALL}/$(get_full_firmware_dir)/g610/mali_csffw.bin
```

改完必须 `rm -rf $BUILD/install_pkg/libmali-*`，否则旧的真实目录会被再次并进镜像，报错复现。

顺便记一个判断：RK3576/356x 用的 G52 是 Bifrost，固件**内置于 kbase**，deb 里没有 firmware 文件，所以那个包里根本没这段代码。

### 7.2 串口 console（rk-serial-console）

不是「顺带加的」，是硬需求，第 11.3 节会讲原因。包很小：一个 systemd unit + `enable_service`。

```ini
# packages/rk-serial-console/system.d/ttyFIQ0-console.service
[Service]
ExecStart=-/bin/sh -l
Environment=TERM=linux
StandardInput=tty-force
StandardOutput=tty
StandardError=tty
TTYPath=/dev/ttyFIQ0
Restart=always
RestartSec=2
```

`StandardInput=tty-force` 是必须的——`ttyFIQ0` 同时是内核 console，不加 force 打不开。`ExecStart` 前面那个 `-` 表示忽略退出码。

### 7.3 音频初始化（rk-audio-default）

这是后期才加的包，放在**项目级** `projects/Rockchip/packages/`（不是设备级），因为四颗芯片都要用，只是控件名不同。第 11.6 节讲背景。

---

## 8. 一条命令出图：`build-board.sh`

### 8.1 用法

```sh
./projects/Rockchip/tools/build-board.sh                       # 菜单：选芯片 → 选板卡 → 确认
./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2-v2  # 直构
./projects/Rockchip/tools/build-board.sh --list                # 所有 (芯片, 板卡)
./projects/Rockchip/tools/build-board.sh --list-boards RK3568
```

选项：

```
-p/--project <P>   默认 Rockchip
-j/--jobs <N>      默认 nproc
--no-clean         不清理 u-boot 构建树
--no-update        不打包 update.img
--force            磁盘不足也继续
-y/--yes           菜单模式不交互
```

脚本的板卡清单是**从 `uboot_helper` 现取**的，所以加板卡甚至加芯片都不用改这个脚本。

### 8.2 为什么每次都要清 u-boot 构建树

厂商 `make.sh` 不做 `distclean`，同一棵源码树换板只跑 `make <board>_defconfig`，会带着上一块板留下的对象文件，产生很难解释的链接错误。所以默认执行 `./scripts/clean u-boot`（源码包已缓存，不联网）。这就是「换板 7~13 分钟」和「全量 6 小时」的差别来源。

### 8.3 构建成功后做哪些断言

脚本在 `make image` 之后把 img 拆开逐项检查，任一不符就 `rc=2`：

| 断言 | 期望 | 为什么 |
|---|---|---|
| FAT 分区里的 dtb | 只有当前板卡那一个 | 防 dtb 名写错 |
| `extlinux.conf` 的 `FDT` 行 | `/rk<chip>-lubancat-x.dtb` | 防 mkimage 拷错 |
| dtb 的 `model` | 与 `expected_model()` 表逐字一致 | 防 dtb 拿错版本 |
| HDMI 节点 | RK3588 `hdmi@fde80000`+`route-hdmi0`；RK3576 `hdmi@27da0000`+`route-hdmi`；RK356x `hdmi@fe0a0000`+`route-hdmi`+`hdmi-sound` | 防显示路由没开（见 11.1） |
| 32 KiB / 8 MiB 魔数 | `4c445220` / `d00dfeed` | 防引导链错位 |
| sha256 | 打印出来 | 交付时核对 |

`expected_model()` 那张表长这样，加板卡时要同步加一行：

```sh
lubancat-0)    echo "EmbedFire LubanCat-Zero" ;;
lubancat-1)    echo "EmbedFire LubanCat-1" ;;
lubancat-2)    echo "EmbedFire LubanCat-2" ;;
lubancat-2-v2) echo "EmbedFire LubanCat-2" ;;   # 2 系的 v1/v2/v3 model 字符串相同
```

### 8.4 耗时基线（4 核）

| 场景 | 时间 |
|---|---|
| 全新 DEVICE 全量构建（含工具链 + 182 核心） | 约 6h22m，其中 mame 单包约 2h |
| 裁到 3 个核心的冒烟构建 | 约 3.5h |
| 换板（同一 DEVICE，命中全部缓存） | 7~13 分钟 |
| 改内核源码/补丁（删 linux stamp） | 9 分钟内核 + 11 分钟出图 |
| 只改 dtb | 用内核树单编 + `make image`，约 11 分钟 |

重核的体积可以当耗时代理：`mame` 3.9 GB、`ppsspp` 2.7 GB、`citra` 2.1 GB、`scummvm` 1.7 GB、`mame2015` 1.1 GB、`panda3ds` 1.0 GB。

### 8.5 长任务怎么跑

沙箱里 `run_in_background` 的 ssh 读不到 `~/.ssh`，会失败。可行做法是在服务器端起进程，前台用 ssh 轮询：

```sh
ssh dev@10.255.200.141 'cd /home/dev/Lakka-LibreELEC && \
  nohup setsid env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB" \
  ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2-v2 -y \
  < /dev/null > /tmp/rk3568-2v2.log 2>&1 &'
```

`setsid` 是关键——前台 ssh 里带 `&` 可能被 SIGTERM 带走，`setsid` 之后远端进程独立存活。

**判断是否跑完有个坑**：`pgrep -f "build-board.sh RK3568"` 会匹配到自己那条 `bash -c`（因为命令串里就含这个关键字），永远显示「仍在运行」。用字符类打断自匹配：

```sh
pgrep -af "build-boar[d].sh RK3568" || echo "已退出"
```

---

## 9. 打包 update.img 与刷机

### 9.1 为什么对外只发 update.img

这条是踩过才知道的。当时把 `target/*.img.gz` 解压成 `.img`，直接 Write 到 SD 卡，上电**串口一个字都没有**；同一个镜像用 Rockchip 的 `SD_Firmware_Tool` 选「SD启动」写同一张卡，一切正常。

先把镜像本身验了一遍，确认不是镜像坏了：

```
LBA64 (32 KiB) : 4c44 5220 ...          → "LDR "，且与 install_pkg 里的 loader 前 32 KB 逐字节一致
8 MiB          : d00d feed               → uboot.img
16 MiB         : eb58 904d 544f 4f34    → FAT32 boot
MBR p1         : type 0x0c @LBA 0x8000，2048 MiB
MBR p2         : type 0x83 @LBA 0x408000，32 MiB
```

和 update.img 里 `parameter.txt` 的 `0x00400000@0x00008000(boot)` / `-@0x00408000(rootfs)` 完全对得上。目前唯一已知的结构差异是**分区表类型**：我们 MBR，官方工具写 GPT。加上本项目的裸 img 从来没在任何平台验证过启动（RK3588/RK3576 一直走 update.img），所以它属于「未验证路径」。

结论很简单：**img.gz 保留为构建中间产物，交付一律用 update.img**。SD 卡用 `SD_Firmware_Tool`（选「SD启动」），eMMC 用 `RKDevTool`「升级固件」。

### 9.2 `mk-rockchip-update.sh` 做了什么

```sh
./projects/Rockchip/devices/RK3568/tools/mk-rockchip-update.sh --board lubancat-2-v2
```

1. 从 `target/*-<board>.img.gz` 里解出整盘镜像（先 `gzip -dc` 解一次再 `dd`，不要管道直连——`dd count` 提前退出会让 gzip 收到 SIGPIPE，`set -o pipefail` 下脚本以 141 中止）；
2. 解析 MBR，确认 p1 起点 0x8000 且是 FAT32，抽出 `boot.img` / `rootfs.img`；
3. 生成 GPT 风格的 `parameter.txt` 和 `package-file`；
4. `afptool -pack` 造 RKAF，`rkImageMaker -RK<CHIP>` 在外面套 RKFW 头；
5. 校验 RKFW 魔数、loader 尺寸、板卡一致性（用 `uboot_helper` 取该板 dtb，比对镜像里 `extlinux.conf` 的 FDT 行）。

`afptool` / `rkImageMaker` 是仓库内置的（`tools/rkfw/`，静态 x86-64），不依赖 SDK。

**这里修过一个潜伏 bug**：早先 `BUILD_DIR=$(ls -d build.Lakka-*.aarch64 | head -1)`，当 RK3566 和 RK3568 两个构建树并存时，会随机取到**另一个芯片的 loader**，打出来的 update.img 能刷但起不来。改成按 `${DEVICE}` 精确定位 `build.Lakka-<DEVICE>.aarch64`，找不到才回落到通配。

打包后 `build-board.sh` 会自动调用它（`--no-update` 可跳过），不用手动跑。

`afptool -unpack` 不能直接解 `update.img`（那是 RKFW 容器，会报 `check crc failed`），只能解里面的 RKAF 段；要回解先按 RKFW 头剥前导。

### 9.3 刷完一定要断电

RK3576 上遇到过**刷机后首次上电偶发卡死**：内核打印到 7.6 秒的一半停住，没有 panic、没有 oops、没有看门狗，停止点正好在 `mmc_pwrseq_emmc_driver_init` 之后、eMMC 主控（CQHCI/HS400ES）起来之前约 2 ms。断电重启一次就正常，而且之后每次启动都正常。

旁证是两次上电的电气状态确实不同：ATF 一次打 `ext 32k is detected`、一次 `not detected`；u-boot 打 `boot mode: normal` 和 `None`（读 PMU 的 boot-mode 寄存器，`None` 表示未定义值）；DDR 每次重训的 vref/roc 也不同。

结论：RKDevTool 刷完的「复位」不是真正断电，PMIC / DDR PHY / eMMC 保留半初始化状态。**刷完拔电 10 秒再上电**，不要把这种现象当成镜像问题去查。

---

## 10. 上机调试的基本手法

这一节是方法论，比具体结论更值得记。

### 10.1 串口

```
1500000 8N1，节点 /dev/ttyFIQ0
```

vendor u-boot 会改写 `console=`：extlinux 里写 `console=tty1 console=ttyFIQ0`，实际下发给内核的可能是 `console=ttyFIQ0 console=ttyFIQ0`。这是正常行为，不用管。

### 10.2 把日志按阶段切开

一条 600 行的启动日志，先按这几个标志行分段，能立刻判断卡在哪一级：

| 标志行 | 含义 |
|---|---|
| `DDR Version V1.xx` / `change to: 1560MHz(final freq)` | DDR 训练完成，loader 是好的 |
| `U-Boot SPL` / `U-Boot 2017.09` / `Model: EmbedFire LubanCat-x` | SPL 与 U-Boot 起来了 |
| `Found /extlinux/extlinux.conf` / `FDT /rkxxxx.dtb` | extlinux 读到了，dtb 名正确 |
| `Starting kernel ...` | 交棒给内核 |
| `Run /init as init process` | 内核交棒给 initramfs |
| `PARTITION RESIZING IN PROGRESS` | 首次安装流程跑起来了 |
| `Lakka (community): devel-xxxx` | 进用户态了 |

如果最后一条是 `Starting kernel` 后面什么都没有，问题在内核 early init；如果停在 `Run /init` 之后，问题在 initramfs（挂根分区、squashfs）；如果到了用户态但没有 UI，问题在 DRM/GPU/retroarch。

### 10.3 定位「卡住但不报错」

加这两个参数：

```
ignore_loglevel initcall_debug
```

`ignore_loglevel` 压过写死在 `scripts/mkimage` 模板里的 `quiet`；`initcall_debug` 让内核给每个 initcall 打 `calling` / `returned`。**最后一个只有 `calling` 没有 `returned` 的 initcall 就是挂起点**。

RK3576 首次上机就是这么用的：内核日志停在 7.457 秒，加参数后二次开机能看出它卡在 late init、根本没进 userspace（initramfs 的 `progress()` 会往 stderr 打 `### ... ###` 标记，一个都没有）。同一份日志后来还证明那次是「刷机后首启偶发卡死」，断电重启即恢复（见 9.3）。

调试完记得删掉，它会拖慢启动、刷满日志。

### 10.4 查镜像里到底装了什么

**不要用 `ls $BUILD/image/system/usr/lib/libretro/`**。`image/system/{bin,sbin,lib}` 是指向绝对路径的符号链接（`bin -> /usr/bin`），`ls` 会穿透到**宿主机**的同名目录，看到的是 x86_64 的二进制。这个假阳性骗过一次「agetty 存在」的判断。

正确做法：

```sh
unsquashfs -ll target/*.system | grep 'usr/lib/libretro/'
unsquashfs -ll target/*.system | grep -c 'libretro.*\.so$'
```

注意要用**宿主的** `/usr/bin/unsquashfs`，构建树里的 `toolchain/bin/unsquashfs` 是 aarch64 二进制，在宿主上跑会静默无输出——这也是假阳性来源。

### 10.5 查内核里到底有没有某个补丁

看构建树里的源文件和目标文件时间：

```sh
grep -n "补丁里独有的注释文字" build/linux-*/sound/soc/codecs/rk817_codec.c
ls -la --time-style=+%m-%d_%H:%M build/linux-*/sound/soc/codecs/rk817_codec.o
```

`.o` 比 `.patch` 新，说明补丁进的是这版内核。`vmlinux` / `Image` 是压缩过的，`strings` 找不到函数名，别用那个判断。

### 10.6 查 codec 寄存器

镜像里没有 `i2c-tools`，但内核开了 `CONFIG_DEBUG_FS`，可以用 regmap 接口 dump：

```sh
ls /sys/kernel/debug/regmap/                       # 找 0-0020-rk817-codec 这类目录
cat /sys/kernel/debug/regmap/0-0020-rk817-codec/registers
```

**要点是「播放期间」抓**，播放结束后 codec 会进低功耗，寄存器全变回默认值。一行写完，避免换行把命令截断（当时就因为这个抓到了一份空闲态快照，白分析一轮）：

```sh
speaker-test -D plughw:0,0 -c 2 -t sine -l 0 >/dev/null 2>&1 & sleep 2; \
awk '$1 ~ /^(2f|31|32|38|3d|3f|40|41):/' /sys/kernel/debug/regmap/0-0020-rk817-codec/registers; \
pkill speaker-test
```

### 10.7 常见假阳性清单

这些日志看着像故障，其实不是，别浪费时间去查：

| 日志 | 真相 |
|---|---|
| `rockchip-vop2 ... _opp_set_regulators: no regulator (vop) found` / `failed to init opp info` | OPP 表回退，无害，HDMI 正常出图 |
| `dw-mipi-dsi ... failed to find panel: -517` | `EPROBE_DEFER`，随后会 probe 成功 |
| `clk: failed to reparent i2s1_mclkout_tx ... -22` | 无害；`clk_summary` 里 MCLK 是 12.288 MHz |
| `ASoC: Property 'rockchip,audio-routing' does not exist` | 整个 vendor 树所有板都没写，却能出声 |
| `rk-pcie ... LTSSM is 0x3` | 空 M.2 槽，正常 |
| `[drm] failed to init overlay plane Cluster0/1-win1` | 叠加层不可用，primary plane 正常 |
| `speaker-test: -16 Device or resource busy` | RetroArch 占着设备，不是故障 |
| `RKNPU ... can't request region for resource` | 厂商 dts 里 npu 与 iommu 的 reg 重叠，SDK 同名 dtb 一样 |
| u-boot 构建日志里 `grep: .config: No such file` | 包内的无害探测 |

---

## 11. 逐个问题的排查记录（按现象索引）

### 11.1 HDMI 没有输出

**现象**：系统起来了、串口有 shell，但屏幕黑。内核日志里搜不到 `Console: switching` / `[drm] fb0`。

**关键日志**：

```
[drm:vop2_bind] *ERROR* No crtc register, please check dts config
rockchip-drm display-subsystem: failed to bind fdd90000.vop: -19
```

**根因**：厂商板级 dts 把所有显示路由 include 都注释掉了：

```dts
// #include "rk3588-lubancat-5-hdmi0-vp0.dtsi"
// #include "rk3588-lubancat-5-hdmi1-vp0.dtsi"
```

这些 dtsi 才是把 `&hdmi0`、`&hdmi0_in_vp0`、`&route_hdmi0`、`&hdptxphy_hdmi0` 设成 `okay` 的地方。dts 自己只 `okay` 了 vop 和 phy，从不 enable hdmi 控制器 → vop2 注册 0 个 CRTC → DRM bind 失败 → 没有 `/dev/dri/card0`。

**修法**：做一个 vendor 补丁把那一行取消注释。已经在用的三个：

```
rockchip-9000-rk3588-lubancat-5-enable-hdmi0-vp0.patch
rockchip-9001-rk3588-lubancat-5iob-enable-hdmi0-vp0.patch
rockchip-9002-rk3588s-lubancat-4-enable-hdmi0-vp0.patch
```

补丁放 `projects/Rockchip/patches/linux/vendor/`，构建时按文件名顺序 `patch -p1` 应用，所以补丁头必须是 `a/` `b/` 前缀（git 邮件头可有可无）。`5-v2` include 的是 `5.dts`，自动继承 9000，不用单独打。

**别做的事**：不要图省事换成 `rk3588-lubancat-generic.dts`。那个的 `#include` 只有 `rk3588s.dtsi`（RK3588S 基座），对全功能 RK3588 会缺外设。

**RK3576 / RK356x 不需要这个补丁**：它们的板级 dts 里显示路由本来就是 `okay`，所以只需要在 `build-board.sh` 的断言表里按芯片区分节点名（RK3576 是 `hdmi@27da0000`，RK356x 是 `hdmi@fe0a0000`，都不带 `0` 后缀）。

### 11.2 进不了系统（squashfs 缺 zstd）

见 5.1，这里只补排查路径：日志在 7.4 秒停住 → 加 `ignore_loglevel` → 看到 `Filesystem uses "zstd" compression. This is not supported` → 确认 `CONFIG_SQUASHFS_ZSTD` → 改 conf → 删 `linux/build_target` → 重编 25 分钟。

### 11.3 串口能打印但回车没反应

这个问题查了三轮，每一轮都排除掉一个错误假设，值得完整记下来。

**第一轮假设：console 顺序错了。** 内核取最后一个 `console=` 当 `/dev/console`，原来是 `console=ttyFIQ0 console=tty1`，控制台落在 HDMI 上，串口只有 printk 镜像。改成 `console=tty1 console=ttyFIQ0` 之后 `/dev/console` 确实到了串口，但**还是没有 shell**。

**第二轮假设：缺 getty。** 于是加了 `rk-serial-getty` 包，用 `agetty --autologin root`。结果镜像里启动失败：

```
ExecStart=/sbin/agetty ... (code=exited, status=203/EXEC)
ttyFIQ0-getty.service: Unable to locate executable '/sbin/agetty': No such file or directory
restart counter is at 279
```

**真相：镜像里根本没有 agetty。** `packages/sysutils/util-linux/package.mk` 的目标配置是 `--disable-all-programs --enable-{libuuid,libblkid,libmount,...,nologin}`，白名单里没有 `--enable-agetty`。而上一轮「看到 `/sbin/agetty` 存在」是 10.4 里说的符号链接假阳性。

顺带还有一个中间坑：`After=dev-ttyFIQ0.device` / `BindsTo=dev-ttyFIQ0.device` 这两个依赖会让 systemd 永远「等设备」——fiq_debugger 自己注册 tty，udev 不给它打 tag，`dev-ttyFIQ0.device` 永远不 active。日志里能直接看到：

```
systemd[1]: Expecting device dev-ttyFIQ0.device...
```

**最终方案**：不再引入任何新二进制，用 systemd 自己 debug-shell 的同款机制直接在 tty 上起 root shell：

```ini
ExecStart=-/bin/sh -l
StandardInput=tty-force
TTYPath=/dev/ttyFIQ0
Restart=always
```

`/bin/sh` 是 busybox ash，支持 `-l`。**不要写任何 device 依赖**。

### 11.4 `/storage` 没有自动扩容

**现象**：`df -h` 显示 `/storage` 26 MB、100% 使用；首次启动日志里没有 `PARTITION RESIZING IN PROGRESS`。现场日志在 `/flash/fs-resize.log`。

**根因**：`packages/sysutils/busybox/scripts/fs-resize` 把 `/storage` 硬编码成「分区 2」：

```sh
PART=$(grep "/storage " /proc/mounts | cut -d" " -f1 | grep '2$')
```

而 Rockchip 的 update.img 布局是 uboot/boot/rootfs = p1/p2/p3（`/flash` = p2、`/storage` = p3），所以 `PART` 为空 → `DISK` 为空 → 走 `"Partition was not detected - resizing aborted."`。更糟的是第 51 行在检测**之前**就 `rm -f /storage/.please_resize_me`，导致永不重试。

**修法**：从挂载设备名推导分区号，不假设：

```sh
PARTNUM=$(basename "$(grep ' /storage ' /proc/mounts | cut -d' ' -f1)" | sed 's/.*[^0-9]\([0-9][0-9]*\)$/\1/')
[ -n "${PARTNUM}" ] || die ...
parted -s -f -m "${DISK}" resizepart "${PARTNUM}" 100%
```

这个文件是 install 阶段从包目录拷进镜像的，改完重跑 `make image` 就生效，不用重编 busybox。

已经装在机器上、不想重刷时的临时做法：

```sh
parted -s -f -m /dev/mmcblk0 resizepart 3 100%
reboot                      # 让内核重读分区表
resize2fs /dev/mmcblk0p3    # ext4 在线扩容
```

### 11.5 RK356x 首次上机 panic（`panic_on_set_idle`）

**现象**：引导链全过，内核跑到 8.9 秒 panic：

```
rockchip-pm-domain fdd90000.power-management:power-controller:
  failed to get ack on domain 'npu', target_idle = 0, target_ack = 0, val=0x6
Kernel panic - not syncing: panic_on_set_idle set
  rockchip_pmu_set_idle_request → rockchip_pd_power → rockchip_pd_power_on
  → _genpd_power_on → __genpd_dev_pm_attach → platform_probe → rk_iommu_driver_init
```

**根因链**：

1. `rk356x.dtsi` 里 `rknpu_mmu: iommu@fde4b000` 是**独立 iommu 节点**，挂 `RK3568_PD_NPU` 电源域；
2. `rk_iommu_driver_init` 是 **core_initcall**，比所有 I2C / PMIC / regulator 驱动都早，此时给 NPU 域「退出 idle」，ack 位清不掉（`val=0x6` 的 bit2 仍置位）；
3. vendor 的 `drivers/soc/rockchip/pm_domains.c` 在超时后**无条件 panic**（上一行已经 `dev_err` 打印过了）；
4. rk356x 上这种「独立 iommu 节点 + 挂电源域」的节点共有 9 个，分布在 npu / vpu / rga / venc / vdec / vi 这几类外设上，任何一个握手超时都会打死内核。

**先排除的**：厂商预编译的 `rk3566-lubancat-1.dtb` 和我们编的 dtb 在 `npu`/`npu_mmu` 上**逐字段一致**（都是 `okay`），所以不是 dtb 差异；RKFW 的 flash_address 也都对。问题在 vendor 内核这版新增的断言。

**为什么 RK3576 / RK3588 不会踩**：`rockchip_pmu_set_idle_request()` 第一行就是短路：

```c
if (pd_info->req_mask == 0)
        return 0;
```

而三个平台的 NPU 域表项完全不同：

```c
/* RK3568 —— 老式 req/ack 握手（RK3399 那代 PMU） */
DOMAIN_RK3568("npu", BIT(1), BIT(2), false)      // req = ack = BIT(2)，真握手

/* RK3576 / RK3588 —— 新式，req 为 0 */
DOMAIN_RK3576("npu", 0x0, BIT(0), BIT(0), 0, 0x0, 0, 0, ...)
DOMAIN_RK3588("npu", 0x0, BIT(1), BIT(1), 0x0, 0, 0, 0x0, 0, ...)
```

拓扑其实三个平台一样（RK3588 有 `rknpu_mmu: iommu@fdab9000`，RK3576 有 `iommu@27702000`，同样在 core_initcall 被 probe），差异全在域表参数——RK3576/RK3588 走到 NPU 域直接返回成功，panic 那行代码根本不可达。

补充一个细节：RK356x 的 **GPU** 域也有 req 握手，但 GPU 由 Mali 驱动在 module_init 之后上电，那时 PMIC 和时钟就绪了，所以不踩雷。只有「独立 iommu 节点 + core_initcall 阶段上电」的 NPU 是雷点。

**修法**（三个补丁）：

| 补丁 | 作用 |
|---|---|
| `rockchip-9003-soc-pm-domains-idle-timeout-no-panic.patch` | idle 握手超时改为返回错误，保留 `dev_err` 诊断 |
| `rockchip-9004-rk3566-lubancat-disable-rknpu.patch` | 板级 dtsi 关掉 `rknpu` + `rknpu_mmu` |
| `rockchip-9005-rk3568-lubancat-disable-rknpu.patch` | 同上，RK3568 |

9003 是通用保护，9004/9005 是针对性处理（Lakka 不用 NPU）。改完删 `linux/build_target` 重编，实测 9 分钟出内核 + 11 分钟出图。验证方式：反编译新 dtb，`npu@fde40000` 和 `iommu@fde4b000` 都应该是 `disabled`。

### 11.6 喇叭/耳机没声音

这个问题前后换过三块板（lubancat-2-v2、lubancat-3、lubancat-1），涉及两种 codec，排查过程比较长。下面按层次写，因为每一层都单独成立、单独能让人没声音。

**第一层：codec 的输出级默认是关的。**

| codec | 板卡 | 必须打开 | 默认值 |
|---|---|---|---|
| RK809 / RK817 | RK3566 的 0/1/1N，RK3568 的 2 系 | `Playback Path` = `SPK` 或 `SPK_HP` | **OFF** |
| ES8388 / ES8323 | RK3576 的 3/3IO，RK3588 的 4/5 系 | `OUT1 Switch`、`OUT2 Switch` = on | **off** |

判断依据就是 `amixer -c 0 contents` 里的那两行。RK809 是枚举控件 `numid=12`，值是 `Item #0 'OFF'`；ES8388 是 `numid=80/81`，值是 `off`。

**第二层：`amixer sset` 只认 simple controls。** ES8388 的 `OUT1 Switch` 不是 simple control，`sset` 会报 `Unable to find simple control`。要用 numid 或 `cset name=`：

```sh
amixer -c 0 cset numid=80 1
amixer -c 0 cset name='OUT2 Switch' 1
```

**第三层：RK809 的「同值短路」。**

```c
/* rk817_playback_path_put() */
if (rk817->playback_path == ucontrol->value.integer.value[0]) {
        DBG("%s : playback_path is not changed!\n", __func__);
        return 0;      /* 值没变 → 不写任何寄存器 */
}
```

而 DAPM 每次 PCM 打开都会用 `playback_power_up_list` 把输出级写回 class-D off / DACD down。于是形成死锁：设过 `SPK_HP` 之后 `playback_path` 变量仍是 `SPK_HP`，再设同值直接短路，class-D 永远打不开。**表现就是只有第一次播放有声，之后必须 OFF → 再设才恢复**。

现场绕法：

```sh
amixer -c 0 sset 'Playback Path' OFF
amixer -c 0 sset 'Playback Path' SPK_HP
```

**第四层：RetroArch 自己也有静音。** `retroarch.cfg` 里 `audio_volume = "0.000000"`（增益倍数，0 = 静音），和 ALSA 是两套独立开关，排查时别混在一起判断。

**最终方案（做进镜像）**：

1. 新包 `projects/Rockchip/packages/rk-audio-default/`，开机 oneshot 遍历 `/proc/asound/card*`，跳过 HDMI/DP，按 codec 名称设控件，全部 best-effort（认不出的控件就跳过），所以一张镜像服务所有板。
2. 内核补丁 `rockchip-9006-audio-rk817-reapply-playback-path.patch`，在 `rk817_codec_power_up()` 的 playback 分支末尾按当前 `playback_path` 重新上电一次（`pre_path` 传 `playback_path` 避免递归），解决第三层。

补丁生成时踩了个坑：幂等判断写成 `"\t\tif (rk817->playback_path != OFF)" not in text`，但源码 1363 行本来就有同样字符串，导致误判「已插入」，第一版只有 1 个 hunk。改用补丁里独有的一句注释做判据才正确。

**已经装在机器上、不想刷镜像时的临时做法**：

```sh
amixer -c 0 sset 'Playback Path' SPK_HP          # RK809
amixer -c 0 cset name='OUT1 Switch' 1            # ES8388
mkdir -p /storage/.config
alsactl store -f /storage/.config/sound.conf     # 开机由 udev 的 soundconfig 自动 restore
sed -i 's/^audio_volume = .*/audio_volume = "1.000000"/' /storage/.config/retroarch/retroarch.cfg
```

**硬件提醒**：RK809 内置 class-D 是按 8Ω 设计的（约 1W 级），接 4Ω 3W 喇叭属于超规格，会有过流保护/失真风险，建议换 8Ω 2W，或把音量压在 70% 以下。

`lubancat-2-v2` 那块板子换上 `SPK_HP` 后只有电流声、没有音乐，而同 codec 的 lubancat-1 正常——这一条到最后仍按板级问题处理，没有结论，记在这里免得后人重复排查。

### 11.7 MIPI 屏 + 又一次 NPU 电源域事故

给 2-V2 上 10.1 寸 MIPI 屏（800×1280，S8001280B1060B）时，合并的设备树能点亮，但系统卡死。日志有两段关键信息：

```
[9.721] Console: switching to colour frame buffer device 100x80     ← 100×80 字符 = 800×1280
[9.805] [drm] fb0: rockchipdrmfb frame buffer device
[8.928] failed to get ack on domain 'npu', target_idle = 0, ...
[9.684] Internal error: synchronous external abort
        regmap_mmio_read32le → rockchip_pmu_save_qos → rockchip_pd_power
        → rockchip_pd_power_off → _genpd_power_off → genpd_power_off_work_fn
[32.4]  rcu_sched detected expedited stalls on CPUs/tasks: { 1-...D }
```

**屏其实是亮的**（`100x80` 字符就是 800×1280），死的是 CPU1：NPU 域上电失败 → genpd 调度下电 → `rockchip_pmu_save_qos()` 去读一个没通电的域的 QoS 寄存器 → 同步外部中止 → 持锁不返回 → RCU stall。

**为什么这次没 panic 却更糟**：编 dtb 用的是 SDK 的 kernel-6.1 源码（`&rknpu` / `&rknpu_mmu` 还是 `okay`），内核是 Lakka 的（带 9003，所以只 `dev_err` 不 panic）。**内核与 dtb 来自不同源码树**，凑出「不 panic 但事后 abort」的组合。

**教训**：改 dtb 时要么用 Lakka 构建树编（它已经带 9004/9005），要么在 dts 里显式关掉 NPU，不要依赖补丁：

```dts
&rknpu     { status = "disabled"; };
&rknpu_mmu { status = "disabled"; };
```

顺带记两条 MIPI 合并 overlay 的坑：

- 主 dts 已经 include 了 `rk3568-lubancat-dsi.dtsi`，里面**已经定义**了 `dsi0_panel`（带 `status = "disabled"`）、`gt911_dsi0`/`gt928_dsi0`（同一个 `@5d` 地址）。overlay 的 `fragment@N` 不能原样贴，否则 label 重复、panel 下出现两个 `endpoint`、i2c1 上两个 `@5d`。正确做法是按 label 覆写，并且**不重复写 `ports`**。
- 覆写 `&dsi0_panel` 时**必须显式写 `status = "okay"`**：dtsi 里它自带 disabled，而 overlay 是新建节点所以没写 status，漏了就永远不亮。
- 注释里不能出现 `*/` 序列（比如写 `hdmi-in-vp*/hdmi-sound`），会把 C 注释提前闭合，`dtc` 报 `syntax error`。

### 11.8 网络类问题（四种子类型）

这几种现象相似，根因完全不同，判断方法也不一样：

| 现象 | 根因 | 判断 | 处理 |
|---|---|---|---|
| `git.libretro.com` 443 超时，8 次重试全失败 | 该主机整体不可达（DNS 能解析，TCP 80/443/9418 全超时） | 同时刻 github.com 正常 | 换 `PKG_SITE`（`amiarcadia` 的镜像有同一 commit，git SHA 覆盖整棵树，可安全替换） |
| 50% 概率 `gnutls_handshake() failed` / `early EOF` | 代理下 HTTP/2 流被间歇截断 | 手动重跑同一条命令有时成功 | `http.version=HTTP/1.1` + `postbuffer`，`get_git` 加带清理的重试循环 |
| `curl 000`、codeload 也 000 | 到 GitHub 的链路被阻断 | 非 GitHub 站点全正常 | 走 `gh-proxy` 做真正的 git fetch（git 自己校验对象 SHA，内容仍然可信） |
| `Cannot get xxx sources` + `Unable to establish SSL connection`（非 GitHub） | 目标站点 HTTPS 不通，或 HSTS 让 HTTP 降级失效 | 同一 URL 用 HTTP 能下 | wget 包装器降级 HTTP；有 `PKG_SHA256` 兜底，不会静默接受错内容 |

还有两个容易被忽略的：

- **CMake 的 `FetchContent` 是第三类受害者**：`melondsds` 在 configure 阶段拉 11 个 GitHub 依赖。git 全局 `insteadOf` 一条就够，因为它对 `git clone` 及其子进程生效。
- **手工灌 git 缓存漏子模块**：见 2.5。修的时候必须同时 `rm -rf build/<pkg>-* .stamps/<pkg>`，因为 `unpack` 按 stamp 跳过，只换 tarball 不会重新解包，旧的空目录会一直在。

### 11.9 编译期的两类交叉编译事故

**SDL:host 读了 aarch64 的头文件**：

```
sysroot/usr/include/bits/math-vector.h:30:9: error: unknown type name '__Float32x4_t'
```

host 编译行是 `host-gcc -march=native`，却带着 `-I<toolchain>/aarch64-.../sysroot/usr/include`。根因是 `PKG_CONFIGURE_OPTS_HOST="${PKG_CONFIGURE_OPTS_TARGET}"`（上游原样），而 target 选项里有 `--with-alsa-prefix=${SYSROOT_PREFIX}/usr/lib`。修法是 host 变体用 sed 剔掉那两条目标 ABI 路径。

**通用教训**：host 侧构建绝不能继承 target 的 `-I` / `--with-*-prefix`。看到 `unknown type name '__Float32x4_t'` / `__Float64x2_t`，基本就是「用 x86 编译器读了 aarch64 glibc 头」。

**GLES-only 图形栈下的两类写法**：libmali 只提供 GLES，没有桌面 GL，所以核心必须走 GLES 分支。但不同核心的 Makefile 写法不一致，两种都踩过：

- `parallel_n64`：`Makefile.common` 把 GLES 分支**嵌套在 `HAVE_OPENGL=1` 里面**，而我们传 `HAVE_OPENGL=0`，整块被跳过 → 一个 GL 宏都没有 → 落到 `#else #include <GL/gl.h>`。修法是 GLES-only 时也传 `HAVE_OPENGL=1`，并补 `GLES=1`。
- `yabasanshiro`：`Makefile.common` 判断 `FORCE_GLES`，`platform=arm64` 分支没置 1，而 `package.mk` 只把 `${OPENGLES}` 加进依赖、从不传 `FORCE_GLES`。修法是补 `FORCE_GLES=1`。

**同类风险筛查法**：在核心的 `package.mk` 里搜「同时出现 `OPENGLES_SUPPORT` 和 `HAVE_OPENGL=0`」。

---

## 12. 加一块新板（同一颗芯片）

这个操作很便宜，只改两个地方：

1. `scripts/uboot_helper` 里加一条（**保持字母序**）：

```python
'lubancat-5-v2': {
  'dtb': 'rk3588-lubancat-5-v2.dtb',
  'config': 'lubancat-5-rk3588-pcie_defconfig',
  'rockchip_legacy_boot': '1'
},
```

2. `build-board.sh` 的 `expected_model()` 加一行期望的 model 字符串。

然后：

```sh
./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5-v2
```

7~13 分钟出图，因为 u-boot 会重编、内核和包全命中缓存。

`dtb` 字段和 `config` 字段都要跟源码树里的真实文件名核对：

```sh
ls build/linux-*/arch/arm64/boot/dts/rockchip/ | grep -i lubancat
ls build/u-boot-*/configs/ | grep -i lubancat
```

**同一块板的硬件版本差异**（以 lubancat-4 的 v0/v1 为例）：厂商给每版 PCB 一个 dts，`rk3588s-lubancat-4-v1.dts` 与 v0 只差两组引脚——`dsi0_reset`（GPIO0_A31 → GPIO1_A1）和 `tp1_irq`（GPIO3_D20 → GPIO4_A1），其余外设相同。不用 MIPI 屏时一张镜像通用。切换有两种方式：

- **不刷机**：SYSTEM 里带全部 dtb（`/usr/share/bootloader/`），`mount -o remount,rw /flash` 后把目标 dtb 拷进 `/flash/` 并改 `extlinux.conf` 的 `FDT` 行，再 reboot。Windows 上直接改 FAT 分区也一样。
- **每版一张镜像**：在 `uboot_helper` 注册 `lubancat-4-v1`，`build-board.sh` 直接出。

---

## 13. 加一颗新芯片（RK3576 / RK356x 的实际差异）

流程就是复制设备目录 + 改差异点，但差异点必须先查清楚，否则会在构建期或上机时才炸。下面这张表是四颗芯片的实测差异，新加芯片时照着核一遍。

| 项 | RK3588 | RK3576 | RK3566 | RK3568 |
|---|---|---|---|---|
| CPU | 4×A76 + 4×A55 | 4×A72 + 4×A53 | 4×A55 | 4×A55 |
| `TARGET_CPU` | `cortex-a76.cortex-a55` | `cortex-a72.cortex-a53` | `cortex-a55` | `cortex-a55` |
| 内核 defconfig | `lubancat_linux_rk3588_defconfig`（930 行） | `lubancat_linux_rk3576_defconfig` | `lubancat_linux_rk356x_defconfig`（987 行） | 同左 |
| `LOCALVERSION` | `-rk3588` | `-rk3576` | `-rk356x` | `-rk356x` |
| GPU blob | G610 valhall-g24p0 | G52 bifrost-g13p0 | G52 bifrost-g13p0 | G52 bifrost-g13p0 |
| u-boot defconfig | `lubancat-5-rk3588-pcie` 等 | `lubancat-rk3576-msata` | `lubancat-rk3566-msata` | `lubancat-rk3568-pcie` |
| FIT 打包 | 是 | 是 | 是 | 是 |
| TRUST ini | `RK3588TRUST.ini` | `RK3576TRUST.ini` | **回落 `RK3568TRUST.ini`** | `RK3568TRUST.ini` |
| DDR 默认 | 1848 | 1560 | 1056 | 1560 |
| DDR 文件名 | `rk3588_ddr_lp4_*` | `rk3576_ddr_lp4_*` | `rk3566_ddr_*`（无 lp4） | `rk3568_ddr_*`（无 lp4） |
| 显示补丁 | 需要（9000/9001/9002） | 不需要 | 不需要 | 不需要 |
| HDMI 节点 | `hdmi@fde80000` | `hdmi@27da0000` | `hdmi@fe0a0000` | `hdmi@fe0a0000` |
| 路由/声卡名 | `route-hdmi0` / `rockchip-hdmi0` | `route-hdmi` / `rockchip-hdmi` | `route-hdmi` / `hdmi-sound` | 同左 |
| codec | ES8388 | ES8388 | RK809 | RK809 |
| debug UART | 0xFEB50000 | 0x2AD40000（defconfig 自带，fragment 要删 DEBUG_UART） | 0xFE660000（defconfig 自带） | 同左 |

共享文件要改的只有三处：`config/arch.aarch64`（CPU 白名单）、`scripts/uboot_helper`（芯片段）、`projects/Rockchip/bootloader/install`（FIT case 加芯片名）。`build-board.sh` 不用改结构，但要加 `expected_model()` 和 HDMI 断言分支。

**做之前先做预检**，能省掉一整轮白跑：拿 SDK 里的预编译 dtb 反编译出 `model` 字符串，和 `expected_model()` 表逐字对一遍。

```sh
for d in rk3566-lubancat-0 rk3568-lubancat-2; do
  printf "%-24s " "$d"
  dtc -I dtb -O dts /home/dev/LubanCat_SDK/kernel-6.1/extboot/dtb/$d.dtb 2>/dev/null \
    | grep -m1 -o 'model = "[^"]*"'
done
```

**磁盘是硬约束**：一个新 DEVICE 的构建树约 52 GB（裁核后 26 GB）。构建机 `/home` 只有 390 GB，两个全量树并存就会紧张，出正式版前要先清 `target/` 的中间产物（`.tar` / `.system` / `.kernel`）和不再需要的 build 树。

---

## 14. 核心清单与冒烟构建

### 14.1 机制

`packages/lakka/libretro_cores/package.mk` 末尾有一段现成的排除逻辑：

```sh
if [ -n "${EXCLUDE_LIBRETRO_CORES}" ]; then
  for core in ${EXCLUDE_LIBRETRO_CORES}; do
    LIBRETRO_CORES="${LIBRETRO_CORES// ${core} /}"
  done
fi
PKG_DEPENDS_TARGET="${LIBRETRO_CORES}"
```

所以不需要改共享文件，只要在设备 `options` 里写 `EXCLUDE_LIBRETRO_CORES`。配合前面说的 `${EXCLUDE_LIBRETRO_CORES:-}` 前缀，命令行也能临时追加。

**坑**：这是按包名做字符串替换，**写错名字会静默忽略**（`atari7800` 无效，Atari 7800 的包名其实是 `prosystem`）。改完一定要重新生成构建计划并 diff：

```sh
env PROJECT=Rockchip DEVICE=RK3568 ARCH=aarch64 bash -c \
  '. config/options ""; set -o pipefail; ./scripts/pkgjson | ./scripts/genbuildplan.py --show-wants --build image' \
  > /tmp/plan-new.txt
diff /tmp/plan-old.txt /tmp/plan-new.txt
```

### 14.2 实际数字

| 项 | 数量 |
|---|---|
| 上游核心全集 `LIBRETRO_CORES` | 182 |
| 设备 `options` 排除 | 84 |
| Rockchip 项目追加排除 | 1（`lr_moonlight`） |
| 正式镜像实际安装的 `*.so` | **93**（`unsquashfs -ll target/*.system \| grep -c 'libretro.*\.so$'`） |

四个芯片共用同一份清单。93 这个数是 2026-10 实测的，比早先按清单估算的「约 97」小，因为有些核心名虽然留在清单里但没产出 `.so`。

### 14.3 冒烟构建

移植新芯片时没必要一上来就编 182 个核心，先只留三个轻量的，验证引导链和显示：

```sh
EXCLUDE_LIBRETRO_CORES="$(./projects/Rockchip/tools/cores-subset.sh 'snes9x gambatte genesis_plus_gx')" \
  ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-1
```

`cores-subset.sh` 输出「除保留名单外的全部核心」，所以任务数从 266 降到 230，全量从 6 小时降到 3.5 小时。

想只砍最重的几个也行：

```sh
EXCLUDE_LIBRETRO_CORES="mame mame2015 mame2010 ppsspp citra scummvm panda3ds flycast" \
  ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2
```

**注意**：冒烟镜像不要当正式版发出去；去掉变量重跑 `make image` 会增量补回核心（不用重编已有的）。

---

## 15. 设备树定制

### 15.1 三个入口

| 入口 | 位置 | 适合 |
|---|---|---|
| 正式补丁 | `projects/Rockchip/patches/linux/vendor/rockchip-9xxx-*.patch` | 要提交、要长期维护 |
| 内核配置 | `devices/<DEVICE>/linux/lubancat-6.1/linux.aarch64.conf` | 只涉及 `CONFIG_*` |
| 临时改 | `build.Lakka-*/.aarch64/build/linux-*/arch/arm64/boot/dts/rockchip/` | 会随 `clean linux` 消失 |

补丁自动应用，日志里能确认：

```sh
grep -n "9006\|patching file" /tmp/lakka-build-lubancat-2.log
```

### 15.2 十分钟一轮的 dtb 热替换

MIPI 屏参数基本靠试，一轮等 40 分钟重编内核太慢。板子上直接换 dtb：

```sh
# 板子上，用串口 shell
dtc -I dtb -O dts -o /tmp/b.dts /flash/rk3566-lubancat-0.dtb
vi /tmp/b.dts
dtc -I dts -O dtb -o /flash/rk3566-lubancat-0.dtb /tmp/b.dts
sync && reboot
```

或者同名覆盖编好的 dtb：

```sh
cp rk3568-lubancat-2-v2.dtb /flash/     # 同名，extlinux.conf 的 FDT 行不用改
```

`/flash` 就是 boot 分区（FAT），默认只读，要先 `mount -o remount,rw /flash`。注意 `extlinux.conf` 是构建时生成的，下次 `make image` 会覆盖，所以这段只适合试参数。

### 15.3 dtbo 不能直接用

- **u-boot 不支持**：vendor 2017.09 全树 grep `fdtoverlays` 零命中，extlinux 里写这行会被静默忽略；只有交互式 `fdt apply`，无法在自动启动里用。
- **内核侧也不 apply**：`CONFIG_OF_OVERLAY=y` 确实开着，但 Lakka 的 initramfs 没有 apply 机制。

所以 `.dtbo` 必须转成文本 dtsi 片段（去掉 `/plugin/`、`fragment@N` 包装，改成 `&node { ... }` 形式）被主 dts include。厂商给的如果本来就是 `.dtsi`，直接 include 就行。

### 15.4 合并 overlay 的正确做法

见 11.7 的三条坑。核心原则：**按 label 覆写，不新建节点**。

- `&route_dsi0 { status="okay"; connect=<&vp1_out_dsi0>; }`
- `&dsi0 { status="okay"; ... }` + `&dsi0_panel { status="okay"; 全部 panel 参数 }`，**不写 `ports`**（沿用 dtsi 已有的端口配对）
- `&gt928_dsi0 { status="okay"; ... }`，同一地址的 `gt911_dsi0` 保持 disabled
- 关掉原来占 vp0 的 HDMI：`route_hdmi` / `hdmi_in_vp0` / `hdmi_in_vp1` / `hdmi` / `hdmi_sound` 全 disabled

编译验证可以用内核树，不需要出整张镜像：

```sh
K=build.Lakka-RK3568.aarch64/build/linux-1bc19c52...
cd $K
cpp -nostdinc -I$K/arch/arm64/boot/dts/rockchip -I$K/arch/arm64/boot/dts \
    -I$K/include -I$K/scripts/dtc/include-prefixes -undef -D__DTS__ \
    -x assembler-with-cpp my.dts -o /tmp/my.pre
dtc -I dts -O dtb -o /tmp/my.dtb /tmp/my.pre
dtc -I dtb -O dts /tmp/my.dtb | grep -A4 "dsi@fe060000"
```

---

## 16. 提交与发布

### 16.1 提交粒度

按主题拆，一个 commit 只做一件事。实际用的粒度（RK356x 那一批）：芯片支持 / 内核补丁 / 工具修复 / 构建脚本 / 新工具 / 配置开关 / 文档，一共 7 个。这样 `git log` 能当变更说明看，回滚也精确。

作者信息统一：

```sh
git config user.name  "xxx"
git config user.email "xxx"
```

### 16.2 分支与 tag

- 分支 `lubancat`（原来叫 `rk3588-port`，覆盖 RK3576 之后改名）。
- tag 用 annotated，说明里写清覆盖范围、验证状态、已知问题：

```sh
git tag -a lubancat-v0.2 -m "LubanCat bring-up v0.2 ..."
git push fork lubancat
git push fork lubancat-v0.2
```

命名上前一个 tag 是 `lubancat-rk3588-v0.1`，覆盖四颗芯片之后去掉了芯片前缀。tag 说明里要**如实写未验证项**（比如「2-V2 音频仍在排查」），否则后来的人会以为全绿。

### 16.3 推不上去的两种情况

1. `origin` 是 gh-proxy 的只读镜像，push 报 `No anonymous write access`。要用 `fork`。
2. 想删旧分支时报 `refusing to delete the current branch` —— 那是 fork 的默认分支，GitHub 不允许删。只能先在网页 Settings → General → Default branch 切到新分支，再删。

构建机上没有 PAT、没有 `gh` CLI，涉及 API 的操作只能人工点网页。

---

## 17. 附录

### 17.1 关键文件清单（以 RK3566 为例，其它芯片同构）

```
projects/Rockchip/
├── options                                    # 项目级：SSH_ENABLED_DEFAULT、SQUASHFS_COMPRESSION 等
├── bootloader/install                         # 引导链装配（case 里要列新芯片）
├── patches/linux/vendor/rockchip-900x-*.patch # 内核补丁，按编号顺序应用
├── packages/rk-audio-default/                 # 项目级包：开机打开 codec 输出级
├── tools/build-board.sh                       # 构建入口
├── tools/cores-subset.sh                      # 冒烟构建的核心裁剪工具
├── tools/setup-cn-network.sh                  # 国内网络三件套
└── devices/RK3566/
    ├── options
    ├── bootloader/config
    ├── linux/lubancat-6.1/linux.aarch64.conf
    ├── packages/{u-boot,rkbin,libmali,rk-serial-console}/package.mk
    ├── tools/{mk-rockchip-update.sh,rkfw/}
    └── README.md / BUILD_GUIDE.md / CORES.md
```

仓库外还要改两处共享文件：`config/arch.aarch64`（CPU 白名单）、`scripts/uboot_helper`（板卡表）。

### 17.2 命令速查

```sh
# 构建
env PATH="$HOME/bin:$PATH" PERL5LIB="$HOME/perl5:$PERL5LIB" \
  ./projects/Rockchip/tools/build-board.sh RK3568 lubancat-2-v2 -y

# 只列板卡
./projects/Rockchip/tools/build-board.sh --list-boards RK3568

# 查板卡的 dtb / defconfig
./scripts/uboot_helper Rockchip RK3568 lubancat-2-v2 dtb

# 冒烟构建（只留 3 个核心）
EXCLUDE_LIBRETRO_CORES="$(./projects/Rockchip/tools/cores-subset.sh 'snes9x gambatte genesis_plus_gx')" \
  ./projects/Rockchip/tools/build-board.sh RK3566 lubancat-1

# 实验 DDR 频点
DDR_FREQ=2112 ./projects/Rockchip/tools/build-board.sh RK3588 lubancat-5

# 单独重打 update.img
./projects/Rockchip/devices/RK3568/tools/mk-rockchip-update.sh --board lubancat-2-v2

# 只重编内核（改了内核源码/补丁之后）
rm -f build.Lakka-RK3568.aarch64/.stamps/linux/build_target

# 查镜像真实内容（必须用宿主的 unsquashfs）
unsquashfs -ll target/*.system | grep 'usr/lib/libretro/'

# 校验引导布局
dd if=target/xxx.img bs=1 skip=32768   count=4 status=none | xxd -p   # 4c445220
dd if=target/xxx.img bs=1 skip=8388608 count=4 status=none | xxd -p   # d00dfeed

# 板子上
cat /proc/cmdline
cat /sys/kernel/debug/regmap/0-0020-rk817-codec/registers
cat /sys/kernel/debug/clk/clk_summary | grep -i i2s
df -h /storage ; cat /flash/fs-resize.log
```

### 17.3 还没解决的问题

- **lubancat-2-v2 音频**：`Playback Path = SPK_HP` 之后只有电流声，同 codec 的 lubancat-1 正常。按板级问题处理，未定位。
- **裸 img 能否启动**：MBR 镜像直接写卡上电无输出，GPT/update.img 正常。结构差异只在分区表类型，但没有定论；实践上只交付 update.img。
- **刷机后首启偶发卡死**：RK3576 上确认过，断电 10 秒可恢复，未在驱动层定位。
- **MIPI 屏没有注册成独立板卡**：目前靠替换 dtb 或 include dtsi，没有做成 `lubancat-2-v2-mipi` 这样的板卡项。要做的话在 `uboot_helper` 加一条 + `expected_model` 加一行即可。

### 17.4 一句话总结

这套移植之所以能覆盖四颗芯片，靠的是三件事：一是把「芯片 = DEVICE 目录、板卡 = uboot_helper 一条记录」这个模型吃透，二是坚持 vendor 链（u-boot FIT + BSP 内核 + rkbin + libmali）不换栈，三是每一步都用字节级的证据（魔数、sha256、反编译 dtb、寄存器 dump）代替「看起来应该没问题」的判断。
