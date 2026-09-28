# U-Boot 设备树加载机制分析与启动介质优先级修改指南

> 基于 LubanCat RK3576 SDK（`u-boot/` 目录，Rockchip v2017 next 分支）源码级分析，所有结论均标注源码位置。
> 关联文档：`uboot-tftpboot-guide.md`（网络引导移植实操）。

---

## 1. U-Boot 是怎么加载自己的设备树，以及引导内核设备树的

### 1.1 总览：两级设备树

| 级别 | 载体 | 作用范围 |
|---|---|---|
| **U-Boot 自带 DTB** | `CONFIG_DEFAULT_DEVICE_TREE`（如 `rk3576-evb`）编译为 `u-boot.dtb`，打包进 `uboot.img` | SPL 加载 U-Boot proper 后的**最早初始化**：串口、MMC、PMIC 等基础外设 |
| **内核 DTB**（实际决定功能） | 从启动介质加载（extboot 下即 boot 分区里的 `rk-kernel.dtb`） | `board_init()` 起接管设备模型；最终原样传给 Linux |

关键配置（`configs/rk3576_defconfig` / 头文件）：

```
CONFIG_USING_KERNEL_DTB=y
CONFIG_USING_KERNEL_DTB_V2=y
CONFIG_ROCKCHIP_EARLY_DISTRO_DTB=y
CONFIG_ROCKCHIP_EARLY_DISTRO_DTB_PATH="rk-kernel.dtb"
```

### 1.2 接管时机：非常早，先于一切启动命令

`arch/arm/mach-rockchip/board.c:557` 的 `board_init()`：

```c
int board_init(void)
{
	board_debug_init();          // 调试串口（此时还能靠 Ctrl+C 打断 autoboot）
#ifdef CONFIG_USING_KERNEL_DTB
	init_kernel_dtb();           // ← 就在这里接管内核 dtb（board.c:567）
#endif
	...
}
```

`board_init()` 运行于 autoboot / 任何 boot 命令**之前**——所以无论是自动启动还是在命令行敲 `booti`，设备模型早已按内核 dtb 重建完毕。

### 1.3 内核 DTB 的查找顺序（`rockchip_read_dtb_file`，`boot_rkimg.c:525`）

按优先级依次尝试（`dtb_scan`，`boot_rkimg.c:488`）：

| 优先级 | 来源 | 实现位置 | 说明 |
|---|---|---|---|
| ① DISTRO | bootable 分区文件系统里的 `rk-kernel.dtb` | `rockchip_read_distro_dtb()`，`boot_rkimg.c:434` | **extboot 模式命中此项**。流程：`part list ${devtype} ${devnum} -bootable devplist` 找到 bootable 分区 → `load <devtype> <devnum>:<分区> fdt_addr_r rk-kernel.dtb`（路径即 `CONFIG_ROCKCHIP_EARLY_DISTRO_DTB_PATH`）。ext4 驱动支持符号链接（`fs/ext4/ext4_common.c:2156`），因此首启脚本 `ln -sf dtb/rk3576-lubancat-3.dtb /boot/rk-kernel.dtb` 创建的软链能被正确解析 |
| ② RESOURCE | resource.img 内的 dtb | `rockchip_read_resource_dtb()` | 非(extboot) 老式打包才用；支持哈希校验 |
| ③ FIT | FIT 镜像内 fdt 节点 | `fit_image_read_dtb()` | 仅 `CONFIG_ROCKCHIP_FIT_IMAGE` 且非 resource 模式 |
| ④ 内嵌兜底 | 编译进 U-Boot 的 dtb | `kernel_dtb.c:334` | 需 `CONFIG_EMBED_KERNEL_DTB`（本 SDK 未开），都失败时报 `Failed to get kernel dtb` 并沿用自带 dtb |

> 对 LubanCat extboot 方案而言：**boot 分区根目录的 `rk-kernel.dtb` 就是 U-Boot 与内核共用的设备树**——这正是"改内核 DTS = 同时改 U-Boot 网络"的根本原因。

### 1.4 接管过程（`init_kernel_dtb`，`kernel_dtb.c:297`）

```c
ret = rockchip_read_dtb_file((void *)fdt_addr);      // ①~④ 查找并加载到 fdt_addr_r (0x48300000)
if (!dtb_check_ok(fdt, gd->fdt_blob)) ...            // 平台兼容性校验（不匹配则拒绝，防串刷 dtb）
dtb_okay:
	gd->fdt_blob = (void *)fdt_addr;                 // 全局 FDT 指针切换为内核 dtb
	hotkey_run(HK_FDT);                              // 支持热键临时换 dtb
	gd->of_root_f = gd->of_root;
	of_live_build(gd->fdt_blob, &gd->of_root);        // 内核 dtb → 平铺设备树(live tree)
	dm_scan_fdt(gd->fdt_blob, false);                // 扫描新设备并入驱动模型
	dm_rm_kernel_dev();                              // V2: 清理 CRYPTO 等内核 dtb 设备重挂
	dm_rm_u_boot_dev();                              // V2: 关键！见下
	mmc_dm_reinit();                                 // MMC 重新绑定（时钟等取自内核 dtb）
	boot_fdt_add_sysmem_rsv_regions(...);            // 保留 reserved-memory 区域
```

