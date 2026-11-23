# darkos_azahar

Azahar（Nintendo 3DS）在 dArkOS / RK3562 上的移植记录与构建脚本。

移植思路来自两个上游：

- [mamaich/dArkOS_rg52mini](https://github.com/mamaich/dArkOS_rg52mini)：libretro 核心的完整配方（2126.2 + 31 个补丁 + PGO），实测 60 fps
- [mamaich/GammaOSNext-RG52mini](https://github.com/mamaich/GammaOSNext-RG52mini)：Android 版 azahar-nano，含 OSD 菜单设计

## 三条路线

| 路线 | 形态 | 现状 |
|---|---|---|
| A. libretro 核心 | RetroArch 加载 `azahar_libretro.so` | 能编、能加载、Vulkan 正常，运行 1.3 s 后 SIGSEGV（待查） |
| B. 独立 Qt 前端 | `azahar` 可执行 + eglfs/Weston | 能编出 aarch64 产物，但 glibc 要求 2.43 > 设备 2.41（待解决） |
| C. trixie chroot | 同一发行版内编 | 环境已建好，编译中断（WSL 反复重启） |

已验证可用、与核心无关的部分：

- per-core 配置 `config/Azahar/Azahar.cfg`：让 RetroArch 只对 Azahar 用 Vulkan，不需要 `--appendconfig` 包装
- Vulkan ICD 选 libmali（不是 malisx2）：Azahar 在 malisx2 上慢 13–20%

## 目录

```
config/Azahar/Azahar.cfg      # 每核心 RetroArch 覆盖配置（已验证）
docs/status.md                # 移植现状与实测数据
docs/gcc-compat.md            # 用 gcc 编 2126.2 需要改的三处
docs/azahar-nano-osd.md       # azahar-nano 的 OSD 菜单结构分析
scripts/                      # 构建脚本
```

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
