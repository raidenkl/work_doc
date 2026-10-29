---
title: rkboot与extboot学习笔记
summary: 鲁班猫 U-Boot 启动机制的学习笔记
board: [鲁班猫]
soc: RK3588
tags: [U-Boot,  启动]
updated: 2026-10-29
formats: [md]
---


# 鲁班猫 U-Boot 启动机制学习笔记：rkboot 与 extboot

> 基于 LubanCat_Linux_Generic_Full_SDK 源码整理，内核以 rk3568/rk3576 为例。
> 源码路径如无特别说明，均指 SDK 根目录下的相对路径。
>
> **进阶篇**：`rkboot与extboot启动流程详解-进阶篇.md`——分阶段讲源码函数、加载地址、启动介质差异，附 Mermaid 流程图和面试追问清单。本文适合先建立概念。

## 写在前面

如果你烧录过鲁班猫的镜像，应该知道系统里有几个固定的分区：uboot、boot、rootfs。uboot 分区放 Bootloader，rootfs 放整个系统，这个好理解。那 boot 分区里放的是什么？

这个问题没有唯一的答案。在这套 SDK 里，同一个 boot 分区可以装两种完全不同的东西，对应两种不同的启动方式——野火把它们分别叫做 **rkboot** 和 **extboot**。理解这两种机制，基本上就把 Rockchip 平台 Bootloader 的设计思路摸了一遍，比单独读代码收获大得多。

这份笔记的写法是：先把需要的背景知识补齐，然后顺着"镜像怎么打出来的、U-Boot 怎么把它启动起来的"这条线，把两边的关键源码各走读一遍，最后比较两者的取舍。建议对照源码一起看。

---

## 一、先补几个背景概念

### 1.1 U-Boot 的启动流程长什么样

RK3568 上电后的大致路径是：

```
BootROM(片内ROM) → TPL/SPL(DDR初始化) → U-Boot proper → Linux 内核
```

我们关心的部分在最后一段：U-Boot proper 怎么把内核、设备树、ramdisk 从存储介质搬到内存，然后跳进内核入口。这件事需要一个"启动介质"（eMMC、SD 卡、SPI Flash……）和一个"启动方法"（从哪里读、读出来是什么格式）。

### 1.2 什么是 FIT 镜像

FIT（Flattened Image Tree）是 U-Boot 上游标准的一种镜像格式。简单说，它是一个用 .its 文本文件描述、用 mkimage 工具编译出来的"包裹"：把内核、设备树、ramdisk 等多个文件装进一个文件，附上加载地址、压缩方式、哈希校验等信息。Android 的 boot.img 是另一种类似思路的打包格式，Rockchip 自己还有第三种更简单的私有格式（后面会讲到）。

### 1.3 什么是 distro boot

distro boot 是 U-Boot 上游为通用 Linux 发行版设计的一套启动约定。核心思想很朴素：**不要把启动配置写死在 U-Boot 里，而是到存储设备上找一个文本描述文件，按描述文件说的办**。U-Boot 会扫描各个分区的文件系统，找到 `/extlinux/extlinux.conf` 或者 `boot.scr` 脚本，按里面的内容加载内核。

Debian、Ubuntu 官方的 ARM64 镜像用的都是这套机制。它要求 boot 内容必须放在一个**有文件系统的分区**里，因为是按文件名去读的。

这两种思路——"配置写死、镜像打包"和"文件系统 + 描述文件"——正是 rkboot 和 extboot 的不同。

---

## 二、一切的起点：U-Boot 里那四条命令

看这个文件：

```c
/* u-boot/include/configs/rockchip-common.h */
#define RKIMG_BOOTCOMMAND           \
    "run distro_bootcmd;"           \
    "boot_android ${devtype} ${devnum};"    \
    "boot_fit;"                     \
    "bootrkp;"
```

Rockchip 的 U-Boot 默认启动命令就是这四条，用分号连起来**依次尝试**。哪一条先成功，系统就从哪里启动；失败的命令静默跳过，继续试下一条。

