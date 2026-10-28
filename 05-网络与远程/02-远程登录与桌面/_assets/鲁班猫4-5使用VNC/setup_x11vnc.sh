#!/bin/bash
# x11vnc 自启动一键配置脚本（鲁班猫3, Debian 12, GDM + Xorg :0）
# 用法: 把本文件传到板子上执行  bash setup_x11vnc.sh
set -e

# 1) 写入 systemd 服务（也可直接把 x11vnc.service 拷到 /etc/systemd/system/ 下）
sudo tee /etc/systemd/system/x11vnc.service > /dev/null <<'EOF'
[Unit]
Description=x11vnc VNC server (mirror local display :0)
After=graphical.target
PartOf=graphical.target

[Service]
Type=simple
User=cat
ExecStart=/usr/bin/x11vnc -display :0 -auth guess -forever -shared -noxdamage -repeat -rfbport 5900 -rfbauth /home/cat/.vnc/passwd -o /home/cat/x11vnc.log
Restart=on-failure
RestartSec=3

[Install]
WantedBy=graphical.target
EOF

# 2) 重载 systemd、设置开机自启并立即启动
sudo systemctl daemon-reload
sudo systemctl enable --now x11vnc.service

# 3) 验证
sleep 3
echo "--- service state ---"
systemctl is-active x11vnc.service   # 期望: active
systemctl is-enabled x11vnc.service  # 期望: enabled
echo "--- port 5900 ---"
ss -tln | grep 5900                  # 期望: 0.0.0.0:5900

