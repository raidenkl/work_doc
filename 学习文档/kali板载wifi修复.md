# RK3588 LubanCat 板载 WiFi 修复指南

> 适用环境：Kali Linux rootfs + LubanCat 系列 RK3588 开发板
> WiFi 芯片：RTL8822CE（PCIe）
> 内核版本：6.1.99-rk3588

---

## 问题诊断

在板子上执行以下命令诊断 WiFi 状态：

```bash
# 1. 检查 WiFi 硬件是否被识别
lspci | grep -i network

# 2. 检查内核模块是否存在
ls /lib/modules/$(uname -r)/kernel/drivers/net/wireless/realtek/rtw88/ 2>/dev/null || echo "模块目录不存在"

# 3. 尝试加载驱动
sudo modprobe rtw88_pci 2>&1
sudo modprobe rtw88_8822ce 2>&1

# 4. 检查加载结果
lsmod | grep rtw

# 5. 检查 WiFi 接口
ip link show | grep wlan
```

### 典型问题现象

| 现象 | 原因 |
|------|------|
| `lspci` 能看到 RTL8822CE，但 `ip link` 没有 `wlan0` | 内核模块（.ko 文件）未安装 |
| `modprobe: FATAL: Module rtw88_pci not found` | `/lib/modules/` 目录缺失 |
| `Possible missing firmware /lib/firmware/regulatory.db` | `wireless-regdb` 包未安装 |
| `wlan0` 存在但无法扫描/连接 | 驱动未正确加载或固件缺失 |

### 根本原因

构建流程使用了简化的方式：

```
build-rootfs.sh  →  mkimg.sh
```

跳过了 `build-kernel.sh` 和 `config-image.sh`，导致内核 .deb 包未安装，**所有内核模块（.ko 文件）均缺失**。

---

## 修复步骤

### 步骤 1：准备内核 deb 包

将内核 deb 包复制到板子上（在 **宿主机** 上执行）：

```bash
# 如果 deb 包在宿主机上，SCP 到板子
scp linux-image-6.1.99-rk3588_6.1.99-rk3588-11_arm64.deb cat@192.168.103.145:~
```

> ⚠️ 如果 `mkimg.sh` 创建的镜像没有独立的 FAT 启动分区，内核 deb 的 postinst 脚本会因 `zz-update-firmware` hook 挂载失败而报错。需要先临时移走该 hook。

### 步骤 2：在板子上安装内核模块

以下命令在 **板子** 上执行（`cat` 用户的密码为 `temppwd`）：

```bash
# 2.1 释放 /boot 空间（如果空间不足）
sudo rm -f /boot/initrd-6.1

# 2.2 临时移走导致报错的 hook
sudo mv /etc/initramfs/post-update.d/zz-update-firmware \
       /etc/initramfs/post-update.d/zz-update-firmware.bak

# 2.3 安装内核 deb
sudo dpkg -i ~/linux-image-6.1.99-rk3588_6.1.99-rk3588-11_arm64.deb

# 2.4 恢复 hook
sudo mv /etc/initramfs/post-update.d/zz-update-firmware.bak \
       /etc/initramfs/post-update.d/zz-update-firmware
```

### 步骤 3：加载 WiFi 驱动

```bash
# 3.1 加载模块
sudo modprobe rtw88_pci
sudo modprobe rtw88_8822ce

# 3.2 验证加载
lsmod | grep rtw
# 应看到：
# rtw88_8822ce
# rtw88_8822c
# rtw88_pci
# rtw88_core

# 3.3 检查 WiFi 接口
ip link show wlan0
# 应看到：wlan0: <NO-CARRIER,BROADCAST,MULTICAST,UP>
```

### 步骤 4：修复 regulatory.db（可选）

`regulatory.db` 缺失会导致 `update-initramfs` 产生警告，但不影响 WiFi 基本功能。如需修复：

```bash
# 方式一：从无线 regulatory 数据库提取
# regulatory.db 包含在 wireless-regdb 包中
sudo apt-get install -y wireless-regdb

# 如果 apt 报错，尝试先修复 dpkg
sudo dpkg --configure -a
sudo apt-get install -y --fix-broken
sudo apt-get install -y wireless-regdb

# 方式二：手动创建空数据库（最小化方案）
# 注意：这会让 WiFi 在所有信道上工作，可能不符合当地法规
# 不建议在生产环境使用
```