- `run distro_bootcmd`：上游标准的扫描式启动，找 extlinux.conf 和 boot.scr。**extboot 靠它**。
- `boot_android`：启动 Android 格式的 boot.img。走 AVB 签名校验那套生态。
- `boot_fit`：启动 FIT 镜像。**rkboot 主要靠它**。
- `bootrkp`：Rockchip 原生私有格式，最后兜底。

这个设计叫**回退链（fallback chain）**，是兼容多生态的常用手法。rkboot 模式下 boot 分区是一段裸数据，没有任何文件系统，distro_bootcmd 里 `test -e` 检查文件必然失败，于是链条自然落到 `boot_fit`；extboot 模式下第一步就找到 extlinux.conf，直接启动，后面的命令根本不会执行。

同一份 U-Boot 二进制，两种机制都能跑，切换只发生在镜像侧。

---

## 三、rkboot：打包成一个 FIT 镜像

### 3.1 分区表长什么样

看 rkboot 模式用的分区表 `device/rockchip/.chips/rk3566_rk3568/parameter-buildroot-fit.txt`：

```
uboot(4M), misc, boot(64M), recovery, backup, rootfs, oem, userdata:grow
```

这是一套完整的量产布局：misc 给 BCB 启动标志用，recovery 配合 OTA 升级，backup 存恢复数据，还有 oem 和 userdata。boot 分区 64MB，够装一个 FIT 镜像。

### 3.2 内核是怎么被打包的

rkboot 模式下构建内核，实际执行的是：

```sh
make <板卡DTS名>.img        # 编译内核，产出 Image
```

然后用 `mk-fitimage.sh` 配合 **zboot.its** 打包。打开这个 ITS 文件看看里面装了什么（`device/rockchip/.chips/rk3566_rk3568/zboot.its`）：

```
images {
    fdt      { data = 内核DTB;     hash { algo = "sha256"; } }
    kernel   { data = Image;       compression = "lz4"; hash { algo = "sha256"; } }
    resource { data = resource.img; }
};
```

三个成分：设备树、（lz4 压缩的）内核、resource.img——最后这个是 Rockchip 的资源镜像，里面装着 U-Boot 阶段要用的 DTB 副本和开机 logo。每个成分都带 sha256 哈希，启动时可以校验完整性。

mkimage 编译完产出一个 boot.img（FIT 格式），直接烧进 boot 分区。**这个分区没有文件系统**，U-Boot 读它的时候是当成一段裸数据来读的。

### 3.3 bootrkp：裸镜像怎么读

兜底的 `bootrkp` 命令实现 `u-boot/cmd/bootrkp.c`，能看清楚 Rockchip 私有格式有多简单。它的镜像头只有 12 字节：8 字节头（tag 魔数 + size）加 4 字节 CRC32：

```c
static int read_rockchip_image(struct blk_desc *dev_desc,
                               disk_partition_t *part, void *dst)
{
    /* 读一个扇区（512B），检查魔数 */
    ret = blk_dread(dev_desc, part->start, 1, img);
    if (img->tag != TAG_KERNEL) {
        printf("Invalid %s image tag(0x%x)\n", part->name, img->tag);
        return -EINVAL;
    }
    /* 总长 = 数据 + 8字节头 + 4字节CRC */
    cnt = DIV_ROUND_UP(img->size + 8 + 4, RK_BLK_SIZE);
    ...
    memcpy(dst, dst + header_len, img->size);   /* 去头，数据前移 */

    /* Rockchip 自己实现的 CRC32 校验 */
    crc32 = crc32_verify((uchar *)(ulong)dst, img->size + 4);
    ...
}
```

启动主函数 `boot_rockchip_image()` 的逻辑是纯"定点搬运"：从名为 `kernel` 的分区读内核镜像，从 boot 分区读 ramdisk（可选，读失败就当没有），从 resource.img 里提取 DTB，最后拼一条命令：

```c
snprintf(cmdbuf, 64, "booti 0x%lx 0x%lx:0x%x 0x%lx",
         kernel_addr_r, ramdisk_addr_r, ramdisk_size, fdt_addr_r);
run_command(cmdbuf, 0);
```

