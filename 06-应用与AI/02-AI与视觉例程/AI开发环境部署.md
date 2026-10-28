# 前置条件
参考的文档在这里：https://doc.embedfire.com/linux/rk356x/Ai/zh/latest/lubancat_ai/env/env.html

注意，下面安装的都是在x86架构的pcUbuntu系统上操作的，不要在板卡做下面的操作。
# 1.Anaconda安装
去[官网](https://www.anaconda.com/download/success)下载，下载左边的完整版，然后导进ubuntu里。因为是一个脚本，所以需要`sudo chmod +x xxx.sh`。然后按照文档2.3.1章节安装，接受许可证，最后输入yes同意初始化。可以用下面的命令禁止默认启动虚拟环境:
```
conda config --set auto_activate_base false
```
然后就是改源

`sudo vim ~/.condarc`

改成ustc的：
```
channels:
  - defaults
show_channel_urls: true
default_channels:
  - https://mirrors.ustc.edu.cn/anaconda/pkgs/main
  - https://mirrors.ustc.edu.cn/anaconda/pkgs/r
  - https://mirrors.ustc.edu.cn/anaconda/pkgs/msys2
custom_channels:
  conda-forge: https://mirrors.ustc.edu.cn/anaconda/cloud
  bioconda: https://mirrors.ustc.edu.cn/anaconda/cloud
```

# 2.rknn-toolkit2安装

这是参考文档2.3.2的安装过程，我做了一些修改，下面有说明：
```
# 创建一个名为toolkit2_1.6的环境，并指定python版本，
conda create -n toolkit2_1.6 python=3.8
conda activate toolkit2_1.6

# 拉取toolkit2源码
git clone https://github.com/airockchip/rknn-toolkit2

# 配置pip源
pip3 config set global.index-url https://mirrors.aliyun.com/pypi/simple/

# pip安装指定版本的库（教程测试时toolkit2版本是2.3.2，请根据python版本选择文件安装）
cd rknn-toolkit2
pip3 install -r packages/requirements_cp38-2.3.2.txt

# 需要根据python版本和rknn_toolkit2版本选择whl文件，例如这里创建的是python3.8环境，使用带”cp38”的whl文件。
pip3 install packages/rknn_toolkit2-2.3.2-cp38-cp38-manylinux_2_17_x86_64.manylinux2014_x86_64.whl
```

拉取源码这步，太慢的话直接去github下载，然后unzip解压，一样的。

pip源我改成了阿里云，教程的源不行。

pip安装指定版本的库，这里要`cd`进`rknn-toolkit2`文件夹里的`packages`具体看是哪个cp38，下面whl文件相同。

# 3.paddlepaddle安装

进paddlepaddle[官网](https://www.paddlepaddle.org.cn/install/old?docurl=undefined#old-version-anchor-7-Conda%E5%AE%89%E8%A3%85%E6%96%B9%E5%BC%8F)，选旧版本安装，我用的是3.0，选的是conda的cpu版本安装，完整安装过程如下：
```
# 使用conda创建一个名为paddle的环境，并指定python版本
conda activate
conda create -n paddle python=3.8

# 进入环境
conda activate paddle

# 安装paddlepaddle计算平台是cpu
conda install paddlepaddle==3.0.0 -c paddle

# 验证安装成功，检测版本
python3 -c "import paddle;paddle.utils.run_check()"
```

