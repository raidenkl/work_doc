# LubanCat SDK rootfs 中 `/lib/modules` 的来源分析

> 分析对象：本仓库（LubanCat_SDK，RK3576 / Ubuntu 22.04 / kernel 6.1）
> 结论：rootfs 里的内核模块**不是**通过 SDK 常见的 post-rootfs 钩子（`91-modules.sh` → `mk-kernel.sh modules`）装进去的，
> 而是**内核 .deb 包在 ubuntu rootfs 构建脚本的 chroot 里被 `apt` 安装**进来的。

---

## 0. 一次构建的总体流程（build.sh 全览）

`build.sh` 通过"钩子（hook）"机制分阶段执行，相关脚本：

| 阶段 | 脚本 | 作用 |
| --- | --- | --- |
| pre-build / build | `common/build-hooks/10-kernel.sh` | 编译内核、打包 kerneldeb、生成 extboot |
| build | `common/build-hooks/30-rootfs.sh` | 构建 rootfs（buildroot / debian / ubuntu / yocto） |
| post-rootfs | `common/post-hooks/91-modules.sh` | 可选安装/裁剪内核模块 |
| post-build | `common/build-hooks/80-firmware.sh` / `90-updateimg.sh` | 打包固件 |

本次配置（`output/.config`）：

```
RK_ROOTFS_SYSTEM="ubuntu"      # Ubuntu rootfs
RK_KERNEL_EXTBOOT=y            # extboot 模式 → 会构建 kerneldeb
RK_KERNEL_VERSION="6.1"        # 内核 6.1，实际 release 6.1.99-rk3576
# RK_ROOTFS_INSTALL_MODULES is not set   ← 关键：post-rootfs 不装模块
RK_ROOTFS_STRIP_MODULES=y      # 只做 strip
```

---

## 1. 模块的"源头"：内核 .deb 包

SDK 用 `bindeb-pkg` 把内核打包成 Debian 包：

`common/build-hooks/10-kernel.sh`（`do_build_kerneldeb`，第 45-50 行）：

```bash
do_build_kerneldeb()
{
    rm -f linux-*.buildinfo linux-*.changes
    rm -f linux-headers-*.deb linux-image-*.deb linux-libc-dev*.deb
    run_command $KMAKE KDEB_COMPRESS=xz bindeb-pkg
}
```

因为 `RK_KERNEL_EXTBOOT=y`，走 `do_build_extboot()` 分支（第 160-165 行），并且**把生成的 .deb 拷进 extboot 目录**（第 108-111 行）：

```bash
if [ $RK_ROOTFS_SYSTEM == "ubuntu" ] || [ $RK_ROOTFS_SYSTEM == "debian" ]; then
    cp ${RK_SDK_DIR}/linux-headers-"$KERNEL_VER"_"$KERNEL_VER"-*.deb $EXTBOOT_DIR/kerneldeb
    cp ${RK_SDK_DIR}/linux-image-"$KERNEL_VER"_"$KERNEL_VER"-*.deb $EXTBOOT_DIR/kerneldeb
fi
```

产物（SDK 根目录）：

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb` | 15.6 MB | **包含 254 个 .ko 模块** |
| `linux-headers-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb` | 10.6 MB | 只含 `/usr/src/linux-headers-*` 头文件 |
| `linux-image-6.1.99-rk3576-dbg_..._arm64.deb` | 55 MB | 调试符号包 |

验证 `linux-image` deb 内容：

```bash
dpkg-deb -c linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb | grep -c "\.ko"   # → 254
dpkg-deb -c linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb | head

# 输出示例：
./lib/modules/6.1.99-rk3576/kernel/drivers/bluetooth/aic_btusb.ko
./lib/modules/6.1.99-rk3576/kernel/drivers/ebf_module/dht11/dht11.ko
./lib/modules/6.1.99-rk3576/kernel/drivers/ebf_module/ds18b20/ds18b20.ko
...
```

**结论：`/lib/modules/6.1.99-rk3576/` 下的所有 .ko 都来自 `linux-image` 这个 deb 包。**

---

## 2. 模块怎么进 rootfs：chroot 里 apt 安装 .deb

Rootfs 构建脚本是 `ubuntu22.04/mk-ubuntu-rootfs.sh`（由 `build_ubuntu()` → `mk-ubuntu-rootfs.sh` 调用）。

### 2.1 把 deb 拷贝进 staging 目录

`ubuntu22.04/mk-ubuntu-rootfs.sh` 第 151-157 行：

```bash
#linux kernel deb
if [ -e ../linux-headers* ]; then
    Image_Deb=$(basename ../linux-headers*)
    sudo mkdir -p $TARGET_ROOTFS_DIR/boot/kerneldeb
    sudo touch $TARGET_ROOTFS_DIR/boot/build-host
    sudo cp -vrpf ../${Image_Deb} $TARGET_ROOTFS_DIR/boot/kerneldeb
    sudo cp -vrpf ../${Image_Deb/headers/image} $TARGET_ROOTFS_DIR/boot/kerneldeb