三个加载地址 `kernel_addr_r`、`ramdisk_addr_r`、`fdt_addr_r` 全部来自 U-Boot 默认环境变量，分区名也是编译期写死的。整个机制没有一点"找"的成分，路径都是确定的。

这就是 rkboot 的特点：**格式私有、位置固定、有校验、启动快**。代价是改任何东西都要重新打包镜像。

---

## 四、extboot：把 boot 分区变成文件系统

### 4.1 分区表的变化

extboot 模式用的是 `parameter-extboot.txt`：

```
uboot(8M), boot(128M, bootable), rootfs:grow
```

对比 rkboot 的分区表，变化很说明问题：

1. **misc、recovery、backup、oem 全没了**。这套 extboot 配置同时关闭了 `RK_RECOVERY`，等于声明"我不走 OTA 那套生态"，rootfs 直接 grow 吃掉剩余空间。
2. boot 分区扩到 128MB，因为要装的东西变多了（下面会看到清单）。
3. boot 分区多了个 **bootable 标志**。这个标志不是摆设——U-Boot 的 distro boot 靠 `part list ${devtype} ${devnum} -bootable devplist` 这条命令找到它，决定去哪个分区扫文件。

### 4.2 打包过程：一个目录变成一个磁盘镜像

打包函数在 `device/rockchip/common/scripts/mk-kernel.sh` 里，叫 `do_build_extboot`。它的思路比想象中直接：

```sh
EXTBOOT_DIR=${RK_SDK_DIR}/kernel/extboot
mkdir -p $EXTBOOT_DIR/{uEnv,kerneldeb,extlinux}

# 内核按版本号命名，支持多内核共存
cp ${RK_SDK_DIR}/$RK_KERNEL_IMG $EXTBOOT_DIR/Image-$KERNEL_VER

# 生成 distro boot 的入口描述文件
echo -e "label kernel-$KERNEL_VER" >> $EXTBOOT_DIR/extlinux/extlinux.conf
echo -e "\tkernel /Image-$KERNEL_VER" >> ...
echo -e "\tdevicetreedir /" >> ...
echo -e "\tappend root=/dev/mmcblk0p3 console=ttyFIQ0 ..." >> ...

# 所有板卡的 DTB 和 overlay 全放进去
cp ${RK_SDK_DIR}/${RK_KERNEL_DTS_DIR}/*.dtb $EXTBOOT_DTB_DIR
cp ${RK_SDK_DIR}/${RK_KERNEL_DTS_DIR}/overlay/*.dtbo $EXTBOOT_DTB_DIR/overlay

# uEnv 变量文件按实际内核版本改写，boot.cmd 编译成 boot.scr
sed -i "s/^uname_r=.*/uname_r=${KERNEL_VER}/" $EXTBOOT_DIR/uEnv/uEnv*.txt
mkimage -T script -C none -d $EXTBOOT_DIR/boot.cmd $EXTBOOT_DIR/boot.scr

# 关键一步：把整个目录做成 ext2 磁盘镜像
truncate -s 128M $EXTBOOT_IMG
fakeroot mkfs.ext2 -F -L "boot" -d $EXTBOOT_DIR $EXTBOOT_IMG

# 符号链接成固件目录里的 boot.img，烧写流程完全复用
ln -rsf "$RK_SDK_DIR/kernel/extboot.img" "$RK_FIRMWARE_DIR/boot.img"
```

`mkfs.ext2 -d` 这个用法值得记住：它能把一个现成目录的内容直接灌进新文件系统，不需要先 mount、再拷贝、再卸载，一条命令完成"目录 → 磁盘镜像"。整个 extboot 的打包就建立在它上面。

最后那个符号链接是个小聪明：产物的**文件名**仍然叫 boot.img，package-file 和烧写工具一概不用改——只是内容从 FIT 裸镜像换成了文件系统镜像。对烧录工具来说两者毫无区别。

我在服务器上找到了一份实际构建出来的产物（rk3576，内核 6.1.99-rt36），目录内容一览：

