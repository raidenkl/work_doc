## 0.测试环境
pc是win10，做服务端，板卡是Ubuntu系统，做客户端。
键鼠共享使用的方案是deskflow；pc端要去[github仓库](https://github.com/deskflow/deskflow)的release下载。
## 1.板卡端配置
基本上参考这个csdn文档：https://blog.csdn.net/qq_62737390/article/details/145210967
使用Flatpak安装deskflow：
```
# Install Flatpak
sudo add-apt-repository ppa:flatpak/stable
sudo apt update
sudo apt install flatpak

# 可选 安装 GNOME Software Flatpak 插件
sudo apt install gnome-software-plugin-flatpak

# Add the Flathub repository
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
```
重启板卡后，安装deskflow：
```
flatpak install flathub org.deskflow.deskflow
```
需要注意的是，ubuntu22 24使用的是wayland，连上服务端也没办法正常被控制，需要修改`/etc/gdm3/custom.conf`，把`WaylandEnable`这一项改成`false`.