# LubanCat-4 (RK3588S) 三路 MIPI 摄像头 TCP 硬编码推流指南

> 板卡：LubanCat-4（RK3588S）· 内核 6.1.99-rk3588 · GStreamer 1.22.9
> 板卡 IP：192.168.103.104 · 用户名/密码：cat / temppwd
> 已验证：Windows VLC 通过 `tcp://` 播放三路摄像头画面成功

---

## 1. 摄像头节点对照表

| 接口 | 传感器 | rkisp 通道 | video 节点 | 最大分辨率 |
|------|--------|-----------|-----------|-----------|
| CAM0 | gc08a8 | rkisp0-vir0 | `/dev/video33` | 3264×2448 |
| CAM1 | gc08a8 | rkisp0-vir1 | `/dev/video42` | 3264×2448 |
| CAM2 | imx415 | rkisp1-vir0 | `/dev/video51` | 3840×2160 |

查看当前节点：
```bash
v4l2-ctl --list-devices
```

---

## 2. 最终可用命令（板卡上执行）

### 三路一键启动

```bash
# CAM0 —— 端口 5000
nohup gst-launch-1.0 v4l2src device=/dev/video33 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  mpph264enc bps=4000000 header-mode=each-idr gop=30 ! h264parse ! \
  "video/x-h264,stream-format=byte-stream,alignment=nal" ! \
  mpegtsmux ! tcpserversink host=0.0.0.0 port=5000 \
  > /tmp/cam0.log 2>&1 &

# CAM1 —— 端口 5002
nohup gst-launch-1.0 v4l2src device=/dev/video42 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  mpph264enc bps=4000000 header-mode=each-idr gop=30 ! h264parse ! \
  "video/x-h264,stream-format=byte-stream,alignment=nal" ! \
  mpegtsmux ! tcpserversink host=0.0.0.0 port=5002 \
  > /tmp/cam1.log 2>&1 &

# CAM2 —— 端口 5004
nohup gst-launch-1.0 v4l2src device=/dev/video51 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  mpph264enc bps=4000000 header-mode=each-idr gop=30 ! h264parse ! \
  "video/x-h264,stream-format=byte-stream,alignment=nal" ! \
  mpegtsmux ! tcpserversink host=0.0.0.0 port=5004 \
  > /tmp/cam2.log 2>&1 &
```

### 单路测试（CAM0）

```bash
nohup gst-launch-1.0 v4l2src device=/dev/video33 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  mpph264enc bps=4000000 header-mode=each-idr gop=30 ! h264parse ! \
  "video/x-h264,stream-format=byte-stream,alignment=nal" ! \
  mpegtsmux ! tcpserversink host=0.0.0.0 port=5000 \
  > /tmp/cam0.log 2>&1 &
```

---

## 3. VLC 播放（Windows 端）

媒体 → 打开网络串流，分别输入：

```
tcp://192.168.103.104:5000
tcp://192.168.103.104:5002
tcp://192.168.103.104:5004
```

---

## 3.5 用 MobaXterm X 服务器直接预览（可选，不走 VLC）

> 若想在 MobaXterm 弹出的窗口里直接看摄像头画面（非 VLC），需满足：
> - MobaXterm 连接时已开启 X11 转发（会话设置 → X11 → 勾选），登录后 `echo $DISPLAY` 应为 `localhost:10.0` 之类
> - **不能用 `ximagesink`**（XInput2 bug，报 BadValue）和 **`xvimagesink`**（MobaXterm 不支持 XVideo 扩展）
> - 必须用 **`glimagesink`** 并强制 **GLX 平台**（板卡 Mali 默认 EGL 在远程 X 下报 `EGL_NOT_INITIALIZED`）

### 3.5.1 单路预览（CAM0）

```bash
export GST_GL_PLATFORM=glx GST_GL_API=opengl

gst-launch-1.0 v4l2src device=/dev/video33 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! glupload ! glimagesink sync=false
```

### 3.5.2 三路同时预览

```bash
export GST_GL_PLATFORM=glx GST_GL_API=opengl

# CAM0
gst-launch-1.0 v4l2src device=/dev/video33 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! glupload ! glimagesink sync=false &

# CAM1
gst-launch-1.0 v4l2src device=/dev/video42 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! glupload ! glimagesink sync=false &

# CAM2
gst-launch-1.0 v4l2src device=/dev/video51 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! glupload ! glimagesink sync=false &
```

### 3.5.3 MobaXterm 预览要点

- **必须 `export GST_GL_PLATFORM=glx GST_GL_API=opengl`**：强制 GLX 绕过 EGL，否则报 `Failed to initialize egl: EGL_NOT_INITIALIZED`
- **必须加 `glupload`**：`glimagesink` 需要 GLMemory，直接接 `videoconvert` 报 not-negotiated
- **预览与推流互斥**：同一 `/dev/video` 设备被推流占用时预览报 "设备或资源忙"，先 `pkill -x gst-launch-1.0` 停推流
- **X11 转发效率低**：三路同时预览建议降到 `640x480`
- 若 GLX 仍失败/白屏，回退到方案 3（VLC 播放 `tcp://`），最稳定