**V2 流程的核心：`dm_rm_u_boot_dev()`（`kernel_dtb.c:44`）**

- 遍历 `UCLASS_ETH`：若设备模型中存在**来自内核 dtb** 的网卡设备，就把 U-Boot 自带 dtb 建立的 ETH 设备**全部删除**；
- 同理 `dm_rm_kernel_dev()` 处理 `UCLASS_CRYPTO`；
- 结论：**U-Boot 运行期的网卡实例完全由内核 dtb 的 gmac 节点决定**（是否存在、reset GPIO、时钟、PHY），U-Boot 自带 dtb 仅作兜底。

### 1.5 传递给内核

接管完成后，`fdt_addr_r`（0x48300000）处的这份 dtb 就是最终交付物：

- `booti <kernel> - <fdt>` 时 U-Boot 在其 `/chosen` 节点中写入 `bootargs`、`rng-seed` 等 fixup 后跳转内核；
- 因此 U-Boot 命令行 `setenv bootargs ...` 的内容，最终也落在这份 dtb 里。

---

## 2. 如何修改优先启动的介质

### 2.1 先分清三层"启动介质"概念

| 层 | 决定什么 | 可修改性 |
|---|---|---|
| **L0：BootROM** | 上电后从哪个介质加载 loader（优先级固化在芯片里：SPI NOR → eMMC → SD → USB OTG） | ❌ 软件不可改 |
| **L1：loader 烧录位置** | U-Boot 本体在哪（烧在 eMMC 的 uboot 分区或 SPI flash） | 由烧录操作决定 |
| **L2：U-Boot 加载内核的介质顺序** | U-Boot 运行后按什么顺序尝试哪个分区/介质/协议启动内核 | ✅ **软件可改，本文重点** |

### 2.2 L2 的现状：启动命令链与介质顺序

**默认 bootcmd（`include/configs/rockchip-common.h:170-178`，按宏开关三选一）：**

```c
#if defined(CONFIG_AVB_VBMETA_PUBLIC_KEY_VALIDATE)
	"boot_android ${devtype} ${devnum};"           // 纯 Android AVB 流程
#elif defined(CONFIG_FIT_SIGNATURE)
	"boot_fit;"                                     // 纯 FIT 流程
#else                                            // 本 SDK 实际命中的分支：
	"run distro_bootcmd;"                           // ① distro 扫描（boot.scr/extlinux）
	"boot_android ${devtype} ${devnum};"            // ② Android boot.img 流程
	"boot_fit;"                                     // ③ FIT 兜底
	"bootrkp;"                                      // ④ Rockchip resource 兜底
#endif
```

**① `distro_bootcmd` 的介质顺序** = `boot_targets` 环境变量，由 `BOOT_TARGET_DEVICES` 宏（`rockchip-common.h:107-113`）生成，本 SDK 默认值：

```
boot_targets = mmc1 mmc0 mtd2 mtd1 mtd0 rknand0 usb0 pxe dhcp
                │      │                        │     │    │
                SD    eMMC                    SPI  NAND  USB→PXE→DHCP
```

即：**SD 卡 → eMMC → SPI/NAND → USB → PXE → DHCP**（`rockchip-common.h:66`：`/* First try to boot from SD (index 1), then eMMC (index 0) */`）。

**② `boot_android` 的介质选择**由 `RKIMG_DET_BOOTDEV`（`rockchip-common.h:153-175`）动态探测，同样 **SD 优先**：`mmc dev 1` + `rkimgtest` 成功 → SD；否则 `mmc dev 0`（eMMC）→ mtd_blk → rknand → rksfc。

### 2.3 修改方法（按侵入程度从低到高）

#### 方法 1：运行时 `setenv`（单次生效，重启失效）

```shell
# 例：改为 eMMC 优先、禁用 SD/网络
setenv boot_targets 'mmc0 mmc1 usb0'
run distro_bootcmd

# 例：本 boot 直接网络引导（配合我们已打通的 TFTP）
setenv bootcmd 'tftp ${kernel_addr_r} Image; tftp ${fdt_addr_r} rk3576-lubancat-3.dtb; \
 setenv bootargs "console=ttyFIQ0,1500000 console=tty1 rw rootwait root=/dev/mmcblk0p3 rootfstype=ext4"; \
 booti ${kernel_addr_r} - ${fdt_addr_r}'
run bootcmd
```

失效原因：本 SDK `CONFIG_ENV_IS_NOWHERE=y`（`u-boot.cfg` 实测），`saveenv` 无处保存，重启回到默认值。适合临时调试。

#### 方法 2：固化默认 `boot_targets`（改默认环境，重编 uboot）——**推荐**

在 `include/configs/rk3576_common.h` 的 `CONFIG_EXTRA_ENV_SETTINGS` 中追加一行覆盖默认值（`env_default.h` 中 EXTRA_ENV 在默认值**之后**导入，同名变量即覆盖）：