如果 `wireless-regdb` 因为 dpkg 基础问题无法安装，不影响 WiFi 连接功能，只是国家码信息缺失。

### 步骤 5：连接 WiFi

```bash
# 5.1 开启 wlan0
sudo ip link set wlan0 up

# 5.2 扫描可用网络
sudo iw dev wlan0 scan | grep "SSID:"

# 5.3 使用 NetworkManager 连接
nmcli dev wifi connect "你的WiFi名称" password "你的WiFi密码"

# 5.4 验证连接
ip addr show wlan0
ping -c 4 8.8.8.8
```

---

## 让模块开机自动加载

模块加载后，确保下次开机自动加载：

```bash
# 方式一：通过配置文件
echo "rtw88_pci" | sudo tee -a /etc/modules
echo "rtw88_8822ce" | sudo tee -a /etc/modules

# 方式二：通过 modprobe.d
echo "rtw88_pci" | sudo tee /etc/modules-load.d/rtw88.conf
echo "rtw88_8822ce" | sudo tee -a /etc/modules-load.d/rtw88.conf

# 更新 initramfs 使配置生效
sudo update-initramfs -u
```

---

## 长期修复（修改构建脚本）

如果希望**重新构建 rootfs 时内核模块自动包含在内**，需要修改 `kali-rootfs/scripts/build-rootfs.sh`：

在 `#add wifi firmware` 段落之后，增加内核模块复制逻辑（需要先将编译好的内核 .deb 放入 `packages/arm64/` 目录）：

```bash
# 在 build-rootfs.sh 中 # Install arm64 deb package 段落添加
# 将内核 deb 包复制到 chroot 并安装
cp ../packages/arm64/linux-image-*.deb ${chroot_dir}/tmp/
chroot ${chroot_dir} /bin/bash -c "dpkg -i /tmp/linux-image-*.deb && rm -rf /tmp/*"
chroot ${chroot_dir} /bin/bash -c "depmod -a"
```

或者使用完整的构建流程：

```
build-kernel.sh  →  编译内核 → 生成 linux-image-*.deb
       ↓
build-rootfs.sh  →  创建基础 rootfs（含 overlay + firmware）
       ↓
config-image.sh  →  安装内核 .deb → update-initramfs → depmod
       ↓
build-image.sh   →  创建 GPT 磁盘映像
```

---

## 参考信息

- 板卡型号：LubanCat 5（rk3588-lubancat-5.dtb）
- 内核版本：6.1.99-rk3588
- WiFi 芯片：Realtek RTL8822CE (PCIe)
- 驱动：`rtw88_8822ce`（由 `rtw88_pci` + `rtw88_core` + `rtw88_8822c` 组成）

---

## 附录：内核更新时 `zz-update-firmware` 报错修复

### 问题现象

安装内核 deb 包时 postinst 脚本报错：

```
mount: /boot/firmware: wrong fs type, bad option, bad superblock on /dev/mmcblk0p1
run-parts: /etc/initramfs/post-update.d//zz-update-firmware exited with return code 32
dpkg: error processing package linux-image-6.1.99-rk3588 (--install):
 old linux-image-6.1.99-rk3588 package postinst maintainer script subprocess failed with exit status 32
```

### 原因

`/etc/initramfs/post-update.d/zz-update-firmware` 脚本的作用是在内核更新后，将新内核、initrd 和设备树复制到启动分区。但它的逻辑**硬编码了 `p1` 作为 FAT 启动分区**，尝试挂载 `/dev/mmcblk0p1` 到 `/boot/firmware/`。

在不同分区布局下会出错：

| 分区 | 标准布局（build-image.sh） | 本板实际布局 |
|------|---------------------------|-------------|
| `p1` | FAT32 启动分区 (512MB) ✅ | **U-Boot 分区 (8MB)** ❌ |
| `p2` | ext4 根分区 | `/boot` (128MB) |
| `p3` | — | `/` 根分区 (29GB) |

### 修复方式（已修改 overlay 脚本）

`overlay/etc/initramfs/post-update.d/zz-update-firmware` 已修改为智能检测逻辑