```
kernel/extboot/
├── Image-6.1.99-rt36-rk3576      内核镜像（版本号命名）
├── System.map-...  config-...    调试用信息
├── boot.cmd  boot.scr            U-Boot 脚本（源码和编译产物）
├── dtb/                          全系板卡 DTB + overlay/
├── extlinux/extlinux.conf        distro boot 主入口
├── initrd-6.1                    initramfs
├── kerneldeb/                    内核 deb 包（Debian/Ubuntu 用）
├── logo.bmp  logo_kernel.bmp     开机 logo
├── rk-kernel.dtb                 默认 DTB（用途见第六节）
└── uEnv/                         各板卡的变量文件
```

和 rkboot 的 FIT 镜像比，东西多了不少，也全部是"看得见摸得着"的文件。

### 4.3 extlinux.conf：一份声明式的启动配置

```
label kernel-6.1.99-rt36-rk3576
	kernel /Image-6.1.99-rt36-rk3576
	devicetreedir /
	append  root=/dev/mmcblk0p3 earlyprintk console=ttyFIQ0 console=tty1
	        consoleblank=0 loglevel=7 rootwait rw rootfstype=ext4 ...
```

三个字段：`kernel` 指定内核文件；`devicetreedir` 让 U-Boot 到根目录下按设备树里的 `model` 属性自动匹配正确的 DTB——所以**一份镜像可以覆盖全系鲁班猫板卡**；`append` 就是内核命令行，注意 root= 在打包时写死成了 p3（这版分区表里 rootfs 确实是第三个分区）。

解析这份文件的是 U-Boot 的 `sysboot` 命令（实现在 `cmd/pxe.c`），它把各字段加载到 `kernel_addr_r`、`fdt_addr_r` 等约定地址，最后执行 booti。扫描逻辑本身在上游的 `include/config_distro_bootcmd.h`：

```
"scan_dev_for_extlinux="
    "if test -e ${devtype} ${devnum}:${distro_bootpart} "
    "${prefix}extlinux/extlinux.conf; then "
        "echo Found ${prefix}extlinux/extlinux.conf; "
        "run boot_extlinux; "
    "fi"
```

### 4.4 uEnv.txt：留给用户改的变量层

`uEnv/uEnv.txt` 的内容很简单：

```
uname_r=6.1.99-rt36-rk3576      # 内核版本 → 决定加载哪个 Image-<版本>
initrd=initrd-6.1
cmdline="earlyprintk console=ttyFIQ0 console=tty1 ... rootfstype=ext4"

enable_uboot_overlays=0
#dtoverlay=/dtb/overlay/rk35xx-lubancat-xxx-overlay.dtbo
```

它的定位是**用户可编辑层**：想换内核版本，改 `uname_r`；想挂设备树 overlay，把注释里的 dtoverlay 行打开；想追加内核参数，改 cmdline。全程不用重新打包镜像，改完文本文件直接重启生效。树莓派的 config.txt 就是同样的设计。

---

## 五、boot.cmd：一段能做硬件探测的 U-Boot 脚本

extboot 镜像里同时有 extlinux.conf 和 boot.scr 两个入口（distro boot 扫描时脚本优先于 extlinux），实际优先走的是 boot.scr。它由 `boot.cmd` 编译而来，比 extlinux.conf 能干得多，值得逐段看。

### 5.1 导入板级变量，动态确定 root 分区

```
if test -e ${devtype} ${devnum}:${distro_bootpart} /uEnv/uEnv.txt; then
    load ${devtype} ${devnum}:${distro_bootpart} ${env_addr_r} /uEnv/uEnv.txt
    env import -t ${env_addr_r} 0x8000        # 把文本导入环境变量

    # 动态查询 rootfs 分区号，不写死
    part number ${devtype} ${devnum} "rootfs" rootfs_part
    setenv bootargs ${bootargs} root=/dev/mmcblk${devnum}p${rootfs_part} \
        boot_part=${distro_bootpart} ${cmdline}
```

