### 0.前置准备
编译zerotier需要用到cargo，执行`sudo apt install cargo`安装就好，最方便。


### 1.获取zerotier源码

这边实测最新的源码会有这个错误
```
lock file version 4 requires `-Znext-lockfile-bump`
```
查了资料发现是板卡的cargo版本不支持 Rust 1.70+ 才支持的锁文件格式（v4），所以需要回退一些版本，实测zerotier1.8.4版本的源码是可以编译成功的，后面就用1.8.4的举例。

在github右边的release页面找到1.8.4的版本下载就可以。

### 2.编译与安装
把压缩包复制到板卡，源码解压到板卡上，以1.8.4举例：
```
unzip ZeroTierOne-1.8.4.zip
cd ZeroTierOne-1.8.4
make -j8
sudo make install
```

这样就编译安装完成了

### 3.启动zerotier

执行`sudo zerotier-one -d`启动zerotier服务。

测试服务是否执行:`sudo zerotier-cli -v`

使用：`sudo zerotier-cli join XXXXX`

上面的xxxxx换成zerotier网页上的id。

