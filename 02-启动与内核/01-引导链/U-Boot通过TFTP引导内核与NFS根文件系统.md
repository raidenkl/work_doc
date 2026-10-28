---
title: U-Boot 通过 TFTP 引导内核与 NFS 根文件系统
summary: 从零跑通网络启动的全流程，每节都写了怎么判断这一步过了，附 tftpboot.zip
board: [鲁班猫4]
soc: RK3588S
kernel: "6.1"
os: buildroot
tags: [U-Boot, TFTP, NFS, 启动]
updated: 2026-10-28
formats: [md]
---

# U-Boot 通过 TFTP 引导内核、NFS 挂载根文件系统

一份从零到跑通的实操记录，基于 RK3588S（鲁班猫 4 V1）+ Rockchip next-dev U-Boot + 内核 6.1 + buildroot 根文件系统。

文中所有命令都在真机上验证过，包括中途卡住的几次。如果你照着做，建议按章节顺序来，每一节末尾都有"怎么判断这一步过了"，别跳。

---

## 一、这套方案在做什么

正常启动是"Bootloader 从 flash 里读出内核镜像，内核再挂载 flash 上的根分区"。TFTP + NFS 启动把这件拆成两半：

- **内核和设备树**不放在板子上，每次上电由 U-Boot 通过 TFTP 从主机下载到内存，然后 `booti` 跳进去
- **根文件系统**也不在板子上，内核起来后通过 NFS 把主机上的一个目录挂成 `/`

好处是改内核只换一个文件、改根文件系统直接改主机目录，都不用重新烧写。代价是每次启动都要依赖网络，且主机上得常驻 TFTP 和 NFS 两个服务。

调试驱动、调内核参数、试 rootfs 里的脚本，这套方式比反复烧 eMMC 快一个数量级，值得先把它搭起来。

### 适用环境

| 项      | 本文取值                                             |
| ------ | ------------------------------------------------ |
| 板卡     | LubanCat-4 V1（RK3588S，LPDDR4X，GMAC1 + RTL8211F）  |
| U-Boot | Rockchip next-dev 分支（2017.09 基线），已能识别网卡          |
| 内核     | linux 6.1，`lubancat_linux_rk3588_tftp_defconfig` |
| 根文件系统  | buildroot 2025.11，`millennium_3588_defconfig`    |
| 主机     | Ubuntu 22.04，`10.255.200.141`                    |
| 串口     | UART2，1500000 8N1，内核里是 `ttyFIQ0`                 |

网络拓扑上有一点要注意：U-Boot 用 DHCP 拿到的可能是 `192.168.103.x` 这种地址，而主机在 `10.255.200.x`，跨网段走网关也能通（实测 TFTP 4MB/s），但两套网段并存会让排查变复杂。建议把板子和主机放在同一网段，或者干脆给板子写死静态 IP。

---

## 二、前置条件

### 2.1 U-Boot 必须已经能用网卡

这是整件事的地基。判断标准很简单，U-Boot 启动时打印：

```
Net:   eth1: ethernet@fe1c0000, 92:be:...:xx
```

并且 `ping ${serverip}` 能通、`tftp` 能拉下文件。如果打印的是 `No ethernet found.`，先解决网卡，别往下走。

在 Rockchip 的 next-dev U-Boot 里，网卡能不能用取决于两件事：

1. `gmac1` 节点要活过 `fdtgrep` 的节点裁剪（需要 `u-boot,dm-pre-reloc` 标签）
2. 节点里的 `pinctrl-0`、`assigned-clocks`、`clock-names` 不能在第二遍属性裁剪时被删掉

第二条最容易踩。一个绕开的办法是启用 `CONFIG_EMBED_KERNEL_DTB_ALWAYS=y`，把内核的完整 dtb 编进 uboot.img，运行时 U-Boot 直接用它，属性一个不缺：

```
CONFIG_EMBED_KERNEL_DTB_ALWAYS=y
```

同时把 `rk3588s-lubancat-4-v1.dtb` 放到 `u-boot/dts/kern.dtb`。启动时会打印：

```
Always embed kernel dtb
DTB: dts/kern.dtb
```

这样 U-Boot 和内核用同一份设备树，网卡、PHY、tx_delay 全对得上。代价是 uboot.img 会变大（内核 dtb 有 256KB），需要把 `CONFIG_SPL_FIT_IMAGE_KB` 从 2048 提到 3072、`CONFIG_SPL_FIT_IMAGE_MULTIPLE` 从 2 改成 1，否则打包会报 `fit/uboot.itb actual: 2262528 bytes, max limit: 2097152 bytes`。

