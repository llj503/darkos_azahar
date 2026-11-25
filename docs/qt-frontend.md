# Qt 前端：构建、打包、设备运行

Azahar 自带的 Qt 前端（`azahar-qt`），不经过 RetroArch。交叉编译在 x86_64 Debian/Ubuntu 上完成，不需要 root。

**状态（2026-11-25）**：固定版本 2126.2 的 Qt 前端、游戏内 OSD 和低内存流式存档已在 AISLPC AIS（4.3 英寸 1024×768，RK3562 / Debian 13 / glibc 2.41 / Mali G52）上运行。测试 ROM 为《新超级马里奥兄弟2 黄金版 汉化版》：标题菜单可进入关卡，ALSA PCM 为 `RUNNING`；槽位 1 保存和读档均已实机通过。OSD 可反复开关、方向高亮跟手、L1/R1 切页且游戏画面不闪；实体按键手感仍待人工确认。

## 构建与打包

```sh
scripts/ns-chroot.sh setup amd64          # trixie 用户命名空间 chroot
scripts/build-azahar-qt.sh build          # 全量构建
scripts/build-azahar-qt.sh resume         # 中断后续编
scripts/make-azahar-qt-bundle.sh repack   # 库已取好，只重新算闭包并打包
```

两棵树都在 `~/darkos-build/`（可用 `DARKOS_BUILD` 修改）：

- `ns-chroot.sh`：免 root 的 trixie chroot，chown 走 subuid，`/proc` 和 `/dev` 在命名空间内绑定。
- `build-azahar-qt.sh`：用 trixie 的 aarch64 gcc 14.2 和 arm64 Qt 6.8.2 构建。chroot 内源码位于 `trixie-amd64/build-src/azahar`，`resume` 不会重新同步宿主机源码树。
- 构建脚本自动应用 Wayland/GLES、流式存档和 OSD 三个补丁。
- `make-azahar-qt-bundle.sh`：从二进制和 Qt 插件计算 NEEDED 闭包；有解析不到的库时直接失败，不生成缺库包。

正式二进制：

- 文件：`out/azahar-qt-arm64-2126.2`
- 大小：39 MB，AArch64 PIE
- SHA256：`f1cb4b2088a1a878d0e08e5d13a858c32b514f3375a0a73f0f40fa542449317a`
- GLIBC 上限：2.38（设备为 2.41）
- NEEDED：Qt6 Widgets/Multimedia/Gui/DBus/Concurrent/Core、libm、libmvec、libc、ld-linux

运行包约 59 MB，解压约 153 MB，包含 108 个库和 12 个 Qt 插件。运行包 SHA256 为 `3e9e3211a4a5b9a1c22f7902616fd2907d515d8c0fc1d05eb8560589229683d8`。库以 SONAME 放在 `lib/`，由启动器设置 `LD_LIBRARY_PATH`；哈希同时记录在 `out/azahar-qt-bundle-2126.2.txt`。

不带入运行包的库：

- glibc：使用设备的 glibc 2.41 和加载器。
- 图形驱动：使用设备镜像中的 libmali。不要用 trixie 的 mesa EGL/GLES/gbm/Wayland EGL 覆盖设备的符号链接。
- GLVND：`libOpenGL`、`libGLX`、`libGLdispatch` 来自 trixie；`libQt6Gui` 需要 `libOpenGL`，设备包清单里没有 `libopengl0`。
- Qt Multimedia ffmpeg 后端：只服务摄像头，会额外拉入整套编解码库；本项目不使用摄像头，故不带。

## 部署

```sh
sudo tar -xf azahar-qt-bundle-2126.2.tar.zst -C /opt   # 得到 /opt/azahar/
sudo install -m 755 device/3ds.sh /usr/local/bin/3ds.sh
```

`/opt/azahar/` 包含 `azahar-qt`、`run.sh`、`lib/`、`qt-plugins/`、`fonts.conf`、`fonts/` 和 `LIBS.txt`。

Weston 使用设备已有的 `/opt/vita3k/weston`，不需要安装 `weston` 包。启动器通过 transient systemd service 运行：停止 ES、取得 DRM master、启动 Weston kiosk，再以 `ark` 用户运行 Azahar。不要只给 Weston 加 sudo，否则会丢失 `XDG_RUNTIME_DIR` 等环境。

