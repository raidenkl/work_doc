在make编译时，出现C++： fatal error:已杀死 signal terminated program cc1plus

出现上述问题，可以考虑是虚拟机内存不足，可以采用swap分区的方式解决。

具体命令是：

（1）主目录下创建分区路径（直接用“ctrl + ALT + T 打开terminal ，运行下面命令”）

`sudo mkdir -p /var/cache/swap/`

（2）设置分区的大小（不唯一）
bs=64M是块大小，count=64是块数量，所以swap空间大小是bs*count=4096MB=4GB
sudo dd if=/dev/zero of=/var/cache/swap/swap0 bs=64M count=64

`sudo dd if=/dev/zero of=/var/cache/swap/swap0 bs=64M count=64`

（3）设置该目录权限

`sudo chmod 0600 /var/cache/swap/swap0`

（4）创建SWAP文件

`sudo mkswap /var/cache/swap/swap0`

（5）激活SWAP文件

`sudo swapon /var/cache/swap/swap0`

（6）查看SWAP信息是否正确

`sudo swapon -s`


swap0文件的路径在/var/cache/swap/下，编译完后, 如果不想要交换分区了, 可以删除。

删除交换分区的命令：

```
sudo swapoff /var/cache/swap/swap0
sudo rm /var/cache/swap/swap0
```

释放空间命令：

```
sudo swapoff -a
#详细的用法：swapoff --help
```

查看当前内存使用情况：

`free -m`