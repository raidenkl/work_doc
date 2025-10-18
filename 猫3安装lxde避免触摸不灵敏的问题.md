# 0.说明

这个办法只是现在工程师尚未修复好gnome桌面的办法，还有一些不足，比如用不了vnc，桌面比较丑等，如果能忽视这些缺点，可以继续了。
## 1.安装

这边使用的镜像是22.04的ubuntu-lite，没有桌面，方便配置。
先安装gdm3，再装lxde
```
sudo apt update
# 安装gdm3有个选项，直接回车就行
sudo apt install gdm3
# 安装lxde要选界面管理器，选gdm3
sudo apt install lxde
# 不知道什么原因只装lxde进不去桌面，再再加一个xfce4
sudo apt install xfce4
sudo reboot
```
这个时候用触摸屏，点击cat用户，在输入密码的时候，右下角有个齿轮，点击选择lxde，输入密码，就可以进入桌面了。

## %关于vnc
串口或者ssh执行如下命令好像就可以用了,前提是gdm3,现在处于可远观而不可亵玩焉的状态，等待后续修复

```
xhost +local: 
xhost +
export DISPLAY=:0
```