## 显示路径

生产启动器固定使用 Wayland：

- QPA：`QT_QPA_PLATFORM=wayland`
- Weston：`drm-backend.so` + `kiosk-shell.so`
- 旋转：写入 Weston 的 `[output] transform`，不是 Qt 的 eglfs 旋转
- 当前设备：`SCREEN_ROTATION=0`、`transform=normal`

Qt 首先尝试桌面 OpenGL 时可能报告 0 个配置，随后回退到 GLES 3.2 并成功创建 EGL surface；这不是黑屏根因。实机内部日志确认：

```text
GL_VERSION: OpenGL ES 3.2
GL_VENDOR: ARM
GL_RENDERER: Mali-G52
Renderer_GraphicsAPI: OpenGL
```

`run.sh` 将 `[Renderer] graphics_api` 固定为 OpenGL。Vulkan 需要 Wayland/X11，并依赖 `/opt/vita3k/wsi` 的 libmali WSI layer；本项目尚未验证 Vulkan，不把它作为默认路径。

## 数据、配置与日志

启动器按 ROM 所在分区选择数据根目录，例如 `/roms/3ds/azahar`：

- 数据：`share/azahar-emu`
- 配置：`config/azahar-emu/qt-config.ini`
- 每游戏覆盖：`config/azahar-emu/custom/<16位大写 TitleID>.ini`
- 存档：`share/azahar-emu/states/<16位大写 TitleID>.<两位槽位>.cst`
- 缓存：`cache/azahar-emu`
- Qt/Weston 日志：`logs/azahar-qt.log`、`logs/weston.log`
- Azahar 内部日志：`share/azahar-emu/log/azahar_log.txt`

`run.sh` 会写入 OpenGL 设置和 `dArkOS` 输入 profile。调试时若看内部日志没有及时刷新，可临时启用 `[Debugging] instant_debug_log=true`，同时把 `instant_debug_log\default` 设为 false；Info 日志默认会被缓冲，强制 SIGKILL 可能丢失未刷新内容。

## 游戏内 OSD

OSD 是 `GRenderWindow` 上的透明原生子表面（`WA_NativeWindow` + `WA_DontCreateNativeAncestors`），通过 `QPainter` 绘制。`GRenderWindow` 内部的原生 `OpenGLRenderWidget` 会遮挡普通同级 QWidget，首次绘制后不再产生 `paintEvent`（表现为选择已变化但高亮不动）；成为原生 Wayland 子表面后可稳定叠在 GL 画面上方。状态变化只调用 `repaint()`，不重建表面，因此游戏画面不会闪。菜单输入直读内核 evdev：按名称定位 `rk3562-joystick`（当前为 `/dev/input/event4`），独立线程 `poll`+`read`，用原子量缓存按键与摇杆状态，再包装成 `Input::ButtonDevice`/`AnalogDevice` 供 16 ms 定时器轮询。这样菜单不经过 SDL，也不消费核心手柄事件；打开时只暂停帧推进，不停止 `EmuThread`。游戏本身输入仍走 SDL。

改用 evdev 的原因：SDL 手柄轮询会偶发停摆（实测停过约 7 分钟），导致 Select 第一次能弹菜单、之后弹不出；而内核 evdev 始终正常投递按键。直读 evdev 让菜单按键不受 SDL 停摆影响。键码映射：Select=BTN_SELECT(314)、Start=BTN_START(315)、A=BTN_EAST(305)、B=BTN_SOUTH(304)、X=BTN_NORTH(307)、Y=BTN_WEST(308)、L1=BTN_TL(310)、R1=BTN_TR(311)、方向键=BTN_DPAD_*(544–547)，摇杆=ABS_X/ABS_Y。注意本设备物理 A/B 与标准手柄相反，与启动器 SDL 映射 `a:b1,b:b0` 一致。

