这个方法需要有桌面环境，所以这边用vnc的自启示例

桌面环境输入alt+f2，然后输入`gnome-session-properties`

点击add添加新的自启服务，我这里用vnc示例，名字就写`vnc`，命令参考文档，写
```
/usr/bin/x11vnc -auth guess -display :0 -rfbauth /home/cat/.vnc/passwd -rfbport 5900 -forever -loop -noxdamage -repeat -shared -capslock -nomodtweak
```

然后保存关闭就行