rk的next-dev分支u-boot支持config fragment，所以可以在`u-boot/configs`目录新建`rk3588-tftp.config`，囊括上面要注意的点。内容如下：
```
CONFIG_BASE_DEFCONFIG="rk3588_defconfig"
CONFIG_DEFAULT_DEVICE_TREE="rk3588-evb-tftp"
CONFIG_PHY_REALTEK=y
CONFIG_PHY_GIGE=y
CONFIG_EMBED_KERNEL_DTB_ALWAYS=y
CONFIG_SPL_FIT_IMAGE_KB=3072
CONFIG_SPL_FIT_IMAGE_MULTIPLE=1
```

然后执行`./make.sh rk3588-tftp`就可以编译出miniloader.bin文件和uboot.img。


### 2.2 内核配置要核对四项

`lubancat_linux_rk3588_tftp_defconfig` 基本是照着网络启动配的，但仍值得确认一遍 `kernel-6.1/.config`：

```
CONFIG_IP_PNP=y
CONFIG_IP_PNP_DHCP=y
CONFIG_ROOT_NFS=y
CONFIG_NFS_FS=y
CONFIG_STMMAC_ETH=y          ← 必须是 =y，不能是 =m
CONFIG_REALTEK_PHY=y
CONFIG_DEVTMPFS_MOUNT=y
```

几个点的原因：

- `STMMAC_ETH` 必须是内建。NFS 根要在内核启动早期就能收发包，那时还没有用户态去 `modprobe`
- `IP_PNP` 是 `ip=` 参数生效的前提，没有它内核不会自己配 IP
- `DEVTMPFS_MOUNT` 让内核自动挂 `/dev`。NFS 根里没有真实设备节点，少了这个连 `/dev/console` 都打不开

核对命令：

```bash
cd ~/self_linux/kernel-6.1
grep -E 'CONFIG_IP_PNP|CONFIG_ROOT_NFS|CONFIG_NFS_FS|CONFIG_STMMAC_ETH|CONFIG_DEVTMPFS_MOUNT' .config
```

### 2.3 主机上要有的两个服务

```bash
# 检查
systemctl is-active nfs-server rpcbind
command -v exportfs
```

`nfs-server` 和 `rpcbind` 都要是 active。TFTP 服务通常默认没装，下一节处理。

---

## 三、准备主机服务

### 3.1 目录规划

本文用这套布局，路径可以换，换了记得同步后面所有命令：

```
self_linux/tftpboot                      U-Boot 从这里取 Image 和 dtb
├── Image                         内核（raw Image，不是 zImage）
├── rk3588s-lubancat-4-v1.dtb     设备树
└── boot.scr                      可选，自动化脚本

/srv/nfs/cat4-root/               根文件系统，内核挂成 /
```

```bash
sudo mkdir -p /srv/tftp /srv/nfs/cat4-root
```

### 3.2 搭 TFTP

**方式一：tftpd-hpa（推荐）**

```bash
sudo apt install tftpd-hpa
```

编辑 `/etc/default/tftpd-hpa`：

```
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="/srv/tftp"
TFTP_ADDRESS=":69"
TFTP_OPTIONS="--secure --create"
```

```bash
sudo systemctl enable --now tftpd-hpa
sudo systemctl status tftpd-hpa --no-pager
```

**方式二：复用 dnsmasq**

如果机器上本来就有 dnsmasq，在配置里加两行就够了：

```
enable-tftp
tftp-root=/home/dev/self_linux/tftpboot
```

本文后续按方式二写。

把内核和 dtb 放进去：

```bash
sudo cp arch/arm64/boot/Image /home/dev/self_linux/tftpboot
sudo cp arch/arm64/boot/dts/rockchip/rk3588s-lubancat-4-v1.dtb /home/dev/self_linux/tftpboot
sudo chmod -R o+r tftpboot/ 
```



### 3.3 搭 NFS

**先解 rootfs**。buildroot 编译后 `output/images/` 下有 `rootfs.tar`、`rootfs.ext4`，NFS 用 tar 那份：

```bash
cd ~/self_linux/buildroot-2025.11
sudo tar -xpf output/images/rootfs.tar -C /srv/nfs/cat4-root
```

