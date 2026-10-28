出现/dev/ttyS* permission denied.

解决方法:
`sudo chmod 777 /dev/ttyS*`

上面的方法每次开机都得操作一遍，实在麻烦。后面找到了个一劳永逸的解决方法

`sudo usermod -aG dialout username`

username修改为自己的用户名，加入dialout用户组，重启电脑后即可