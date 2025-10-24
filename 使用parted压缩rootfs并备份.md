参考的文章是这个：https://doc.embedfire.com/linux/rk356x/build_and_deploy/zh/latest/building_image/backup_rootfs/backup_rootfs.html#

下面说一下没有gparted的时候应该怎么备份。
## 压缩rootfs分区

因为没有gparted，所以直接用命令压缩了

```
# 这里填多少G根据实际情况写，若指定大小小于已用空间，会提示失败
sudo resize2fs /dev/mmcblk0p3 xxg 

# 启动 parted 工具，指定磁盘
sudo parted /dev/mmcblk0

# 查看当前分区信息（输出中找到 mmcblk0p3 的 "Start" 和 "End" 位置）
(parted) print  

# 调整分区结束位置（假设文件系统已缩小到 7GB，目标分区结束位置为Start + 7GB，我这里写8G）
(parted) resizepart 3  
(parted) 8GB

# 验证调整结果
(parted) print  
(parted) quit

```

后面的步骤参考文档操作就可以了.