`env import` 是 U-Boot hush shell 的一个实用能力：把 key=value 文本直接灌进环境变量。`part number` 则查出了 rootfs 的实际分区号再拼进 bootargs——对比 extlinux.conf 里写死的 p3，这条路径在 SD 卡、eMMC 之间迁移镜像时更健壮。

### 5.2 加载内核三件套

```
if test -e ... /initrd-${uname_r}; then
    load ... ${ramdisk_addr_r} /initrd-${uname_r}
fi
load ... ${kernel_addr_r} /Image-${uname_r}      # 版本化内核
load ... ${fdt_addr_r} /rk-kernel.dtb            # 默认设备树
```

### 5.3 通用屏自动适配：野火的特色功能

这段是最有意思的部分，它用纯 U-Boot 脚本实现了硬件探测：

```
i2c bus                                          # 探测 I2C 总线
if test "${enable_gsdt_auto_load}" = "1" && test -n "${i2c_devs}"; then
    for dev in ${i2c_devs}; do
        i2c dev ${dev}
        i2c md "${eeprom_addr}" 0 1              # 读屏幕背板 EEPROM
        if test $? -eq 0; then
            setenv plugin_file "${gsdt_plugin0}"  # 按 EEPROM 内容选 DTBO
            load ... ${fdt_over_addr} ${plugin_file}
            fdt apply ${fdt_over_addr}            # 叠加到基础 DTB
        fi
    done
fi
```

逻辑是：上电后探测 I2C 总线，尝试读显示模组背板上的 EEPROM；读到了就根据内容挑一个对应的 .dtbo，用 `fdt apply` 动态叠加进设备树。于是同一套出厂镜像，插不同屏幕都能自动点亮。

这种"运行时探测 + 动态 overlay"的设计，在 FIT 裸镜像方案下做不了（overlay 得预先打进镜像），是文件化 boot 分区独有的灵活性。

### 5.4 最终启动

```
booti ${kernel_addr_r} ${ramdisk_addr_r} ${fdt_addr_r}
```

和 bootrkp 殊途同归——内核三件套搬好之后，都是这条命令。

---

## 六、一个容易被忽略的问题：U-Boot 阶段的设备树从哪来

这是移植时最容易踩坑的地方，单独拿出来说。

Rockchip 的 U-Boot 有一个不太常见的需求：在 distro boot 真正开始扫描**之前**，它就需要一份设备树——显示控制器、logo、PMIC 这些驱动的初始化都依赖它。rkboot 模式下这份 DTB 藏在 resource.img 里；extboot 模式没有 resource.img，就得另想办法。

U-Boot 配置里有这么两项：

```
CONFIG_ROCKCHIP_EARLY_DISTRO_DTB=y
CONFIG_ROCKCHIP_EARLY_DISTRO_DTB_PATH="rk-kernel.dtb"
```

对应的实现 `arch/arm/mach-rockchip/boot_rkimg.c`：

```c
static int rockchip_read_distro_dtb(void *fdt_addr)
{
    /* 找到 bootable 分区（extboot 的 boot 分区就有这个标志） */
    const char *cmd = "part list ${devtype} ${devnum} -bootable devplist";
    ...
    fs_argv[4] = CONFIG_ROCKCHIP_EARLY_DISTRO_DTB_PATH;  /* "rk-kernel.dtb" */
    do_load(NULL, 0, 5, fs_argv, FS_TYPE_ANY);
    ...
}

/* DTB 查找的三级顺序 */
static int dtb_scan(void *fdt, int where)
{
    if (where == LOCATE_DISTRO)       /* ① 先试 extboot 的 rk-kernel.dtb */
        return rockchip_read_distro_dtb(fdt);
    else if (where == LOCATE_RESOURCE)  /* ② 再试 resource.img 里的 DTB */
        ...
    else if (where == LOCATE_FIT)       /* ③ 最后试 FIT 镜像里的 fdt 节点 */
        ...
}
```

现在回头看打包脚本里这一行就有答案了：

```sh
cp $EXTBOOT_DTB_DIR/${RK_KERNEL_DTS_NAME}.dtb $EXTBOOT_DIR/rk-kernel.dtb
```

