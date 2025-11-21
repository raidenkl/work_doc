## 0.问题描述
就算摄像头打开了，可以用guvcview正常预览，但是没办法用python的`cap = cv2.VideoCapture(11)`来调用摄像头，会提示
```
global /tmp/pip-req-build-n2dy_g_s/opencv/modules/videoio/src/cap_v4l.cpp (890) open VIDEOIO(V4L2:/dev/video11): can't open camera by index
```

## 1.解决方法
可能是文档写的opencv安装版本的问题，用下面的方法安装最新的opencv就解决了
```
#用apt的方法安装的opencv用下面的命令卸载
sudo apt purge python3-opencv
#换pip的源
pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/
#安装
pip install opencv-python  opencv-contrib-python 
```
用下面的方法查看安装的opencv版本
```
cat@lubancat:~$ python3
Python 3.8.10 (default, Nov 14 2022, 12:59:47)
[GCC 9.4.0] on linux
Type "help", "copyright", "credits" or "license" for more information.
>>> import cv2 as cv
>>> print(cv.__version__)
4.12.0
>>>
```
截至2025/11/19，安装的版本是4.12.0
这个时候再使用`python3 xxx.py`执行程序就可以了。