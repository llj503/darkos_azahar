# 移植现状（2026-11-23）

设备：RG52 Mini，RK3562，Debian 13 trixie，glibc 2.41，Mali G52（libmali）

## A. libretro 核心

来源：`azahar-emu/azahar` 2126.2 + `rk3566_core_builds` 的 31 个补丁（000–029、034），无 PGO。

| 项 | 结果 |
|---|---|
| 交叉编译 | 成功，AArch64，47 MB（strip 后） |
| 依赖 | 仅 libc / libm / ld-linux（libstdc++ 静态） |
| glibc 上限 | 2.38 ✅ |
| 设备加载 | 成功，`Using HW render, vulkan driver forced.` |
| 运行 | `SET_GEOMETRY 1280x640` → 1.34 s 后 `Unhandled SIGSEGV` |

崩溃点紧接 NWM 初始化之后，与上游已知的“SIGTERM 退出崩溃”不是同一处。待查方向：

1. 用 clang 交叉重编（排除 gcc 与 clang 的代码生成差异）
2. 对 31 个补丁二分
3. 比对 mamaich 的 `azahar_libretro.so` 与我们的构建参数差异

## B. Qt 前端

| 项 | 结果 |
|---|---|
| 交叉编译 | 成功，40 MB PIE，依赖 Qt6 Widgets/Multimedia/Gui/DBus/Concurrent |
| glibc 上限 | **2.43** ❌（设备 2.41） |
| 原因 | 链接时 `-lm` 优先命中 Ubuntu 交叉工具链的 libm（2.43），sysroot 的 2.41 排在后面；`-fno-math-errno` 未覆盖到全部对象 |

受影响符号：`sinhf acosf atan2f asinf sqrtf log10f`

## C. trixie chroot（已跑通）

| 项 | 结果 |
|---|---|
| 环境 | `/root/trixie-amd64`，debootstrap amd64 trixie，双架构 Qt 6.8.2 + aarch64 交叉 gcc |
| 配置 | cmake 通过（`CMAKE_PREFIX_PATH=/usr/lib/aarch64-linux-gnu/cmake`，无 sysroot 手工拼装） |
| 编译 | 成功，2246 个目标 |
| 产物 | `azahar-qt-arm64-chroot`，40 MB，sha256 `3a3908e059eca533…` |
| **glibc 上限** | **2.38** ✅（设备 2.41） |
| 依赖 | Qt6 Widgets / Multimedia / Gui / DBus / Concurrent / Core + libm / libmvec / libc |

同一发行版内编译后，之前所有 glibc 相关坑自然消失：moc 版本、libicu、libGLX、`sqrtf@GLIBC_2.43` 都不再出现。

### 断点续编

WSL 会空闲重启，chroot 的挂载会丢。恢复：

```sh
mount --bind /proc /root/trixie-amd64/proc
mount --bind /dev  /root/trixie-amd64/dev
mount --bind /sys  /root/trixie-amd64/sys
bash scripts/resume-azahar-qt-chroot.sh
```

从 Windows 调 WSL 跑脚本时必须加 `MSYS_NO_PATHCONV=1`，否则 Git Bash 会把 `/bin/bash` 转成 Windows 路径，报 127。

### 设备侧还需两件事

1. 补 `libQt6Multimedia.so.6`（镜像里只有 Qt6 Core/Gui/Widgets/Quick/WaylandClient/Svg/Network/DBus），它依赖 `libpulse.so.0`
2. 用 `QT_QPA_PLATFORM=eglfs` 直接跑，或走 Weston kiosk（Vita3K 同款）