- 短按 Select：打开/关闭菜单。
- 长按 Select 600 ms：退出游戏。
- D-pad 或左摇杆：导航；左/右调整选项；A：确认；B：返回。
- L1 或 X：上一页；R1 或 Y：下一页（Main、Video、Audio、System、Controls 循环）。
- 主菜单：Resume、Save/Load State、State Slot 1–10、Video、Audio、System、Controls、每游戏覆盖、Restart、Exit。
- Video：内部Resolution、Screen Layout、Swap Screens、Frame Limit、Shader Cache。
- Audio：Volume、Audio Stretching、Realtime Audio。
- System：New 3DS Mode、CPU Clock、Region。
- 存档界面槽位 1–10 对应核心普通槽位 0–9；核心槽位 0 保留给 Quick Save。
- 每游戏覆盖启用后，设置写入 `custom/<TitleID>.ini`，不调用全局 `config->Save()`；删除和重建逻辑已实现。
- Restart/Exit 有确认页；恢复游戏前会等待导航按钮和摇杆释放。

已通过自动菜单操作验证：OSD 打开、Load State 请求、核心读档、OSD 恢复，以及 Exit 确认后结束独立会话并恢复 ES。Restart/Exit 确认页默认选中第一个可执行项，避免按 A 落在说明行上。设置保存、每游戏覆盖和 Restart 还需要进一步实机操作验证。

## 低内存流式存档

RK3562 设备约 2 GB 内存且无 swap。原实现先把完整状态序列化到 `std::ostringstream`，再一次性压缩，峰值曾超过 1.4 GB 并触发 OOM。现在：

1. 原始状态流式写入 `.cst.tmp`。
2. 通过 `Common::Compression::CompressDataZSTD` 分块压缩到 `.cst.tmp-compressed`。
3. 压缩成功后原子 rename 为最终 `.cst`。
4. 读档先流式解压到 `.cst.tmp`，再用 `iarchive` 直接反序列化。
5. 临时文件由 RAII 清理，失败不会覆盖旧存档。

`.cst` 格式和 CSTHeader 不变，压缩时提供 pledged source size。`SaveStateBuffer` / `LoadStateBuffer` 仍保留原向量接口，供暂停的 libretro 路线使用。

《新超级马里奥兄弟2 黄金版 汉化版》槽位 1 实机结果：

| 项 | 结果 |
|---|---|
| 原始状态 | 308,921,412 字节（约 309 MB） |
| 压缩存档 | 20,001,256 字节（约 20 MB） |
| 保存耗时 | 约 16.9 秒 |
| 保存进程峰值 | 约 800 MB |
| 读档耗时 | 约 12.9 秒 |
| 读档进程峰值 | 约 738 MB |
| 结果 | `Save completed` / `Load completed`，无 OOM、无 `.tmp` 残留 |

## 手柄

Azahar 的 SDL 直接读取 evdev，Weston/libinput 不参与手柄事件。设备 GUID 为：

```text
1900a4dd726b333536322d6a6f797300
```

GUID 的 CRC 部分为 `a4dd`，由设备名 `rk3562-joystick` 计算；bus 为 `0x19`，vendor/product 为 0 时 GUID 尾部保存设备名前 12 字节。实机诊断确认 SDL 以 `controller=true` 打开设备，正式版不保留该临时诊断日志。

完整 evemu 能力记录同时包含标准 `BTN_SOUTH` 等键码和 `BTN_TRIGGER_HAPPY*` 键码。SDL Linux 后端先扫描 `>= BTN_JOYSTICK` 的键，因此 D-pad 的 raw button index 是 26–29，而不是旧的 13–16。当前 `run.sh` 的 raw mapping 为：

```text
a:b1,b:b0,x:b2,y:b3,back:b8,start:b9,guide:b10,misc1:b17,
leftstick:b11,rightstick:b12,dpup:b26,dpdown:b27,dpleft:b28,dpright:b29,
leftshoulder:b4,rightshoulder:b5,lefttrigger:a2,righttrigger:a5,
leftx:a0,lefty:a1,rightx:a3,righty:a4
```

Azahar profile 使用标准 SDL controller 编号：A=0、B=1、X=2、Y=3、Back=4、Guide=5、Start=6、L=9、R=10、方向键=11–14、Misc1=15；扳机使用轴 4/5，Circle Pad 和 C-Stick 使用轴 0/1 与 2/3。OSD 的 Select 对应 Back，A/B/X/Y 和方向键使用相同标准编号。

