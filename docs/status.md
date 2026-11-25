# 移植现状（2026-11-25）

设备：AISLPC AIS，4.3 英寸 1024×768，RK3562，Debian 13 trixie，glibc 2.41，Mali G52（libmali）。设备已通过 SSH 实机测试；固定 Azahar 版本 2126.2。`/home/ark/.config/.DEVICE` 仍保留旧的 `RG52MINI` 值，设备树型号为 `AISLPC AIS`。

## A. libretro 核心（暂缓）

来源：`azahar-emu/azahar` 2126.2 + `rk3566_core_builds` 的 31 个补丁（000–029、034），无 PGO。

| 项 | 结果 |
|---|---|
| 交叉编译 | 成功，AArch64，47 MB（strip 后） |
| 依赖 | 仅 libc / libm / ld-linux（libstdc++ 静态） |
| glibc 上限 | 2.38 ✅ |
| 设备加载 | 成功，`Using HW render, vulkan driver forced.` |
| 设备运行 | `SET_GEOMETRY 1280x640` → 1.34 s 后 `Unhandled SIGSEGV` |

崩溃点紧接 NWM 初始化之后，与上游已知的“SIGTERM 退出崩溃”不是同一处。按用户选择暂缓，不在本轮继续排查。后续可选方向：

1. 按上游配方重编：trixie clang-19 + PGO（`scripts/ns-chroot.sh` 的 `NS_XTOOL=1` 环境已验证）。
2. 对 31 个补丁二分。
3. 比对 mamaich 的 `azahar_libretro.so` 与本项目构建参数。

## B. Qt 前端（当前可用路径）

| 项 | 结果 |
|---|---|
| 交叉编译 | trixie chroot，aarch64 gcc 14.2 + arm64 Qt 6.8.2，成功 |
| 产物 | `azahar-qt`，39 MB PIE，GLIBC 上限 2.38 |
| SHA256 | `f1cb4b2088a1a878d0e08e5d13a858c32b514f3375a0a73f0f40fa542449317a` |
| 运行包 | `azahar-qt-bundle-2126.2.tar.zst`，59 MB（解压 153 MB），108 个库、12 个 Qt 插件 |
| 运行包 SHA256 | `3e9e3211a4a5b9a1c22f7902616fd2907d515d8c0fc1d05eb8560589229683d8` |
| qemu 验证 | glibc 2.41 下 `ldd` 零缺项；三个平台插件可加载 |
| 设备启动 | 成功进入《新超级马里奥兄弟2 黄金版 汉化版》 |
| 显示 | AISLPC AIS 4.3 英寸 1024×768，Wayland + Weston kiosk |
| 渲染 | OpenGL ES 3.2，ARM / Mali-G52 |
| 声音 | ALSA PCM `RUNNING`，`Playback Path=SPK` |
| OSD | 原生 Wayland 子表面叠在 GL 画面上；短按 Select 反复开关、长按退出、方向高亮跟手、游戏画面不闪；L1/R1（及 X/Y）切换 Main/Video/Audio/System/Controls 页；自动菜单操作触发读档并成功恢复；Exit 确认后结束独立会话并恢复 ES |
| 槽位 1 存档 | 原始约 309 MB，压缩约 20 MB，保存约 16.9 秒，峰值约 800 MB |
| 槽位 1 读档 | 约 12.9 秒，峰值约 738 MB，`Load completed`，无临时文件残留 |
| 手柄 GUID | `1900a4dd726b333536322d6a6f797300`，SDL 确认 `controller=true` |
| 旧退出 | Select+Start 成功终止 Azahar |
| 恢复 | ES、killer_daemon、ogage 均 `active`；Weston/Azahar 无遗留；音频仍为 `SPK` |
| ES 配置 | 已安装 `/usr/local/bin/3ds.sh`，活动配置及 `.sd1/.sd2/.dual` 三个模板均保留 retroarch/azahar 并新增 azahar-qt；Qt 复用原解密包装 |
| Vulkan | 未验证；生产启动器固定 OpenGL |

关键实现：