```c
#define CONFIG_EXTRA_ENV_SETTINGS \
	ENV_MEM_LAYOUT_SETTINGS \
	"fdtfile=" "rk-kernel.dtb" "\0" \
	"boot_targets=" "mmc0 usb0 pxe dhcp" "\0" \      /* ← 新增：eMMC 优先，去掉 SD/MTD */
	"partitions=" PARTS_RKIMG \
	...
```

> 不建议直接改 `rockchip-common.h` 的 `BOOT_TARGET_DEVICES` 宏——它被全 Rockchip 系列芯片共用，影响面大。

重编并烧录：

```shell
./build.sh uboot
./rkflash.sh uboot        # 或 upgrade_tool di -uboot output/firmware/uboot.img
```

#### 方法 3：固化自定义 `bootcmd`（跳过扫描，直接指定启动动作）

同样在 `CONFIG_EXTRA_ENV_SETTINGS` 中追加 `bootcmd=...`（覆盖 `RKIMG_BOOTCOMMAND`），例如无条件网络引导、或只认 eMMC：

```c
"bootcmd=" "tftp ${kernel_addr_r} Image; tftp ${fdt_addr_r} rk3576-lubancat-3.dtb; \
	booti ${kernel_addr_r} - ${fdt_addr_r}" "\0" \
```



#### 方法 4：让环境变量持久化（一劳永逸，改动最大）

开启 `CONFIG_ENV_IS_IN_MMC`（需要一个 env 存储偏移/分区；RK SDK 默认 NOWHERE，且当前 `parameter-extboot.txt` 没有预留 env 分区，需要规划存储位置）。之后 `setenv` + `saveenv` 即可运行时固化任何启动顺序，无需重编。适合产品化阶段。

#### 方法 5：L2 中 Android 流程的介质探测顺序

若你的启动走 `boot_android` 分支，SD 优先行为由 `RKIMG_DET_BOOTDEV`（`rockchip-common.h:153`）里的 `mmc dev 1 && rkimgtest` 探测实现——希望 eMMC 优先就调整该探测顺序（同样建议在板级头文件覆盖，不动公共头）。

### 2.4 方法对比与推荐

| 方法 | 生效范围 | 重编 uboot | 适用场景 |
|---|---|---|---|
| 1. `setenv` | 本次上电 | 否 | 临时调试（当前调试流程即用此法） |
| 2. 固化 `boot_targets` | 永久 | 是 | 调整介质优先级（如 eMMC 优先于 SD） |
| 3. 固化 `bootcmd` | 永久 | 是 | 无头设备固定从网络/固定介质启动 |
| 4. `ENV_IS_IN_MMC` | 永久+运行时可改 | 是 | 产品化，现场可调 |
| 5. 改 `RKIMG_DET_BOOTDEV` | 永久 | 是 | 走 Android 流程时的介质探测顺序 |

**推荐路径**：调试期方法 1；确定策略后方法 2/3 写入板级头文件重编；产品化再考虑方法 4。

### 2.5 注意事项

1. **BootROM 层改不了**：想让 U-Boot 本体从别处加载，只能通过烧录位置（如 SPI flash 烧 loader）实现；
2. `rockchip-common.h` / `config_distro_bootcmd.h` 是公共文件，改动影响所有板型——优先在 `rk3576_common.h` 用 EXTRA_ENV 覆盖；
3. `boot_targets` 中 PXE/DHCP 排在最后是刻意的兜底设计（本地全部失败才走网络），若要"网络优先"需显式前置 `pxe`/`dhcp` 或固化网络 `bootcmd`；
4. `boot_targets` 里每个介质条目对应 `bootcmd_<name>` 脚本（由 `BOOTENV_DEV` 宏生成），可用 `printenv bootcmd_mmc0` 查看具体动作；
5. 重编后确认 `u-boot.cfg` / 串口日志中的实际 bootcmd/boottargets（`U-Boot 20xx...` 后 `printenv`）再出厂。

---

## 附：本文关键源码索引

| 结论 | 位置 |
|---|---|
| 内核 dtb 接管入口 | `arch/arm/mach-rockchip/board.c:567` → `init_kernel_dtb()` |
| dtb 查找顺序 | `arch/arm/mach-rockchip/boot_rkimg.c:525`（DISTRO→RESOURCE→FIT→内嵌） |
| DISTRO 路径加载 | `boot_rkimg.c:434`（part list -bootable + load rk-kernel.dtb） |
| V2 设备清理 | `kernel_dtb.c:35`（crypto）、`kernel_dtb.c:44`（ETH：删 U-Boot 设备换内核 dtb） |
| ext4 软链支持 | `fs/ext4/ext4_common.c:2156` |
| 默认介质顺序 | `include/configs/rockchip-common.h:66-113`（SD 优先于 eMMC） |
| bootcmd 三分支 | `include/configs/rockchip-common.h:170-178` |
| Android 流程介质探测 | `include/configs/rockchip-common.h:153-175`（RKIMG_DET_BOOTDEV） |
| 默认环境覆盖机制 | `include/env_default.h`（EXTRA_ENV_SETTINGS 晚于默认值导入） |
| env 不持久 | `u-boot.cfg`: `CONFIG_ENV_IS_NOWHERE=1` |