`-p` 不能省。少了它 `/bin/busybox` 的权限位、`/etc/shadow` 的 640 都会丢，系统起来后各种奇怪报错。

不要直接导出 `output/target`。它看着更省事，但里面混着构建期的中间文件，出问题时很难分清是 NFS 的锅还是 rootfs 的锅。

**配置 exports**，`/etc/exports` 加一行：

```
/srv/nfs/cat4-root  192.168.103.0/24(rw,sync,no_subtree_check,no_root_squash,insecure) \
                    10.255.200.0/24(rw,sync,no_subtree_check,no_root_squash,insecure)
```
这里要写两个网段的原因是板卡的ip网段和主机的网段不同，当然也可以省事直接写`*`。
四个选项的具体解析：

- `rw` —— 根文件系统必须可写，否则 `/var`、`/tmp` 写不进去，很多服务直接起不来
- `no_root_squash` —— 客户端的 root 要保持 root 身份。默认的 root_squash 会把它映射成 nobody，写文件立刻 Permission denied
- `insecure` —— 允许客户端用非特权端口连接。Linux 的 mount.nfs 用特权端口没问题，但 U-Boot 的 `nfs` 命令和 busybox 的客户端用的是高位端口，不加这个会被拒
- `no_subtree_check` —— 少一层路径校验，性能和稳定性都更好

**生效并验证**：

```bash
sudo exportfs -arv                # 这里看到的内容才是内核里的真实导出表
showmount -e localhost
```

`exportfs -v` 比 `cat /etc/exports` 可靠得多。改了文件忘记重新导出，是 NFS 排障里最常见的一条。

**本机自测**：

```bash
sudo mkdir -p /mnt/nfstest
sudo mount -t nfs -o vers=3,tcp 10.255.200.141:/srv/nfs/cat4-root /mnt/nfstest -v
ls /mnt/nfstest                  # 应该能看到 bin/ etc/ usr/ 这些目录
sudo umount /mnt/nfstest
```

这一步如果报 `access denied by server`，先看第十节的排查表，九成是客户端地址没被 exports 覆盖。

---

## 四、在 U-Boot 里手动启动

第一次跑通别急着写脚本，手动敲一遍，看清楚每一步的反馈。

### 4.1 命令序列

```
setenv ipaddr 192.168.103.xxx
setenv netmask 255.255.255.0
setenv gatewayip 192.168.103.254    
setenv serverip 10.255.200.141       # 主机（TFTP 服务器）
saveenv                              # 若 env 不持久则每次重设


ping ${serverip}
tftp ${kernel_addr_r} Image
tftp ${fdt_addr_r} rk3588s-lubancat-4-v1.dtb

setenv bootargs "console=ttyFIQ0,1500000 console=tty1 rw rootwait root=/dev/nfs \
 nfsroot=${serverip}:/srv/nfs/cat4-root,v3,tcp \
 ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:lubancat:eth0:off"

fdt addr ${fdt_addr_r}
fdt rm /chosen bootargs

booti ${kernel_addr_r} - ${fdt_addr_r}
```

命令名是 **`tftp`**，不是 `tftpboot`。这个 build 的 `cmd/net.c` 里只注册了 `tftp`、`tftpbootm`、`tftpflash`、`tftpput`，敲 `tftpboot` 会得到 `Unknown command`。

`booti` 中间的 `-` 是 ramdisk 占位符，我们没有 initramfs，所以留空。

`fdt rm /chosen bootargs` 这一句现在看着莫名其妙，第六节会解释——少了它大概率起不来。

### 4.2 内存地址

这个 build 的默认值：

| 变量              | 值            | 用途            |
| --------------- | ------------ | ------------- |
| `kernel_addr_r` | `0x00400000` | 内核加载地址        |
| `fdt_addr_r`    | `0x0a100000` | 设备树加载地址       |
| `scriptaddr`    | `0x00500000` | boot.scr 加载地址 |

arm64 的 `Image` 不需要解压，`booti` 直接把控制权交给它。这三个地址已经错开了，不用改。

### 4.3 bootargs 逐段解释

这一串是整个流程里最容易写错的地方，拆开看：

```
console=ttyFIQ0,1500000
console=tty1
rw
rootwait
root=/dev/nfs
nfsroot=${serverip}:/srv/nfs/cat4-root,v3,tcp \
 ip=${ipaddr}:${serverip}:${gatewayip}:${netmask}:lubancat:eth0:off
```

