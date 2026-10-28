# debian12

执行下面的命令：
```
sudo apt update
sudo apt install qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools
sudo apt install qtcreator
```
验证qt版本：
```
qmake --version
```

安装例程:
```
sudo apt install qt5-doc qtbase5-examples qtbase5-doc-html
sudo apt install qtcharts5-examples qtcharts5-doc-html qt5serialport-examples qtmultimedia5-examples
```


编译例程的时候要用root用户打开qtcreator，不然会缺少头文件

# ubuntu22.04

执行下面的命令：
```
sudo apt update
sudo apt install aptitude
```
安装qt核心库：
```
sudo apt install libqt5core5a=5.15.3+dfsg-2 libqt5dbus5=5.15.3+dfsg-2 \
libqt5gui5=5.15.3+dfsg-2 libqt5network5=5.15.3+dfsg-2 libqt5widgets5=5.15.3+dfsg-2

sudo aptitude install qtbase5-dev qtchooser qt5-qmake qtbase5-dev-tools

这里直接yes就可以
```
安装qtcreator：
```
sudo aptitude install qtcreator
这里先选no，然后选yes
```
验证qt版本：
```
qmake --version
```
安装例程:
```
sudo apt install qt5-doc qtbase5-examples qtbase5-doc-html
sudo apt install qtcharts5-examples qtcharts5-doc-html qt5serialport-examples qtmultimedia5-examples
```

上面的安装方法只是安装了最核心的qt库，后面编译程序缺少什么库就自行安装一下。