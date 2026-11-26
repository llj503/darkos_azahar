# darkos_azahar

Azahar（Nintendo 3DS）在 dArkOS / RK3562 上的移植记录与构建脚本。

移植思路来自两个上游：

- [mamaich/dArkOS_rg52mini](https://github.com/mamaich/dArkOS_rg52mini)：libretro 核心的完整配方（2126.2 + 31 个补丁 + PGO），实测 60 fps
- [mamaich/GammaOSNext-RG52mini](https://github.com/mamaich/GammaOSNext-RG52mini)：Android 版 azahar-nano，含 OSD 菜单设计

## 三条路线

| 路线 | 形态 | 现状 |
|---|---|---|
| A. libretro 核心 | RetroArch 加载 `azahar_libretro.so` | 能编、能加载、Vulkan 正常，运行约 1.3 s 后 SIGSEGV（按用户选择暂缓） |
| B. 独立 Qt 前端 | `azahar-qt` + Wayland/Weston | **AISLPC AIS 实机通过**：可进入关卡、ALSA PCM `RUNNING`；游戏内 OSD 可反复开关，L1/R1 翻页，存档/读档、设置和每游戏覆盖可用；Video 页可视化自定义布局编辑器可拖动/缩放双屏并保存全局布局；OSD 退出后恢复 ES；ES 的 3DS 系统可选择 `azahar-qt`（见 [docs/qt-frontend.md](docs/qt-frontend.md)） |

已验证可用、与核心无关的部分：

- Qt 正式版：Mali-G52 / OpenGL ES 3.2 显示，PCM `RUNNING`，Select+Start 退出后 ES、killer_daemon、ogage 和 `SPK` 输出恢复
- per-core 配置 `config/Azahar/Azahar.cfg`：让 RetroArch 只对 Azahar 用 Vulkan，不需要 `--appendconfig` 包装
- Vulkan ICD 选 libmali（不是 malisx2）：Azahar 在 malisx2 上慢 13–20%

Qt 路线剩余人工体验和 Vulkan 验证项，详见 [docs/status.md](docs/status.md)。

## 目录

```
config/Azahar/Azahar.cfg      # 每核心 RetroArch 覆盖配置（已验证）
docs/status.md                # 移植现状与实测数据
docs/qt-frontend.md           # Qt 前端：构建、运行包、设备部署与验证清单
docs/gcc-compat.md            # 用 gcc 编 2126.2 需要改的三处
docs/azahar-nano-osd.md       # azahar-nano 的 OSD 菜单结构分析
device/                        # 设备文件：azahar-qt.sh（Weston 启动器）、3ds.sh（ES 入口）
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

产物在 `~/darkos-build/out/`：`azahar-qt-arm64-2126.2` 和 `azahar-qt-bundle-2126.2.tar.zst`。正式二进制 SHA256 为 `c4a30fc07d6108b6fb8e23af784f2af9a2d072d1959ed0db6ba38233fc92da62`，运行包 SHA256 为 `4d2baffde0ae4724af435a55af94491340dfb45818b9ab0acac2cab69d1fa308`。部署与 EmulationStation 配置见 [docs/qt-frontend.md](docs/qt-frontend.md)。

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
- `ENABLE_OPENGL=ON` + `-DUSING_GLES`，否则 RetroArch 的 gl 驱动起不来
- 存档走 zstd 流式（patch 012），加载不预问尺寸（RetroArch patch 0024），否则每次读档先序列化整个 292 MB 状态
- 纹理上传环从 512 MiB 降到 128 MiB（patch 028），Mali 驱动不可换出，省 345 MB
