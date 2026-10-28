[原文档](https://doc.embedfire.com/linux/rk356x/build_and_deploy/zh/latest/building_image/lubancat_sdk/lubancat_gen_sdk.html#id11)


>>>>> 以下的命令，全部都不使用root用户执行

## 1.选芯片

如果在编译完一个主芯片的工程后需要切换编译其他的主芯片，要先用以下命令清理SDK， 防止由缓存或编译环境引起的编译错误。
```
# 清除整个SDK的
sudo ./build.sh cleanall

# 选择SDK配置文件
./build.sh chip
```
## 2.选系统
如果已经选择过了主芯片并且不需要切换主芯片，而是要切换同一主芯片的其他板卡或文件系统类型， 则不需要清理SDK。
```
# 选择SDK配置文件
./build.sh lunch
```

## 3.编译uboot
`./build.sh uboot`

构建生成的U-boot镜像为u-boot/uboot.img
## 4.编译kernel
extboot分区内核镜像，要先生成内核deb包，然后再编译内核并将生成的deb包打包进extboot分区。

按顺序执行以下命令，将自动完成 kernel 的构建及打包。
```
./build.sh kerneldeb
./build.sh extboot
```
构建生成的kernel镜像为kernel/extboot.img

## 5.编译rootfs
### 5.1编译ubuntu
目前提供20.04/22.04的根文件系统构建脚本，Kernel-5.10搭配Ubuntu20.04，Kernel-6.1则搭配Ubuntu22.04。 具体的对应情况在SDK配置文件中已经配置好，用户无需特殊关心。
```
# 如果SDK中ubuntu目录是具体的ubuntu20.04或者ubuntu22.04，需要将下面命令中的ubuntu目录路径替换为实际的路径。都有则选择较高版本的安装。
sudo dpkg -i ubuntu/ubuntu-build-service/packages/*
sudo apt-get install -f

# 构建Ubuntu
./build.sh ubuntu
```

### 5.2编译debian
```
# 如果SDK中debian目录是具体的debian11或者debian12，需要将下面命令中的debian目录路径替换为实际的路径。都有则选择较高版本的安装。
sudo dpkg -i debian/ubuntu-build-service/packages/*
sudo apt-get install -f

# 构建Debian
./build.sh debian

# 返回的提示信息：跳过镜像构建，删除rootfs镜像后以便重新构建Debian根文件系统镜像
[    Already Exists IMG,  Skip Make Debian Scripts    ]
[ Delate linaro-rk3588-gnome-rootfs.img To Rebuild Debian IMG ]
```

> 为了加速SDK构建效率，只有不存在已经构建好的根文件系统镜像时才会重新编译根文件系统。如果要重新构建根文件系统，需要先手动删除根文件系统镜像文件。以rk3588为例，我们需要删除ubuntu20.04/ubuntu-rk3588-gnome-rootfs.img时后重新构建镜像时才会重新构建Debian根文件系统。

## 6.镜像打包
当u-boot，kernel，Rootfs都构建完成以后，需要再执行 ./build.sh firmware 进行固件打包， 主要是检查分区表文件是否存在，各个分区是否与分区表配置对应，并根据配置文件将所有的文件复制或链接到rockdev/内。
```
# 固件打包
./build.sh firmware

# 生成update.img
./build.sh updateimg
```
如果最后生成updateimg失败，可以直接用分散的固件根据分区表分开烧录进去
