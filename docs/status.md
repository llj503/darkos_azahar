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

## C. trixie chroot

已建 `/root/trixie-amd64`，安装双架构 Qt 6.8.2 + aarch64 交叉 gcc，cmake 配置通过。
ninja 编译被 WSL 反复重启打断（WSL 空闲会重启，chroot 的 /proc /dev /sys 绑定随之失效）。

恢复方法：

```sh
mount --bind /proc /root/trixie-amd64/proc
mount --bind /dev  /root/trixie-amd64/dev
mount --bind /sys  /root/trixie-amd64/sys
chroot /root/trixie-amd64 bash -lc 'cd /build-src/azahar/build-qt && ninja azahar'
```

## 已验证：per-core 配置

```
[INFO] [Override] Core-specific overrides found at ".../config/Azahar/Azahar.cfg"
[INFO] [Environ] GET_PREFERRED_HW_RENDER, video driver: "vulkan"
[INFO] [Video] Using HW render, vulkan driver forced.
```

全局 `retroarch.cfg` 是 `video_driver = "gl"`，说明覆盖生效。加上
`savefiles_in_content_dir = "false"` 后用户目录从 `/roms/3ds/Azahar/` 移到
`~/.config/retroarch/saves/Azahar/`。