---

## 3.6 用 SSH 在板卡 HDMI 屏幕本地预览（不依赖 Windows/MobaXterm）

> 若板卡已连接 **HDMI 显示器**（板卡本地有桌面/GNOME 运行），可通过 SSH 登录后把摄像头画面直接显示到板卡自己的 HDMI 屏幕上。
> 原理：SSH 登录后设置 `DISPLAY=:0`（板卡本地 X server）和 `XAUTHORITY`，用 `autovideosink` 自动选择可用的本地 sink（板卡本地 Xorg 支持 xvimagesink/ximagesink 等，不报 XInput 错误）。

### 3.6.1 三路同时预览到 HDMI

```bash
export DISPLAY=:0
export XAUTHORITY=/home/cat/.Xauthority

# CAM0
gst-launch-1.0 v4l2src device=/dev/video33 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! autovideosink sync=false &

# CAM1
gst-launch-1.0 v4l2src device=/dev/video42 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! autovideosink sync=false &

# CAM2
gst-launch-1.0 v4l2src device=/dev/video51 ! \
  "video/x-raw,format=NV12,width=1280,height=960,framerate=30/1" ! \
  videoconvert ! autovideosink sync=false &
```

### 3.6.2 HDMI 预览要点

- **必须设置 `DISPLAY=:0`**：指向板卡本地 X server（HDMI 屏幕）；不设置时 SSH 会话无 DISPLAY，无法开窗口
- **必须设置 `XAUTHORITY=/home/cat/.Xauthority`**：SSH 会话默认没有本地 X 的授权，否则报 `No protocol specified` 或 `cannot open display`
- **用 `autovideosink`**：板卡本地 Xorg 功能完整，`autovideosink` 会自动选 `xvimagesink`/`ximagesink`，均可用；若个别异常可显式改用 `xvimagesink`
- **预览与推流互斥**：同一 `/dev/video` 设备被推流占用时预览报 "设备或资源忙"，先 `pkill -x gst-launch-1.0` 停推流
- 若 HDMI 未连接，画面会显示到虚拟 X 上（无物理输出），此时请改用方案 3（VLC `tcp://`）或方案 3.5（MobaXterm 转发）

---

## 4. 关键参数说明（踩坑总结）

| 参数 | 作用 | 必填 |
|------|------|------|
| `mpph264enc bps=4000000` | 码率 4Mbps（注意：此板卡 mpp 插件用 `bps`，**不是** `bitrate`） | ✅ |
| `header-mode=each-idr` | **核心修复**：每个关键帧都内嵌 SPS/PPS，VLC 随时可解码 | ✅ |
| `gop=30` | 每 30 帧（1 秒）一个关键帧，缩短 VLC 起播等待 | ✅ |
| `"video/x-h264,stream-format=byte-stream,alignment=nal"` | 让 mpegtsmux 正确切分 NAL，否则报 not-negotiated | ✅ |
| `tcpserversink host=0.0.0.0` | TCP 服务器，监听所有网卡，VLC 用 tcp:// 连接 | ✅ |
| `mpegtsmux` | MPEG-TS 封装，VLC 打开 tcp:// 自动识别 H264，无需 SDP | ✅ |

---

## 5. 常见问题排查

### 5.1 VLC 黑屏但进度条在走
- 原因：SPS/PPS 只在第一帧发送，VLC 中途连接拿不到参数集
- 解决：加 `header-mode=each-idr`（必须），不要用 `h264parse config-interval=-1`

### 5.2 mpph264enc 找不到属性 bitrate
- 此板卡 Rockchip 旧版插件用 `bps` 控制码率，非 `bitrate`

### 5.3 报 not-negotiated
- 缺少 `"video/x-h264,stream-format=byte-stream,alignment=nal"` capsfilter

### 5.4 三路中某路没画面
- 确认对应端口已监听：`ss -tlnp | grep 5002`
- 确认摄像头节点存在：`v4l2-ctl --list-devices`

### 5.5 查看日志
```bash
tail -5 /tmp/cam0.log   # cam1.log / cam2.log
```

---

## 6. 管理命令

```bash
# 查看推流进程
pgrep -x gst-launch-1.0

# 查看端口监听
ss -tlnp | grep -E '5000|5002|5004'

# 停止全部推流
pkill -x gst-launch-1.0
```

---

## 7. 附录：mpph264enc 常用属性

| 属性 | 说明 | 建议值 |
|------|------|--------|
| `bps` | 目标码率 | `4000000`（4Mbps） |
| `gop` | I 帧间隔（-1=按帧率） | `30` |
| `rc-mode` | 码率模式：0=vbr, 1=cbr, 2=fixqp | `1`（默认 cbr） |
| `profile` | H264 档次：baseline/main/high | `high`（默认） |
| `level` | 级别（40=1080p@30, 42=1080p@60, 50=4K@30） | `40` |
| `header-mode` | 参数集发送：first-frame / each-idr | `each-idr` |
