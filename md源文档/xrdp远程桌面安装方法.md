# xrdp 远程桌面安装方法（板卡侧手工，不固化进镜像）

> 适用：LubanCat-5（RK3588）上烧录本仓库构建的 Kali rootfs 镜像
> 前提：桌面为 XFCE + lightdm；GPU 用户态为 panfork mesa（默认）+ 闭源 libmali（按需）
> **本文档记录的步骤只在板卡上执行，不写进构建流程** —— 每次重新烧录镜像后需重做一次。

---

## 0. 为什么用 xrdp 而不是 x11vnc

板上实测结论（2026-09-24）：

| 方案 | 结果 | 原因 |
| --- | --- | --- |
| `x11vnc`（默认 / `-noshm`） | ❌ 每次连接都把 Xorg 搞崩 | 抓屏迫使 glamor 做「GPU→CPU 回读」，内核同时报 `mali fb000000.gpu: Invalid CPU access to UMM memory`，Xorg 随即 `Caught signal 7 (Bus error) → Server aborting`；`-loop` 会变成 3 秒一轮的崩溃循环 |
| `x11vnc -rawfb` 读 `/dev/fb0` | ❌ 连上但全黑 | 该 fb 不是 HDMI 活跃扫描输出（mmap 也失败），读到的是无效缓冲 |
| **`xrdp` + `xorgxrdp`** | ✅ **可用** | xorgxrdp 的 Xorg 用内存 framebuffer 驱动，**不访问 `/dev/dri`、不触发 mali**，与 GPU 栈完全解耦 |

**代价（重要）**：xrdp 提供的是**独立虚拟会话**，不是 HDMI 上那个 `:0` 桌面。
两个桌面并行共存（HDMI 一个、远程一个），互不干扰。

---

## 1. 前置检查（只读）

```bash
apt-cache policy xrdp xorgxrdp        # 关键：xorgxrdp 必须在（Kali 源自带）
df -h /                               # 装完约需 30~50MB
ip -4 addr | grep inet                # 记下板卡 IP，客户端要连它
ps -eo args | grep '[X]org'           # 记当前 X 实例数，便于事后对照
dmesg | grep -c 'Invalid CPU access'  # 记这个数字，验证时要求它「不增加」
```

登录账号用 **`cat`**（构建时设过密码）。忘记密码可在板上 `passwd cat` 重设。

---

## 2. 安装

```bash
apt update
apt install -y xrdp xorgxrdp
```

- `xorgxrdp` 不能漏：只有 `xrdp` 时缺少 Xorg 后端模块，连接会报
  `Cannot find Xorg module` / 直接断开。
- 若会话起来后 DBus 相关服务（如 xfce4-power-manager）报错，可补装 `dbus-x11`。

---

## 3. 会话启动脚本

**先看默认脚本**（多数情况够用）：

```bash
cat /etc/xrdp/startwm.sh
```

Debian/Kali 的默认实现会去执行 `/etc/X11/Xsession`，而 XFCE 是系统默认会话，通常直接可用。

**若连上后黑屏 / 没有面板**，加用户级兜底（推荐，改动最小）：

```bash
printf 'startxfce4\n' > /home/cat/.xsession
chmod +x /home/cat/.xsession
chown cat:cat /home/cat/.xsession
```

（等价的系统级做法：在 `/etc/xrdp/startwm.sh` 末尾加 `exec startxfce4`，影响所有用户。）

---

## 4. 启动服务并设置开机自启

```bash
systemctl enable --now xrdp
systemctl status xrdp --no-pager | head -8

# 较新版本 sesman 是独立 unit，存在就一并启用
systemctl list-unit-files | grep -i xrdp
systemctl enable --now xrdp-sesman    # 无此 unit 会报 not found，忽略即可

ss -lntp | grep 3389                  # 期望看到 0.0.0.0:3389 / [::]:3389
```

> `systemctl enable` 的效果写在磁盘上，**只要不重烧镜像就一直有效**；重烧后需重做本节。

---

## 5. 客户端连接

**Windows（推荐）**：`Win+R` → `mstsc` → 计算机填 `<板卡IP>:3389` → 用户名 `cat` + 密码 → 会话类型选 **Xorg**。

**Linux**：

```bash
xfreerdp /v:<板卡IP>:3389 /u:cat /w:1600 /h:900 +clipboard
```

连接后可用的默认能力：双向剪贴板、分辨率自适应。默认**无音频**转发（需要的话另配 pulseaudio 模块）。

---