**`console=ttyFIQ0,1500000`** —— 控制台设备。RK3588 的 dts 用了 fiq-debugger，串口被它接管，对外呈现为 `ttyFIQ0` 而不是 `ttyS2`。波特率 1500000 是 RK 平台的常用值，和你终端的设置一致。

**`root=/dev/nfs`** —— 告诉内核根文件系统从 NFS 来。内核看到这个值会走 NFS 根分支，并用下面的 `nfsroot` 定位服务器。

**`rootwait`** —— 等根设备就绪再挂载。网络设备是异步起来的，没有这个参数内核可能在网卡还没 probe 完就开始挂根，然后直接 panic。

**`nfsroot=<服务器>:<路径>,<选项>`** —— 路径是**服务器上的绝对路径**，必须和 `/etc/exports` 里写的一致。`v3,tcp` 建议显式指定：NFSv3 兼容性最好，配上 TCP 能躲开 UDP 丢包导致的 `server not responding`。

**`ip=<客户端>:<服务器>:<网关>:<掩码>:<主机名>:<网卡>:<自动配置>`** —— 七个字段，冒号分隔，空字段就留空。上面这条的意思：

```
${ipaddr}      板子自己的 IP
${serverip}     NFS/TFTP 服务器 IP
${gatewayip}       网关
${netmask}      掩码
lubancat               主机名，可以不填
eth0               网卡名，必须是内核里的名字
off                不用 DHCP/BOOTP/RARP，全静态
```

如果网络里有 DHCP 服务器，把最后一段换成 `ip=dhcp` 也行。但受管网络里随手起 DHCP 容易和网关打架，静态更可控。

### 4.4 这一步的判定标准

敲完 `booti` 之后，串口应该依次出现：

```
[    0.000000] Booting Linux on physical CPU ...
[    0.000000] Kernel command line: console=ttyFIQ0,1500000 ... root=/dev/nfs ...
[    2.xxx] rk_gmac-dwmac fe1c0000.ethernet eth0: Link is Up - 1Gbps/Full
[    3.xxx] IP-Config: Complete:
[    3.xxx]      device=eth0, addr=10.255.200.50, mask=255.255.255.0, gw=10.255.200.1
[    5.xxx] VFS: Mounted root (nfs filesystem) on device 0:17.
[    5.xxx] devtmpfs: mounted
[    5.xxx] Run /sbin/init as init process
```

看到 `IP-Config: Complete` 说明 `ip=` 生效了；看到 `VFS: Mounted root (nfs filesystem)` 说明根挂上了。这两行是分水岭，卡在哪一行，问题范围就很清楚了。

---

## 五、先解决这个坑：`root=` 被设备树覆盖

如果第二节没做 dtb 那一步，很可能会卡在：

```
[  179.109242] Waiting for root device PARTUUID=614e0000-0000...
```

明明写的是 `root=/dev/nfs`，为什么在等 PARTUUID？看内核打印的完整命令行就明白了：

```
Kernel command line: console=ttyFIQ0 console=tty1 rw rootwait root=PARTUUID=614e0000-0000
   nfsroot=10.255.200.141:/srv/nfs/cat4-root,v3,tcp
   ip=10.255.200.50:10.255.200.141:10.255.200.1:255.255.255.0::eth0:off
   earlycon=uart8250,mmio32,0xfeb50000 irqchip.gicv3_pseudo_nmi=0 rcupdate.rcu_expedited=1 rcu_nocbs=all
```

对照一下会发现：`nfsroot` 和 `ip` 都在（说明 bootargs 传进去了），`root=` 却变成了 PARTUUID，`console=` 的波特率也丢了。

原因在 `arch/arm/mach-rockchip/board.c` 的 `board_fdt_chosen_bootargs()`：

```c
bootargs = fdt_getprop(fdt, nodeoffset, "bootargs", NULL);
...
env_update("bootargs", bootargs);      /* 按键名合并，dtb 的值覆盖环境变量 */
```

它会读设备树里 `/chosen/bootargs`，按键名合并进 U-Boot 的环境变量，**同名参数以 dtb 为准**。而这份 dtb 里写着：

```dts
/* kernel-6.1/arch/arm64/boot/dts/rockchip/rk3588-linux.dtsi */
chosen: chosen {
    bootargs = "earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0 irqchip.gicv3_pseudo_nmi=0
                root=PARTUUID=614e0000-0000 rw rootwait rcupdate.rcu_expedited=1 rcu_nocbs=all";
};
```

