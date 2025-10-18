在尝试在板卡上编译内核模块时出现报错信息：
```
make -C /lib/modules/6.1.75/build M=/home/cat/Workspace/modules/hello modules
make[1]: Entering directory '/usr/src/linux-headers-6.1.75'
warning: the compiler differs from the one used to build the kernel
The kernel was built by: aarch64-linux-gnu-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
You are using: gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
CC [M] /home/cat/Workspace/modules/hello/hello.o

↓↓↓↓ 报错信息 ↓↓↓↓
/bin/sh: 1: scripts/basic/fixdep: Exec format error
↑↑↑↑ 报错信息 ↑↑↑↑

make[2]: *** [scripts/Makefile.build:250:
/home/cat/Workspace/modules/hello/hello.o] Error 126
make[2]: *** Deleting file '/home/cat/Workspace/modules/hello/hello.o'
make[1]: *** [Makefile:2014: /home/cat/Workspace/modules/hello] Error 2
make[1]: Leaving directory '/usr/src/linux-headers-6.1.75'
make: *** [Makefile:8: all] Error 2

```

## 解决方法
内容中有一个警告信息，说我们使用的 gcc 版本不是编译内核所使用的 aarch64-linux-gnu-gcc

执行 `gcc -v` 可以看到我们的 host 是 aarch64，版本也是相同的
```
cat@lubancat:~$ gcc -v
Using built-in specs.
COLLECT_GCC=gcc
COLLECT_LTO_WRAPPER=/usr/lib/gcc/aarch64-linux-gnu/11/lto-wrapper
Target: aarch64-linux-gnu
Configured with: ../src/configure -v --with-pkgversion='Ubuntu 11.4.0-1ubuntu1~22.04' --with-bugurl=file:///usr/share/doc/gcc-11/README.Bugs --enable-languages=c,ada,c++,go,d,fortran,objc,obj-c++,m2 --prefix=/usr --with-gcc-major-version-only --program-suffix=-11 --program-prefix=aarch64-linux-gnu- --enable-shared --enable-linker-build-id --libexecdir=/usr/lib --without-included-gettext --enable-threads=posix --libdir=/usr/lib --enable-nls --enable-bootstrap --enable-clocale=gnu --enable-libstdcxx-debug --enable-libstdcxx-time=yes --with-default-libstdcxx-abi=new --enable-gnu-unique-object --disable-libquadmath --disable-libquadmath-support --enable-plugin --enable-default-pie --with-system-zlib --enable-libphobos-checking=release --with-target-system-zlib=auto --enable-objc-gc=auto --enable-multiarch --enable-fix-cortex-a53-843419 --disable-werror --enable-checking=release --build=aarch64-linux-gnu --host=aarch64-linux-gnu --target=aarch64-linux-gnu --with-build-config=bootstrap-lto-lean --enable-link-serialization=2
Thread model: posix
Supported LTO compression algorithms: zlib zstd
gcc version 11.4.0 (Ubuntu 11.4.0-1ubuntu1~22.04)
```
所以这个警报不必在意。

接下来是报错内容，说是 `scripts/basic/fixdep: Exec format error`，其中 `Exec format error` 这种类型的报错主要是运行的二进制文件指令不兼容，这种问题可能发生在比如 在 x86 平台上执行 arm 平台的二进制文件，反之也会报这样的错误。所以我们找到这个 fixdep 的二进制文件

这个文件在文件系统的 /usr/src/linux-headers-6.1.75/scripts/basic/ 目录下，执行 ls 可以看到以下内容：
```
cat@lubancat:~$ ls /usr/src/linux-headers-6.1.75/scripts/basic/
fixdep  fixdep.c  Makefile
```

>具体目录是不是 linux-headers-6.1.75 需要检查内核对应的版本，可以使用 name -r 来检查自己板卡对应的目录

这个 `fixdep` 就是我们编译内核模块时看到的报错信息对应的文件，通过 `readelf` 指令查看这个二进制文件，可以看到，这个二进制文件对应的硬件平台是 x86-64，而我手里的鲁班猫板子所使用的是 ARMv8 指令集，无法执行 x86-64 的二进制文件，所以会报上面列出的那个错误，解决方法就是重新编译生成这个可执行文件，执行如下指令：
```
# 跳转到二进制文件对应的目录
cd /usr/src/linux-headers-`uname -r`/scripts/basic

# 删除原有的指令格式异常的二进制文件
sudo rm fixdep

# 重新编译生成那个 fixdep 文件
sudo gcc fixdep.c -o fixdep
```
再次编译内核模块，又遇到报错信息，和上面提到的差不多，也是说文件格式错误，如下所示：
```
cat@lubancat:~/Workspace/modules$ make
make -C /lib/modules/6.1.75/build M=/home/cat/Workspace/modules modules
make[1]: Entering directory '/usr/src/linux-headers-6.1.75'
warning: the compiler differs from the one used to build the kernel
  The kernel was built by: aarch64-linux-gnu-gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
  You are using:           gcc (Ubuntu 11.4.0-1ubuntu1~22.04) 11.4.0
  CC [M]  /home/cat/Workspace/modules/hello.o
  MODPOST /home/cat/Workspace/modules/Module.symvers
/bin/sh: 1: scripts/mod/modpost: Exec format error
make[2]: *** [scripts/Makefile.modpost:126: /home/cat/Workspace/modules/Module.symvers] Error 126
make[1]: *** [Makefile:1966: modpost] Error 2
make[1]: Leaving directory '/usr/src/linux-headers-6.1.75'
make: *** [Makefile:5: all] Error 2
```
可以看到 `scripts/mod/modpost` 这个文件的文件格式也有问题，解决方式和之前提到的 `fixdep` 相同，执行如下指令：
```
# 跳转到对应的目录
cd /usr/src/linux-headers-`uname -r`/scripts/mod/

# 删除指令格式异常的文件 modpost 文件
sudo rm modpost

# 重新生成 modpost 文件，依赖源文件可以通过 Makefile 文件找到信息
sudo gcc file2alias.c sumversion.c modpost.c -o modpost
```
执行之后可以看到重新生成了 modpost 文件，再次编译内核模块，可以看到编译通过，生成 xxx.ko 文件