## 声音与退出

- 音频：`SDL_AUDIODRIVER=alsa`。实机 `/proc/asound/card0/pcm0p/sub0/status` 为 `RUNNING`，`Playback Path` 为 `SPK`。
- 旧退出方式：按住 Select（Linux 314）再按 Start（315），由 `killer_daemon` 终止 Azahar。
- OSD 退出方式：长按 Select 600 ms，或在 Exit Game 确认页选择 Yes。
- `run.sh` 清理 Weston、恢复 CPU/GPU/DMC governor、重启 `killer_daemon` 和 `ogage`、启动 ES，并恢复亮度与音频路径。

## EmulationStation 集成

仓库中的 `device/3ds.sh` 支持 `%EMULATOR%=azahar-qt`，为空或 `retroarch`/`azahar` 时仍走原 libretro 核心。Qt 分支设置 `AZAHAR_BIN=/opt/azahar/run.sh` 和 `AZAHAR_USER_DIR=<ROM 所在分区>/3ds/azahar/share/azahar-emu` 后调用设备原有的 `azahar-dec.sh`，因此保留 CIA 解密、更新/DLC 安装和字库处理，并让它们写入 Qt 自己的 NAND/SDMC。

设备 `/etc/emulationstation/es_systems.cfg` 的 3DS system 使用以下配置。该 ES 会在启动时按 SD 卡模式从 `es_systems.cfg.sd1`、`.sd2` 或 `.dual` 覆盖活动文件，因此三个模板也已同步修改；修改前备份为同名 `.pre-azahar-qt-20261125`：

```xml
<command>sudo perfmax %GOVERNOR% %ROM%; nice -n -19 /usr/local/bin/3ds.sh %EMULATOR% %ROM%; sudo perfnorm</command>
<emulators>
	<emulator name="retroarch">
		<cores>
			<core>azahar</core>
		</cores>
	</emulator>
	<emulator name="azahar-qt" />
</emulators>
```

在 ES 的 3DS 游戏启动选择中选 `azahar-qt` 即可进入 Qt 前端；独立会话中 OSD 的 Exit 确认和长按 Select 会结束 Azahar 进程，`run.sh` 随后恢复 ES。非独立会话仍保留原来的 Qt 游戏列表行为。

## 实机验证结果与剩余项

已在设备上验证：

- 最终二进制 SHA256 与上述一致，启动器能进入 ROM `0004000000137E00` 并初始化 DSP/audio。
- Wayland + Weston kiosk + OpenGL ES 3.2 / Mali-G52 显示正常。
- OSD 可叠加在游戏画面，自动菜单操作可触发并完成读档。
- OSD 可反复开关；方向键/摇杆切换选项时高亮跟手，游戏画面不闪。
- L1/R1 切页已实机确认：日志中 310/311 分别对应上一页/下一页，Main、Video、Audio、System、Controls 循环正常。
- 正式版已移除 OSD 逐键/心跳/绘制诊断日志和 2 秒 fd 重开；设备 `instant_debug_log` 恢复 false。
- 槽位 1 保存和读档通过，内存峰值约 800 MB / 738 MB，无 OOM、无临时文件残留。
- ALSA PCM `RUNNING`，输出路径 `SPK`。
- 旧 Select+Start 退出可恢复 ES、killer_daemon、ogage 和音频路径。
- OSD Exit 确认已自动验证：Azahar 进程结束，transient session 变为 inactive，ES 恢复 active。
- ES XML 校验通过并已重启加载；活动配置及三个 SD 卡模板都保留 `azahar-qt`。使用 ES 的 `3ds.sh azahar-qt` 命令链实机启动正式二进制成功，停止会话后 ES 恢复。

仍需人工或后续测试确认：

- 实体手柄的 ABXY 方位、手感、方向键、摇杆和扳机仍需人工确认；实体长按 Select 退出尚未人工验证。
- OSD 设置修改、每游戏覆盖创建/删除/重建、Restart 确认需继续实机验证。
- 实际听感与音量。
- Vulkan + `/opt/vita3k/wsi` 的性能与稳定性。
- ES 前端选择器的实际按键导航需在掌机上人工确认；设备配置和命令链已验证。
