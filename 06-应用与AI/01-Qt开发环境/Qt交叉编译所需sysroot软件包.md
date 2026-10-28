# Qt 5.15.17 交叉编译 — 板卡需安装的软件包

本文档记录了为编译 Qt 5.15.17 在 LubanCat ARM64 目标板上额外安装的开发包。

## 安装命令汇总

在目标板（`cat@192.168.103.141`）上依次执行：

### 1. SQLite3 + Tslib

```bash
sudo apt-get install -y libsqlite3-dev libts-dev
```

- `libsqlite3-dev` — SQLite3 开发头文件与 pkg-config
- `libts-dev` — Tslib 触摸屏库开发文件（依赖 `libts0`）

### 2. XKBCommon X11

```bash
sudo apt-get install -y libxkbcommon-x11-dev
```

- `libxkbcommon-x11-dev` — xkbcommon X11 支持的开发文件
- `libxcb-xkb-dev` —（作为依赖自动安装）

### 3. XCB 全套扩展开发包

```bash
sudo apt-get install -y \
  libxcb-icccm4-dev \
  libxcb-image0-dev \
  libxcb-keysyms1-dev \
  libxcb-randr0-dev \
  libxcb-render-util0-dev \
  libxcb-shape0-dev \
  libxcb-sync-dev \
  libxcb-xfixes0-dev \
  libxcb-xinerama0-dev \
  libxcb-xinput-dev \
  libxcb-util-dev \
  libxcb-dri2-0-dev \
  libxcb-dri3-dev \
  libxcb-present-dev \
  libxcb-glx0-dev \
  libxcb-res0-dev \
  libxcb-composite0-dev \
  libxcb-damage0-dev
```

## 完整安装列表（共 21 个包）

| 序号 | 包名 | 用途 |
|------|------|------|
| 1 | `libsqlite3-dev` | SQLite3 数据库开发文件 |
| 2 | `libts-dev` | Tslib 触摸屏开发文件 |
| 3 | `libxkbcommon-x11-dev` | XKB X11 键盘映射开发文件 |
| 4 | `libxcb-xkb-dev` | XCB XKB 扩展开发文件 |
| 5 | `libxcb-icccm4-dev` | XCB ICCCM 协议开发文件 |
| 6 | `libxcb-image0-dev` | XCB Image 扩展开发文件 |
| 7 | `libxcb-keysyms1-dev` | XCB KeySyms 开发文件 |
| 8 | `libxcb-randr0-dev` | XCB RandR 扩展开发文件 |
| 9 | `libxcb-render-util0-dev` | XCB Render Util 开发文件 |
| 10 | `libxcb-shape0-dev` | XCB Shape 扩展开发文件 |
| 11 | `libxcb-sync-dev` | XCB Sync 扩展开发文件 |
| 12 | `libxcb-xfixes0-dev` | XCB XFixes 扩展开发文件 |
| 13 | `libxcb-xinerama0-dev` | XCB Xinerama 扩展开发文件 |
| 14 | `libxcb-xinput-dev` | XCB XInput 扩展开发文件 |
| 15 | `libxcb-util-dev` | XCB Utility 开发文件 |
| 16 | `libxcb-dri2-0-dev` | XCB DRI2 扩展开发文件 |
| 17 | `libxcb-dri3-dev` | XCB DRI3 扩展开发文件 |
| 18 | `libxcb-present-dev` | XCB Present 扩展开发文件 |
| 19 | `libxcb-glx0-dev` | XCB GLX 扩展开发文件 |
| 20 | `libxcb-res0-dev` | XCB Res 扩展开发文件 |
| 21 | `libxcb-composite0-dev` | XCB Composite 扩展开发文件 |
| 22 | `libxcb-damage0-dev` | XCB Damage 扩展开发文件 |

## 一键安装命令

```bash
sudo apt-get install -y \
  libsqlite3-dev \
  libts-dev \
  libxkbcommon-x11-dev \
  libxcb-icccm4-dev \
  libxcb-image0-dev \
  libxcb-keysyms1-dev \
  libxcb-randr0-dev \
  libxcb-render-util0-dev \
  libxcb-shape0-dev \
  libxcb-sync-dev \
  libxcb-xfixes0-dev \
  libxcb-xinerama0-dev \
  libxcb-xinput-dev \
  libxcb-util-dev \
  libxcb-dri2-0-dev \
  libxcb-dri3-dev \
  libxcb-present-dev \
  libxcb-glx0-dev \
  libxcb-res0-dev \
  libxcb-composite0-dev \
  libxcb-damage0-dev
```

## 安装后同步 sysroot

安装完成后需将板卡文件重新同步到宿主机的 sysroot：

```bash
rsync -avz cat@192.168.103.141:/usr/lib/     /home/lubancat/bianyiqt/sysroot/usr/lib/
rsync -avz cat@192.168.103.141:/usr/include/  /home/lubancat/bianyiqt/sysroot/usr/include/
rsync -avz cat@192.168.103.141:/usr/share/pkgconfig/ /home/lubancat/bianyiqt/sysroot/usr/share/pkgconfig/
```

---

> **日期：** 2026-06-11  
> **目标板：** LubanCat ARM64 (Debian Bookworm) @ 192.168.103.141  
> **宿主机：** Ubuntu x86_64，交叉编译器 `aarch64-linux-gnu-g++ 12.2.0`
