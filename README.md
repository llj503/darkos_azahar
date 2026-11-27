# darkos_azahar

Azahar（Nintendo 3DS）在 dArkOS / RK3562 上的移植记录与构建脚本。

移植思路来自两个上游：

- [mamaich/dArkOS_rg52mini](https://github.com/mamaich/dArkOS_rg52mini)：libretro 核心的完整配方（2126.2 + 31 个补丁 + PGO），实测 60 fps
- [mamaich/GammaOSNext-RG52mini](https://github.com/mamaich/GammaOSNext-RG52mini)：Android 版 azahar-nano，含 OSD 菜单设计

## 三条路线

| 路线 | 形态 | 现状 |
|---|---|---|
| A. libretro 核心 | RetroArch 加载 `azahar_libretro.so` | 能编、能加载、Vulkan 正常，运行约 1.3 s 后 SIGSEGV（按用户选择暂缓） |
| B. 独立 Qt 前端 | `azahar-qt` + Wayland/Weston | **AISLPC AIS 实机通过**：可进入关卡、ALSA PCM `RUNNING`；游戏内 OSD 可反复开关，L1/R1 翻页，支持简体中文 / English 即时切换（系统页，持久化到 `osd.ini`），存档/读档、设置和每游戏覆盖可用；Video 页可在 Vulkan/OpenGL 间切换图形接口（写全局配置，重启游戏生效），Vulkan 经 `/opt/vita3k/wsi` 隐式 WSI 层实机验证，并可在 libmali/malisx2 两种 Vulkan 驱动间切换（malisx2 需预装，默认 libmali）；Video 页可视化自定义布局编辑器可拖动/缩放双屏并保存全局布局，画布超出 1024×768 时自动等比缩放居中、双屏完整显示；可为布局黑边选择自定义背景图片，保存在 `backgrounds/` 目录并在游戏画面下方居中裁剪绘制；Video 页「显示帧率」开启后，菜单关闭时右上角显示实时 FPS 角标（写 `osd.ini` 的 `[ui] show_fps`，重启保持）；OSD 退出后恢复 ES；ES 的 3DS 系统可选择 `azahar-qt`（见 [docs/qt-frontend.md](docs/qt-frontend.md)） |

已验证可用、与核心无关的部分：

- Qt 正式版：Mali-G52 / OpenGL ES 3.2 显示，PCM `RUNNING`，Select+Start 退出后 ES、killer_daemon、ogage 和 `SPK` 输出恢复
- OSD 界面支持简体中文 / English：系统页「界面语言」即时切换，写入 `osd.ini` 的 `[ui] language`，退出重启游戏后仍保持
- FPS 显示：Video 页「显示帧率」开关写入 `osd.ini` 的 `[ui] show_fps`；开启后返回游戏时右上角常驻半透明角标，每 500 ms 刷新，菜单打开（暂停）时自动隐藏，重启游戏后自动恢复
- per-core 配置 `config/Azahar/Azahar.cfg`：让 RetroArch 只对 Azahar 用 Vulkan，不需要 `--appendconfig` 包装
- Vulkan ICD 默认选 libmali（不是 malisx2）：Azahar 在 malisx2 上慢 13–20%；OSD 视频页「Vulkan 驱动」可在 libmali/malisx2 间切换，2026-11 用 malisx2 0.6.1 实机跑通 Vulkan 进游戏与 OSD 操作

Qt 路线剩余人工体验项，详见 [docs/status.md](docs/status.md)。

## 目录

```
config/Azahar/Azahar.cfg      # 每核心 RetroArch 覆盖配置（已验证）
docs/status.md                # 移植现状与实测数据
docs/qt-frontend.md           # Qt 前端：构建、运行包、设备部署与验证清单
docs/gcc-compat.md            # 用 gcc 编 2126.2 需要改的三处
docs/azahar-nano-osd.md       # azahar-nano 的 OSD 菜单结构分析
device/                        # 设备文件：azahar-qt.sh（Weston 启动器，安装为 /opt/azahar/run.sh）
scripts/ns-chroot.sh          # 免 root 的 trixie chroot（用户命名空间）
scripts/build-azahar-qt.sh    # 交叉编译 Qt 前端
scripts/make-azahar-qt-bundle.sh  # 连同 Qt 运行库打成设备运行包
scripts/build-azahar-libretro.sh  # libretro 核心（仍是 WSL 版本，路径待改）
```

## 构建（Qt 前端）

在 Debian/Ubuntu 上，不需要 root：

```sh
scripts/ns-chroot.sh setup amd64
scripts/build-azahar-qt.sh build
scripts/make-azahar-qt-bundle.sh
```

Qt 独立端关键参数（2026-11-27 起启用 LTO）：

```
-DENABLE_LTO=ON                    # CMake 映射为 -flto=auto -fno-fat-lto-objects
-march=armv8-a -moutline-atomics   # A53 只有 ARMv8.0，不能有 LSE 指令
-fno-math-errno                    # 避免 sqrtf 等绑定到 GLIBC_2.43
-static-libstdc++ -static-libgcc
```

产物在 `~/darkos-build/out/`：`azahar-qt-arm64-2126.2` 和 `azahar-qt-bundle-2126.2.tar.zst`。LTO 正式二进制 SHA256 为 `d32558c016b6636e036592c710f4df5df07bc812813b6e2d6f945970ce32911b`，运行包 SHA256 为 `a6145ae77f092c8ae7594ae7421625c6bcb32b5190dcda9e6a52009372bbbcfb`。部署与 EmulationStation 配置见 [docs/qt-frontend.md](docs/qt-frontend.md)。

## 构建（libretro 核心）

```sh
bash scripts/build-azahar-libretro.sh
```

依赖：Debian/Ubuntu + aarch64 交叉 gcc、Debian trixie sysroot（glibc 2.41）、上游 PGO profile。
产物需满足 `GLIBC <= 2.41`，否则在 Debian 13 设备上无法加载。

关键参数：

```
-march=armv8-a -moutline-atomics   # A53 只有 ARMv8.0，不能有 LSE 指令
-fno-math-errno                    # 避免 sqrtf 等绑定到 GLIBC_2.43
-static-libstdc++ -static-libgcc
```

## 上游关键结论

- 官方 aarch64 包不能用：ARMv8.1/LSE 指令在 A53 上 SIGILL
- 核心沿用 clang + PGO；LTO 在 PGO 之上没有额外收益且需要 lld，因此核心保持 `ENABLE_LTO=OFF`；Qt 独立端单独启用 GCC LTO
- `ENABLE_OPENGL=ON` + `-DUSING_GLES`，否则 RetroArch 的 gl 驱动起不来
- 存档走 zstd 流式（patch 012），加载不预问尺寸（RetroArch patch 0024），否则每次读档先序列化整个 292 MB 状态
- 纹理上传环从 512 MiB 降到 128 MiB（patch 028），Mali 驱动不可换出，省 345 MB