## 6. 验证成功的判据

| 检查 | 期望 |
| --- | --- |
| mstsc 进入桌面 | XFCE 桌面可见、能开终端、窗口可拖动 |
| `ps -eo args \| grep '[X]org'` | 比第 1 步多出一个 Xorg（xrdp 自己的 display，通常是 `:10`） |
| `journalctl -b \| grep -i xrdp \| tail` | 无 fatal / error |
| `dmesg \| grep -c 'Invalid CPU access'` | **与第 1 步相同**（证明真的没碰 GPU 通路） |

---

## 7. 故障排查

日志位置（按排查优先级）：

```bash
tail -50 /var/log/xrdp-sesman.log     # ★ 会话启动失败绝大多数在这里
tail -30 /var/log/xrdp.log
cat /home/cat/.xsession-errors        # 会话内程序报错
```

症状对照表：

| 症状 | 原因与处理 |
| --- | --- |
| 连接被拒 / 秒断 | `xrdp-sesman` 没跑：`systemctl enable --now xrdp-sesman`；确认 3389 在监听 |
| 连上但黑屏无面板 | 会话没启动窗口管理器：按第 3 步加 `~/.xsession`（`startxfce4`） |
| 报 `Cannot find Xorg module` | 漏装 `xorgxrdp` |
| 想用 root 登录被拒 | `/etc/xrdp/sesman.ini` 的 `[Security]` 段设 `AllowRootLogin=true`，然后 `systemctl restart xrdp`（安全上仍建议用 `cat`） |
| 键鼠布局异常 | `/etc/xrdp/xrdp.ini` 调整键盘段落；客户端也可指定布局 |
| 分辨率/色深不理想 | `xrdp.ini` 的 `[Globals] max_bpp=32`，客户端侧再指定宽高 |
| 会话断开后进程残留 | `sesman.ini` 的 `KillDisconnected` / `DisconnectedTimeLimit` |

可选：`sesman.ini` 里 `MaxSessions` 控制同一账号并发会话数。

---

## 8. 卸载 / 回滚

```bash
systemctl disable --now xrdp
apt purge -y xrdp xorgxrdp
rm -f /home/cat/.xsession
# 残留按需清理：/etc/xrdp、/var/log/xrdp*.log、/var/lib/xrdp
```

对仓库与镜像零影响（本方案不改构建流程）。

---

## 9. 一键脚本（可选，方便重烧后快速重做）

存成板卡上的 `/root/setup-xrdp.sh`，`chmod +x` 后执行：

```bash
#!/bin/bash -e
# 板卡侧一键安装 xrdp（Xorg 后端 + XFCE 会话）
apt update
apt install -y xrdp xorgxrdp

# 会话兜底：确保 XFCE 被拉起（默认 startwm.sh 已可用时也可保留，无害）
printf 'startxfce4\n' > /home/cat/.xsession
chmod +x /home/cat/.xsession
chown cat:cat /home/cat/.xsession

systemctl enable --now xrdp
systemctl list-unit-files | grep -q '^xrdp-sesman' && systemctl enable --now xrdp-sesman || true

ss -lntp | grep 3389 && echo "[ok] xrdp 已在 3389 监听，用 mstsc 连 <板卡IP>:3389，账号 cat"
```

---

## 10. 备注：若将来要固化进镜像

本次明确**不固化**（保持镜像精简、且这是使用侧需求而非出厂能力）。若以后要内置，改动要点：

1. `scripts/build-rootfs.sh` 的 apt 包列表加 `xrdp xorgxrdp`（改包列表会自动让 apt 阶段失效重跑）；
2. 新增 `overlay/etc/xrdp/startwm.sh`（定制为 `exec startxfce4`）与 `overlay/home/cat/.xsession`，
   并在 overlay **逐文件 `cp`** 段补对应拷贝语句（该仓库 overlay 是逐文件复制，新增文件必须同步补）；
3. 照 `cpu-governor-performance.service` 的既有写法加
   `chroot ${chroot_dir} /bin/bash -c "systemctl enable xrdp"`；
4. 文档同步：`build/docker/README.md` 的改动清单 + `README.md` 的功能列表各补一条，并注明
   **"xrdp 是独立虚拟会话，不是 HDMI 上的桌面"** 这一前提；
5. 注意 `GPU_STACK=libmali|both` 时 `/etc/ld.so.conf.d/00-aarch64-mali.conf` 的全局注入已被构建期注释，
   xrdp 会话走默认库路径（panfork），无额外处理需求。
