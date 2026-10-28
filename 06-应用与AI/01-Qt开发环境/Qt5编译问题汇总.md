# Qt 5.15 交叉编译常见问题修复 (LubanCat ARM64)
原文档参考：https://doc.embedfire.com/linux/rk356x/Qt/zh/latest/lubancat_qt/install/install_arm_2.html#

## 1. sysroot 软链接修复
问题：rsync 复制板子根文件系统后，`/lib` 下的相对软链接指向错误。
修复：
```bash
cd sysroot/lib
ln -sfn ../usr/lib/aarch64-linux-gnu aarch64-linux-gnu
ln -sfn ../usr/lib lib
ln -sfn aarch64-linux-gnu/ld-linux-aarch64.so.1 ld-linux-aarch64.so.1
```

## 2. crt 文件路径
问题：Debian multiarch 把 crt1.o/crti.o/crtn.o 放在 `usr/lib/aarch64-linux-gnu/`，编译器在 `usr/lib/` 找。
修复：
```bash
cd sysroot/usr/lib
ln -sfn aarch64-linux-gnu/crt1.o crt1.o
ln -sfn aarch64-linux-gnu/crti.o crti.o
ln -sfn aarch64-linux-gnu/crtn.o crtn.o
```

## 3. 缺失开发包
板子上需安装：libsqlite3-dev, libts-dev, libxkbcommon-x11-dev, 及全套 libxcb-*-dev。
详见 sysroot-packages.md。

## 4. libm.a 静态库冲突
问题：sysroot 中 libm.a 来自板子 Debian glibc，引用了 `__frexp`/`__ldexp` 等内部符号，与交叉编译器不兼容。
修复：
```bash
rm sysroot/usr/lib/aarch64-linux-gnu/libm.a
# 同时将 libm.so 绝对路径软链接改为相对路径：
cd sysroot/usr/lib/aarch64-linux-gnu
ln -sfn libm.so.6 libm.so
```