fi
```

构建日志（`output/log/latest/build.log`）印证：

```
11649: '../linux-headers-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb' -> 'binary/boot/kerneldeb/linux-headers-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb'
11650: '../linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb' -> 'binary/boot/kerneldeb/linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb'
```

### 2.2 在 chroot 里 `apt install` 内核包

`ubuntu22.04/mk-ubuntu-rootfs.sh` 第 232 行：

```bash
\${APT_INSTALL} /boot/kerneldeb/* || true
```

日志（`output/log/latest/build.log` 第 11996-12040 行附近）印证：

```
root@localhost:/# ${APT_INSTALL} /boot/kerneldeb/* || true
The following NEW packages will be installed:
  linux-headers-6.1.99-rk3576 linux-image-6.1.99-rk3576
Get:1 /boot/kerneldeb/linux-headers-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb linux-headers-6.1.99-rk3576 arm64 6.1.99-rk3576-11 [10.6 MB]
Get:2 /boot/kerneldeb/linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb linux-image-6.1.99-rk3576 arm64 6.1.99-rk3576-11 [15.6 MB]
...
Unpacking linux-headers-6.1.99-rk3576 (6.1.99-rk3576-11) ...
Unpacking linux-image-6.1.99-rk3576 (6.1.99-rk3576-11) ...
Setting up linux-headers-6.1.99-rk3576 (6.1.99-rk3576-11) ...
Setting up linux-image-6.1.99-rk3576 (6.1.99-rk3576-11) ...
update-initramfs: Generating /boot/initrd.img-6.1.99-rk3576   ← deb 的 postinst 生成 initrd
Install kernel package
```

> 注：`linux-image` 包的 postinst 会调用 `update-initramfs`，用**模块**（`/lib/modules/6.1.99-rk3576`）生成 `/boot/initrd.img-6.1.99-rk3576`，所以 modules 目录是 initrd 生成的前提。

### 2.3 安装后清理 `/boot`（但保留 `/lib/modules`）

`ubuntu22.04/mk-ubuntu-rootfs.sh` 第 345 行：

```bash
rm -rf /boot/*        # 清掉 boot 下的 deb、initrd、Image，模块目录不受影响
rm -rf /packages/
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/
```

### 2.4 打包成 ext4 镜像

`ubuntu22.04/mk-image.sh`：

```bash
sudo mkfs.ext4 -d ${TARGET_ROOTFS_DIR} ${ROOTFSIMAGE} ${IMAGE_SIZE_MB}M
```

日志印证：

```
13185: Rootfs Image: ubuntu-rk3576-gnome-rootfs.img
```

---

## 3. 为什么不是 post-rootfs 的 `mk-kernel.sh modules` 路径？

SDK 里确实另有一条"标准"装模块的路径，`common/post-hooks/91-modules.sh`：

```bash
#!/bin/bash -e
source "${RK_POST_HELPER:-$(dirname "$(realpath "$0")")/post-helper}"

if [ "$RK_ROOTFS_INSTALL_MODULES" ]; then
    message "Installing kernel modules..."
    "$RK_SCRIPTS_DIR/mk-kernel.sh" modules "$TARGET_DIR/"
fi

if [ "$RK_ROOTFS_STRIP_MODULES" ]; then
    message "Strip kernel modules..."
    source "$RK_SCRIPTS_DIR/kernel-helper"
    find "$TARGET_DIR" -name "*.ko" \
        -exec ${RK_KERNEL_TOOLCHAIN}strip --strip-unneeded -v {} \;
fi
```

它只在这两种情况下生效：

| 配置项 | 作用 |
| --- | --- |
| `RK_ROOTFS_INSTALL_MODULES` 打开 | 跑 `mk-kernel.sh modules` → `make modules_install INSTALL_MOD_PATH=<TARGET_DIR>`（见 `10-kernel.sh:146-152`） |
| `RK_ROOTFS_STRIP_MODULES` 打开 | 对 target 下所有 `.ko` 做 `strip --strip-unneeded` |

而本次构建 `output/.config`：

```
# RK_ROOTFS_INSTALL_MODULES is not set     ← 不装模块
RK_ROOTFS_STRIP_MODULES=y                  ← 只 strip
```

所以这次构建：
- **没有走 `mk-kernel.sh modules` 装模块**（`RK_ROOTFS_INSTALL_MODULES` 关闭），日志里也没有任何 `mk-kernel.sh modules` / `modules_install` 调用；
- post-rootfs 钩子的作用仅是** strip**（`RK_ROOTFS_STRIP_MODULES=y`）。

---

## 4. 证据汇总

| 证据 | 位置 |
| --- | --- |
| 254 个 .ko 在 deb 里 | `dpkg-deb -c linux-image-...deb` |
| deb 拷入 `binary/boot/kerneldeb` | `mk-ubuntu-rootfs.sh:151-157` + log 11649/11650 |
| chroot 里 apt 安装两个内核包 | `mk-ubuntu-rootfs.sh:232` + log 11996-12040 |
| `binary/lib/modules/6.1.99-rk3576` 与 deb 一致 | `find binary/lib/modules -name "*.ko" | wc -l` → 254 |
| post-rootfs 装模块被关闭 | `output/.config`：`# RK_ROOTFS_INSTALL_MODULES is not set` |
| post-rootfs 只做 strip | `common/post-hooks/91-modules.sh:11-18` |

---

## 5. 复现/验证方法

```bash
# 1) 看 deb 内模块
dpkg-deb -c linux-image-6.1.99-rk3576_6.1.99-rk3576-11_arm64.deb | grep "\.ko" | head

# 2) 看构建 staging 里的模块（与 deb 一致）
find ubuntu22.04/binary/lib/modules -name "*.ko" | wc -l    # 254

# 3) 看配置
grep -E "INSTALL_MODULES|STRIP_MODULES" output/.config

# 4) 看日志
grep -n "kerneldeb\|linux-image-\|modules" output/log/latest/build.log | head
```

---

## 6. 知识点：两条"模块进 rootfs"的通道

### 通道 A（本次走的路）：linux-image deb + apt

```
kernel make bindeb-pkg
        │ 生成 linux-image-*.deb（含 /lib/modules/<ver>/... 254 个 .ko）
        ▼
ubuntu mk-ubuntu-rootfs.sh: 拷 deb 到 binary/boot/kerneldeb
        │
        ▼
chroot 内 apt install /boot/kerneldeb/*.deb
        │ 解包到 /lib/modules/<ver>；postinst 调 update-initramfs 生成 initrd
        ▼
rm -rf /boot/*（模块保留）
        ▼
mkfs.ext4 -d binary → rootfs.img
```

### 通道 B（SDK 通用路径，本次关闭）：post-rootfs 钩子

```
make modules && make modules_install INSTALL_MOD_PATH=<target>
        ▼
build.sh post-rootfs <target> → post-hooks/91-modules.sh
        │ RK_ROOTFS_INSTALL_MODULES=y 时安装
        │ RK_ROOTFS_STRIP_MODULES=y 时 strip
```

> 通道 B 对 buildroot / debian / yocto rootfs 更常用；对 ubuntu rootfs，本项目作者选择了在 chroot 里直接装 deb 的方式（同时顺带生成 initrd 和保留 headers 源码树）。

---

## 7. 附：相关文件速查表

| 文件 | 作用 |
| --- | --- |
| `common/build-hooks/10-kernel.sh` | 编译内核 / 打包 kerneldeb / 生成 extboot |
| `common/build-hooks/30-rootfs.sh` | rootfs 构建入口（`build_ubuntu()` 等） |
| `ubuntu22.04/mk-ubuntu-rootfs.sh` | Ubuntu rootfs 具体构建（含装内核 deb） |
| `ubuntu22.04/mk-image.sh` | 把 `binary/` 打成 rootfs.ext4 |
| `common/post-hooks/91-modules.sh` | 可选的 post-rootfs 模块安装/strip |
| `common/scripts/kernel-helper` | 定义 `KMAKE` 和内核工具链 |
| `output/.config` | 本次构建实际配置（`RK_ROOTFS_INSTALL_MODULES` 等） |