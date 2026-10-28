## 0.配置
    因为22.04的镜像默认用的窗口系统是Wayland，需要先改成x11。
`sudo vim /etc/gdm3/custom.conf`


把文件里的`WaylandEnable=true`改成`WaylandEnable=false`。这样配置gdm3就会使用x11窗口系统。

开启自动登录：
```
文件里的：
  # AutomaticLoginEnable = false
  # AutomaticLogin = user1
改成：
  AutomaticLoginEnable = true
  AutomaticLogin = cat

```

开启七寸屏的设备树插件：

`sudo vim /boot/firmware/ubuntuEnv.txt`

在`overlays=`这一行后面加上`rk3588-lubancat-5-dsi1-1024x600-overlay`，保存退出。

做好配置之后重启。

## 1.安装vnc
这里参考[VNC远程桌面](https://doc.embedfire.com/linux/rk3588/quick_start/zh/latest/quick_start/vnc/vnc.html)这份文档安装就可以。设置完密码之后执行：
```
export DISPLAY=:0
x11vnc -auth guess -once -loop -noxdamage -repeat -rfbauth /home/cat/.vnc/passwd -rfbport 5900 -shared

```

如果没有提示`-auth guess: failed for display=':0'`基本说明就成功了，这个时候用mobaxterm登录vnc就行。