- `device/azahar-qt.sh` 通过 transient systemd service 停 ES、起 `/opt/vita3k/weston`，再以 `ark` 运行 Azahar。
- `device/3ds.sh` 在 ES 的 Qt 分支复用 `azahar-dec.sh`，并把 `AZAHAR_USER_DIR` 指向 Qt 的 `share/azahar-emu`，避免解密包装把 NAND/SDMC 写到 RetroArch 目录。
- 数据目录为 `share/azahar-emu`，配置为 `config/azahar-emu/qt-config.ini`，内部日志为 `share/azahar-emu/log/azahar_log.txt`。
- `src/citra_qt/osd_overlay.*` 实现透明游戏内 OSD：短按 Select 开关、长按 600 ms 退出、存档/读档、视频/音频/系统设置、每游戏覆盖和确认页。
- OSD 菜单输入直读内核 evdev（按名称定位 `rk3562-joystick`，独立线程 poll+read，原子缓存按键/摇杆），不经过 SDL，也不消费核心输入；通过 frame limiter 暂停/恢复，不停止 `EmuThread`。游戏本身输入仍走 SDL。
- OSD 使用 `WA_NativeWindow` + `WA_DontCreateNativeAncestors` 成为原生 Wayland 子表面。普通子 QWidget 在同级原生 `OpenGLRenderWidget` 存在时首次能画、之后收不到 `paintEvent`，这是“高亮不动”的真正原因；改用原生子表面后每次仅 `repaint()`，避免重建成闪烁。
- 翻页：L1 / X 上一页，R1 / Y 下一页（Main、Video、Audio、System、Controls 循环）。
- 每游戏设置为 `config/azahar-emu/custom/<TitleID>.ini`；启用时不写全局配置。
- `src/core/savestate.cpp` 和 `src/common/zstd_compression.*` 改为流式序列化、Zstandard 压缩/解压和原子替换，解决 RK3562 存档 OOM。
- 完整 evemu 能力记录包含标准手柄键码和 Trigger Happy 键码；D-pad raw index 已从旧的 13–16 修正为 26–29。ABXY 保持设备约定的 A=Linux 305、B=Linux 304。
- 构建脚本自动应用 `azahar-qt-wayland-gles.patch`、`azahar-qt-streaming-savestate.patch` 和 `azahar-qt-osd.patch`。
- 临时 SDL 识别日志、SDL pump 心跳诊断、自动读档诊断代码和虚拟手柄均已移除；OSD 的逐键日志、心跳、绘制日志和 2 秒 fd 重开也已移除。设备 `instant_debug_log` 已恢复 false，`run.sh` 为仓库干净启动器。

剩余项：

- 实体手柄 ABXY 方位、手感、方向键、摇杆和扳机仍需人工确认。OSD 的 Select 反复开关、方向/摇杆高亮跟手、L1/R1 翻页、画面不闪已实机确认。
- OSD 设置修改、每游戏覆盖创建/删除/重建、Restart 确认需继续实机验证。
- 实际听感未验证，只有 PCM 与输出路径证据。
- Vulkan + `/opt/vita3k/wsi` 未验证。
- ES 前端的选择界面与实际按键导航需在掌机上人工确认；命令入口和设备侧返回 ES 链路单独验证。

流程、部署和完整验证记录见 [qt-frontend.md](qt-frontend.md)。

## 经过的弯路

- **WSL + Ubuntu 交叉工具链**：链接时 `-lm` 命中 Ubuntu 的 libm（2.43），产物 glibc 上限 2.43，设备无法加载。改为同一 trixie 发行版内编译后消失。
- **WSL root chroot**：改为免 root 的用户命名空间 chroot，避免 WSL 重启丢挂载。
- **SDL 没有音频后端**：未安装 `libasound2-dev:arm64` 时，SDL 会静默编成没有音频后端的版本；构建依赖已补上。
- **Qt Multimedia ffmpeg 后端**：会拉入整套解码库，多约 95 MB；只服务摄像头，故不带。
- **桌面 OpenGL 初始失败**：Qt 可能先报告 0 个桌面 OpenGL 配置，再回退 GLES 3.2；实机可正常创建 surface，不是黑屏原因。
- **Linux 304 被误认为 A**：设备映射下它是 SDL B；真正的 A 是 Linux 305。
- **GUID 误判**：vendor/product 为 0 不代表 GUID 以 0 开头；设备 bus 为 0x19，名称 CRC 为 `a4dd`，正确 GUID 保持 `1900a4dd...`。
- **按键能力表不完整**：只看 `BTN_TRIGGER_HAPPY*` 会漏掉标准手柄键码，导致 D-pad raw index 错为 13–16；完整记录显示标准键码在前，应为 26–29。
- **存档 OOM**：完整状态先进入内存字符串再压缩，峰值约 1.4 GB；改为文件流式处理，峰值降到约 800 MB。
- **core 直接依赖 zstd 头文件**：core 没有该 include/link 边界；流式实现移到 `common/zstd_compression.*`。
- **诊断日志看似缺失**：Info 日志默认缓冲，SIGKILL 会丢失；调试时临时开启即时日志，正式版已恢复。
- **查看错日志文件**：Qt stderr 在 `logs/azahar-qt.log`，Azahar 内部日志在 `share/azahar-emu/log/azahar_log.txt`。
- **OSD 按键偶发失灵**：现象是 Select 第一次能弹菜单、之后弹不出。逐层排查证明 OSD 逻辑/定时器正常、内核 evdev 始终投递按键、无进程独占手柄、设备无 runtime PM；根因是 SDL 手柄轮询间歇停摆（实测停过约 7 分钟，`raw_select` 恒 false、摇杆恒 0，按键后才恢复），且四次受控复现均未再触发，难以定点根除。改为 OSD 菜单直读 evdev 绕开 SDL，菜单按键不再受 SDL 停摆影响。
- **OSD 高亮不动被误判为输入丢失**：evdev 日志显示按键到达且 `MoveSelection` 已执行，但选择从 0 变到 3 时没有任何 `paintEvent`。真正原因是普通子 QWidget 被同级的原生 `OpenGLRenderWidget` 遮挡，首次绘制后不再收到绘制事件。改为 `WA_NativeWindow` 原生 Wayland 子表面后解决。
- **原生 OSD 初期切页/移动时画面闪**：每次移动都 `hide(); show();` 会重建 Wayland 子表面并扰动 GL 画面；只保留 `repaint()` 后高亮跟手且画面稳定。