`rk3588s-lubancat-4.dts` 第 20 行 include 了它，所以一定生效。这个设计本意是让内核 dts 决定根设备，本地存储启动时很方便，做 NFS 根时就成了拦路虎。

### 临时解法：启动前删掉 dtb 里的 bootargs

```
fdt addr ${fdt_addr_r}
fdt rm /chosen bootargs
```

删掉之后 `board_fdt_chosen_bootargs()` 找不到这个属性，环境变量原样生效。这两行加在 `booti` 之前即可，不用重编任何东西。

### 长期解法：改 dts

把 dtsi 里那个 `root=PARTUUID=...` 删掉，顺便把 `console=ttyFIQ0` 改成 `console=ttyFIQ0,1500000`：

```dts
bootargs = "earlycon=uart8250,mmio32,0xfeb50000 console=ttyFIQ0,1500000
            irqchip.gicv3_pseudo_nmi=0 rw rootwait rcupdate.rcu_expedited=1 rcu_nocbs=all";
```

之后 root 完全由 U-Boot 决定：NFS 启动传 `/dev/nfs`，切回 eMMC 启动就传对应分区，不用再动 dtb。

改完 `make dtbs` 重新生成，**两份都要替换**：

- TFTP 目录里的 `rk3588s-lubancat-4-v1.dtb`（决定内核收到什么 bootargs）
- `u-boot/dts/kern.dtb`（决定 U-Boot 自己的设备）

只换一份会出现"U-Boot 里网卡正常、内核里网卡消失"这类错位问题。

---

## 六、登录：getty 端口要对上

根挂上、init 跑起来之后，如果串口上只有内核日志、没有 `login:`，多半是 getty 挂在了错误的设备上。

buildroot 的 `millennium_3588_defconfig` 里是：

```
BR2_TARGET_GENERIC_GETTY_PORT="ttyS2"
```


但内核启用了 fiq-debugger，串口对外是 `ttyFIQ0`，`ttyS2` 这个设备在内核里根本不存在。两条路：

- 改 buildroot：`BR2_TARGET_GENERIC_GETTY_PORT="ttyFIQ0"`，重新生成 rootfs（`inittab` 里的 getty 行会跟着变）
- 或者关掉内核的 `CONFIG_FIQ_DEBUGGER`，让 uart2 回归普通 8250 串口

登录账号是 `root`，密码看 `BR2_TARGET_GENERIC_ROOT_PASSWD`，这份配置里是 `root`。


## 八、常见问题排查

### 8.1 按现象对号

| 现象                                           | 大概率原因                      | 处理                                               |
| -------------------------------------------- | -------------------------- | ------------------------------------------------ |
| `Unknown command 'tftpboot'`                 | 命令名错了                      | 用 `tftp`                                         |
| `No ethernet found.`                         | 设备树里没有 ethernet 节点         | 见 2.1 节，检查 fdtgrep 裁剪和 `EMBED_KERNEL_DTB_ALWAYS` |
| `ping` 不通                                    | 网段/掩码不对，或 `serverip` 没设    | 确认板子和主机同网段，`setenv serverip`                     |
| `TFTP error: 'File not found'`               | TFTP 根目录里没这个文件，或大小写不对      | 检查 `TFTP_DIRECTORY` 和文件名                         |
| `TFTP error: timeout`                        | 防火墙挡了 UDP 69，或服务没起         | `systemctl status tftpd-hpa`，检查防火墙               |
| `Waiting for root device PARTUUID=...`       | dtb 的 bootargs 覆盖了 `root=` | 见第五节，`fdt rm /chosen bootargs` 或改 dts            |
| `VFS: Unable to mount root fs via NFS`       | exports 没覆盖客户端，或路径不对       | `exportfs -v` 看实际导出表，核对 `nfsroot` 路径             |
| `mount.nfs: access denied by server`         | 客户端地址不在 exports 里          | 见 8.2                                            |
| `nfs: server ... not responding`             | 用了 UDP 且被丢包                | bootargs 加 `,v3,tcp`                             |
| 挂上了但写文件 Permission denied                    | 缺 `no_root_squash` 或 `rw`  | 改 exports 后 `exportfs -ra`                       |
| 根挂上了但没有 login                                | getty 端口不对                 | 见第六节                                             |
| `saveenv` 提示 `Saving Environment to nowhere` | 没有 env 存储介质                | 用 boot.scr，或后续加 env 分区                           |