**U-Boot 早期用的 DTB 和最终传给内核的 DTB 是两份独立加载的东西。**rkboot 从 resource.img 拿，extboot 从文件系统拿，两条路径各自把"早期 DTB"这个坑补上了。如果两份 DTB 不一致——比如 rk-kernel.dtb 是 A 板卡的，extlinux 却匹配到 B 板卡——会出现显示异常之类的怪问题，而且很难第一时间想到原因。遇到 extboot 显示异常时，先检查这两份 DTB 是不是同源。

---

## 七、两种机制怎么选

到这里两条路径都走完了，放在一起看：

| | rkboot（FIT 裸镜像） | extboot（ext2 + distro boot） |
|---|---|---|
| boot 分区内容 | 一个 FIT 镜像，无文件系统 | ext2 文件系统，内核等全是普通文件 |
| 修改内核 | 重新打包镜像 | 换个文件 + 改 uEnv.txt |
| 多板卡支持 | 每块板打一份镜像 | devicetreedir 自动匹配，一份通吃 |
| 镜像校验 | sha256（FIT）+ CRC32（原生格式） | 无（除非启用 FIT 签名） |
| OTA / recovery | 支持（misc/recovery 分区齐全） | 不支持（分区已裁掉） |
| 掉电鲁棒性 | 好（裸数据 + 校验） | 一般（ext2 无日志） |
| 启动速度 | 快（定点读取） | 稍慢（要扫描设备、分区、路径） |
| 典型场景 | 量产、OTA 产品 | 开发、Debian/Ubuntu 通用镜像 |

一句话概括两者的取舍：**rkboot 为量产而生，extboot 为开发而生**。前者格式可控、可校验、启动链路短，适合出货；后者一切皆文件、改起来零打包，适合折腾。extboot 最大的隐忧是 ext2 没有日志，异常掉电可能把 boot 分区搞坏——量产产品如果要用，最好换成 ext4 或者加校验机制。

---

## 八、动手验证建议

纸上得来终觉浅，几个低成本实验：

1. **串口看启动日志**。extboot 启动时留意 `Found /extlinux/extlinux.conf` 或 `Found U-Boot script /boot.scr` 这行输出，能看到 U-Boot 实际走了哪条路径。
2. **在 Linux 里挂载 boot 分区**。extboot 模式下 `mount /dev/mmcblk0p2 /boot`，你会看到和 4.2 节完全一致的目录结构——亲手体会"boot 分区就是文件系统"这件事。
3. **改 uEnv.txt 换启动参数**。往 cmdline 里追加一项（比如 `loglevel=0`），重启看内核日志变化。改坏也没关系，恢复文本就行。
4. **对比两种分区表烧写**。用 SDK 分别构建 rkboot 和 extboot 两个镜像，`parted -l` 对比分区布局，直观感受 4.1 节讲的差异。
5. **读 bootrkp 的失败路径**。故意把 boot 分区刷坏（比如刷成全 0），观察回退链逐级失败再成功的过程，对理解"回退"非常有体感。

---

## 附：关键源码索引

| 文件 | 内容 |
|---|---|
| `u-boot/include/configs/rockchip-common.h` | RKIMG_BOOTCOMMAND 四段回退链、bootdev 探测 |
| `u-boot/cmd/bootrkp.c` | Rockchip 原生镜像格式的读取与启动 |
| `u-boot/cmd/bootfit.c` | FIT 镜像启动命令 |
| `u-boot/arch/arm/mach-rockchip/boot_rkimg.c` | DTB 三级扫描、early distro DTB |
| `u-boot/include/config_distro_bootcmd.h` | distro boot 扫描逻辑（上游代码） |
| `device/rockchip/common/scripts/mk-kernel.sh` | do_build_extboot 打包实现 |
| `device/rockchip/.chips/rk3566_rk3568/zboot.its` | rkboot 模式 FIT 描述文件 |
| `device/rockchip/.chips/rk3566_rk3568/parameter-*.txt` | 两种机制的分区表 |
| `kernel/extboot/` | 构建出的 extboot 产物，可直接对照本文阅读 |