### 8.2 `access denied by server` 怎么定位

先看挂载日志里这两行：

```
prog 100003 ... port 2049     ← nfsd 在
prog 100005 ... port 34811    ← mountd 在
```

两个都能连，说明服务、端口映射、网络都正常，问题只在**导出访问控制**这一层。

最常见的原因是 exports 只放行了网段，而你在本机用 `localhost` 测试——`localhost` 解析成 `127.0.0.1`，不在 `10.255.200.0/24` 里，自然被拒。两种处理：

```bash
# 改用真实 IP 挂载（推荐，和板子行为一致）
sudo mount -t nfs -o vers=3,tcp 10.255.200.141:/srv/nfs/cat4-root /mnt -v

# 或在 exports 里补上本机地址
/srv/nfs/cat4-root  127.0.0.1(rw,sync,no_subtree_check,no_root_squash,insecure) \
                    10.255.200.0/24(rw,sync,no_subtree_check,no_root_squash,insecure)
```

第二种改完记得 `sudo exportfs -ra`。

服务端日志会直接写明拒绝原因：

```bash
sudo grep -i 'refused mount\|unmatched host' /var/log/syslog | tail
```

### 8.3 挂载超时和挂载被拒是两回事

如果板子那边表现为**卡住很久然后超时**，而不是 `access denied`，那通常不是权限问题，而是端口不通。NFSv3 需要三个端口：

- 111（rpcbind）
- 2049（nfsd）
- mountd 的动态端口（本文环境里是 34811，每次重启可能变）

中间隔防火墙或交换机 ACL 时，动态端口会被挡。把 mountd 端口固定下来，只放行这三个：

```
# /etc/default/nfs-kernel-server
RPCMOUNTDOPTS="-p 20048"
```

```bash
sudo systemctl restart nfs-kernel-server
```

### 8.4 一份好用的日志过滤

内核启动日志很长，用这一条能快速定位网络和挂载相关问题：

```bash
dmesg | grep -iE 'eth0|IP-Config|nfs|VFS|gmac'
```

U-Boot 侧则关注这几行：`Net:`、`TFTP from server`、`Bytes transferred`、`Loading:`。

---

## 九、验证清单

把整个过程按这张表走一遍，每项都过再往下：

1. 主机 `tftp 127.0.0.1 -c get Image` 能取到文件
2. 主机 `sudo mount -t nfs -o vers=3,tcp <主机IP>:/srv/nfs/cat4-root /mnt` 能挂上、能 ls 到 `bin/` `etc/`
3. U-Boot `ping ${serverip}` 通
4. U-Boot `tftp` 拉 Image，大小和源文件一致
5. `booti` 后出现 `IP-Config: Complete`，地址、掩码、网关都对
6. 出现 `VFS: Mounted root (nfs filesystem)`
7. 出现 `Run /sbin/init as init process`
8. 串口出现 login 提示
9. 登录后 `mount | grep nfs` 能看到根是 nfs
10. 改主机上 rootfs 目录里的一个文件，板子上立刻能看到（说明确实是 NFS 挂载，不是本地副本）

第 10 条最能确认你挂的确实是主机上的目录。

---

## 十、几个值得记住的点

**U-Boot 的 `tftp` 不写 `tftpboot`。** 这个分支里命令就叫 `tftp`，网上很多教程写 `tftpboot` 是旧版本或者别的分支的习惯。

**设备树的 bootargs 优先级高于环境变量。** Rockchip 的 U-Boot 会合并两者，同名参数以 dtb 为准。排查 bootargs 不生效的问题时，第一步应该是把内核打印的 `Kernel command line` 和你在 U-Boot 里 setenv 的内容逐字对比，而不是反复改 setenv。

**`ip=` 的七个字段值得背下来。** 客户端、服务器、网关、掩码、主机名、网卡、自动配置方式。中间的字段可以留空，但冒号不能少——少一个冒号整个参数就废了，而且报错信息不会告诉你哪里错了。

**NFS 的三个失败点是分层的。** 服务没起（超时）、导出没覆盖客户端（access denied）、挂载后权限不对（读写失败）。三种现象对应三个完全不同的原因，别混在一起查。

**先让 U-Boot 只做一件事。** 第一次跑的时候，先只验证 `ping` 和 `tftp`，确认网络和文件都对，再拼 bootargs。一次性全配好然后面对一堆日志，比一步一步来慢得多。
