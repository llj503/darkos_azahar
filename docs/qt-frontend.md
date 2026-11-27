# Qt 前端：构建、打包、设备运行

Azahar 自带的 Qt 前端（`azahar-qt`），不经过 RetroArch。交叉编译在 x86_64 Debian/Ubuntu 上完成，不需要 root。

**状态（2026-11-26）**：固定版本 2126.2 的 Qt 前端、游戏内 OSD（简体中文界面）、可视化自定义布局编辑器、自定义背景图片和低内存流式存档已在 AISLPC AIS（4.3 英寸 1024×768，RK3562 / Debian 13 / glibc 2.41 / Mali G52）上运行。测试 ROM 为《新超级马里奥兄弟2 黄金版 汉化版》：标题菜单可进入关卡，ALSA PCM 为 `RUNNING`；槽位 1 保存和读档均已实机通过。OSD 可反复开关、方向高亮跟手、L1/R1 切页且游戏画面不闪；布局编辑器可拖动/缩放双屏矩形并保存为全局布局，画布超出窗口时由渲染器等比缩放居中、不会裁切；实体按键手感仍待人工确认。

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
- SHA256：`9a67d63c168c4bb8f0ec4e92d36df4aec00e65aa4c3b116ec562aee3448c7cc3`
- GLIBC 上限：2.38（设备为 2.41）
- NEEDED：Qt6 Widgets/Multimedia/Gui/DBus/Concurrent/Core、libm、libmvec、libc、ld-linux

运行包约 59 MB，解压约 153 MB，包含 108 个库和 12 个 Qt 插件。运行包 SHA256 为 `2240ad004ab39f31b66ce130503abfbca45b8483d9371d245ee3d6f9c0b05749`。库以 SONAME 放在 `lib/`，由启动器设置 `LD_LIBRARY_PATH`；哈希同时记录在 `out/azahar-qt-bundle-2126.2.txt`。

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

启动器不再固定 `[Renderer] graphics_api`：OSD 视频页「图形接口」可切换 OpenGL / Vulkan（写全局 `qt-config.ini`，同时写 `graphics_api\default=false`，否则 `default=true` 会把值强制回默认；重启游戏生效）。Vulkan 依赖 libvulkan + ICD `rk_vk.json`（libmali G52）和 `/opt/vita3k/wsi` 的隐式 WSI 层，启动器自动注入 `VK_ADD_IMPLICIT_LAYER_PATH=/opt/vita3k/wsi`；两条路径均已在 AISLPC AIS 上进入游戏并完成 OSD 反复开关、翻页验证，默认仍为 OpenGL。

Vulkan 下 OSD 只有首次打开能上屏是 Qt 6.8 Wayland 的问题：全屏 WSI 子表面遮挡主窗口后，Weston 不再回主窗口的 frame callback，Qt 6.8 超时（100 ms）后把主窗口标记为 inexposed；OSD 子表面的 `isExposed()` 取父窗口状态，因此重开时不再收到 expose，`QWidget` 不绘制、表面不 attach。启动器设置 `QT_WAYLAND_FRAME_CALLBACK_TIMEOUT=0` 关闭该超时后问题消失（该变量由 `QWaylandWindow` 构造函数读取，`0` 表示不启动超时定时器）。

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

OSD 是 `GRenderWindow` 上的透明原生子表面（`WA_NativeWindow` + `WA_DontCreateNativeAncestors`），通过 `QPainter` 绘制。`GRenderWindow` 内部的原生 `OpenGLRenderWidget` 会遮挡普通同级 QWidget，首次绘制后不再产生 `paintEvent`（表现为选择已变化但高亮不动）；成为原生 Wayland 子表面后可稳定叠在 GL 画面上方。状态变化只调用 `repaint()`，不重建表面，因此游戏画面不会闪。菜单输入直读内核 evdev：按名称定位 `rk3562-joystick`（当前为 `/dev/input/event4`），独立线程以非阻塞 `read` 直接解析事件，原子量缓存按键、摇杆和按下计数；16 ms 定时器轮询时把尚未处理的按下计数补放（最多 8 次），避免主线程绘制阻塞期间丢键。这样菜单不经过 SDL，也不消费核心手柄事件；打开时只暂停帧推进，不停止 `EmuThread`。游戏本身输入仍走 SDL。

改用 evdev 的原因：SDL 手柄轮询会偶发停摆（实测停过约 7 分钟），导致 Select 第一次能弹菜单、之后弹不出；而内核 evdev 始终正常投递按键。直读 evdev 让菜单按键不受 SDL 停摆影响。键码映射：Select=BTN_SELECT(314)、Start=BTN_START(315)、A=BTN_EAST(305)、B=BTN_SOUTH(304)、X=BTN_NORTH(307)、Y=BTN_WEST(308)、L1=BTN_TL(310)、R1=BTN_TR(311)、方向键=BTN_DPAD_*(544–547)，摇杆=ABS_X/ABS_Y。注意本设备物理 A/B 与标准手柄相反，与启动器 SDL 映射 `a:b1,b:b0` 一致。

- 短按 Select：打开/关闭菜单。
- 界面文案为简体中文；`run.sh` 的 fontconfig 会扫描设备 `/usr/share/fonts`，中文由 Noto Sans CJK SC 渲染（设备自带）。
- 长按 Select 600 ms：退出游戏。
- D-pad 或左摇杆：导航；左/右调整选项；A：确认；B：返回。
- L1 或 X：上一页；R1 或 Y：下一页（Main、Video、Audio、System、Controls 循环）。
- 主菜单：Resume、Save/Load State、State Slot 1–10、Video、Audio、System、Controls、每游戏覆盖、Restart、Exit。
- Video：内部Resolution、Screen Layout、Custom Layout Editor、背景图片、Swap Screens、Frame Limit、Shader Cache。
- Audio：Volume、Audio Stretching、Realtime Audio。
- System：New 3DS Mode、CPU Clock、Region。
- 存档界面槽位 1–10 对应核心普通槽位 0–9；核心槽位 0 保留给 Quick Save。
- 每游戏覆盖启用后，设置写入 `custom/<TitleID>.ini`，不调用全局 `Save()`；删除和重建逻辑已实现。
- Restart/Exit 有确认页；恢复游戏前会等待导航按钮和摇杆释放。

### 自定义布局编辑器

Screen Layout 选择 `Custom` 或进入 Video 页的 Custom Layout Editor 时，OSD 切换为布局编辑界面：屏幕上按 4:3 预览绘制上/下两个屏幕矩形（蓝色 TOP、琥珀色 BOTTOM），可实时拖动和缩放。

- D-pad 或左摇杆：移动当前矩形（每步 10 px，摇杆连续触发间隔 90 ms）。
- L1 / R1：宽度 −10 / +10 px；X / Y：高度 −10 / +10 px。
- A：切换编辑 TOP / BOTTOM；Start：恢复默认（TOP `0,0,800,480`，BOTTOM `240,480,320,240`）。
- B：保存并退出编辑器（菜单停留），写入全局 `[Layout] custom_*` 并应用；布局为全局一套，不随游戏保存。
- Select：保存并恢复游戏（长按仍为退出游戏）。

矩形坐标构成一块虚拟画布（最小 80×60、坐标非负、宽高上限 2048），渲染时 `Layout::CustomFrameLayout` 会把整块画布等比缩放并居中铺进 1024×768 窗口，所以画布超出屏幕也不会被裁切；编辑器右下角显示「画布 W x H  缩放 N%」，与实机画面一致。进入编辑器时会把当前 `layout_option` 切到 Custom（值 6，按每游戏覆盖规则写入），因此编辑器里拖动即时生效；B 保存时调用 `QtConfig::SaveCustomLayoutValues()` 写全局 `custom_*`。

### 自定义背景图片

Video 页「背景图片」可选一张图片填满布局黑边（例如双屏外的区域），选「关闭」恢复纯色清屏。图片放在数据目录的 `backgrounds/` 子目录（例如 `/roms/3ds/azahar/share/azahar-emu/backgrounds/`），支持 `png`、`jpg`、`jpeg`、`webp`、`bmp`，按文件名排序；该目录在 OSD 首次列出时自动创建。改动即时生效，无需重启游戏。

- 背景是全局设置，写在独立的 `config/azahar-emu/osd.ini` 的 `background/image`，不参与核心设置和每游戏覆盖。
- Qt 前端用 `QImage` 解码并转为 RGBX8888（透明像素按黑底合成，超过 2048 像素先等比缩小），再通过 `RendererBase::SetBackgroundImage` 交给渲染线程。
- `RendererOpenGL::DrawBackground` 在清屏之后、双屏之前绘制全屏四边形，按窗口宽高比居中裁剪（cover），因此 4:3、16:9 等图片都不会拉伸。
- 只有 OpenGL 后端实现；Vulkan 路径忽略该设置。

已通过自动菜单操作验证：OSD 打开、Load State 请求、核心读档、OSD 恢复，以及 Exit 确认后结束独立会话并恢复 ES。Restart/Exit 确认页默认选中第一个可执行项，避免按 A 落在说明行上。自定义布局编辑器已用虚拟手柄逐项验证：D-pad 连续移动、L1/R1 调宽、X/Y 调高、A 切换上下屏、摇杆拖动、B 保存、Start 重置均准确；保存后全局 `custom_*` 与每游戏 `layout_option=6` 均落盘。其余设置保存、每游戏覆盖删除/重建和 Restart 还需要进一步实机操作验证。

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
- 自定义布局编辑器实机验证通过：D-pad 多按逐次生效（右×3 → x=40、下×2 → y=30），L1/R1 宽度、X/Y 高度步进准确，A 切换 TOP/BOTTOM，摇杆拖动方向自然，B 保存后写入全局 `custom_*`，Start 恢复默认；每游戏覆盖保持 `layout_option=6`。
- 布局自适应验证：全局 `custom_*` 为 1710×1270 画布时，1024×768 下按 60% 缩放居中，运行日志实测布局矩形 top `(6,4–641,477)`、bottom `(641,477–1024,764)`，全部位于窗口内，无裁切。
- 自定义背景实机验证：1600×1200 测试图通过 OSD 选择后写入 `osd.ini`，启动日志出现 `OSD background image set`；帧缓冲回读 1024×768 左下角 `(122,61,30)`、右上角 `(27,42,74)`，与测试图对应角落颜色一致，证明背景已绘制、方向正确且在双屏之下。
- 中文界面逐页截图验证：主菜单、视频、音频、系统、操作说明、退出/重启确认页和布局编辑器均正常渲染，无缺字或截断。
- L1/R1 切页已实机确认：日志中 310/311 分别对应上一页/下一页，Main、Video、Audio、System、Controls 循环正常。
- 正式版已移除 OSD 逐键/心跳/绘制诊断日志和 2 秒 fd 重开；设备 `instant_debug_log` 恢复 false。
- 槽位 1 保存和读档通过，内存峰值约 800 MB / 738 MB，无 OOM、无临时文件残留。
- ALSA PCM `RUNNING`，输出路径 `SPK`。
- 旧 Select+Start 退出可恢复 ES、killer_daemon、ogage 和音频路径。
- OSD Exit 确认已自动验证：Azahar 进程结束，transient session 变为 inactive，ES 恢复 active。
- ES XML 校验通过并已重启加载；活动配置及三个 SD 卡模板都保留 `azahar-qt`。使用 ES 的 `3ds.sh azahar-qt` 命令链实机启动正式二进制成功，停止会话后 ES 恢复。

仍需人工或后续测试确认：

- 实体手柄的 ABXY 方位、手感、方向键、摇杆和扳机仍需人工确认；实体长按 Select 退出尚未人工验证。
- OSD 其他设置保存、每游戏覆盖删除/重建、Restart 确认需继续实机验证。
- 实际听感与音量。
- Vulkan 长时间运行的性能与稳定性。
- ES 前端选择器的实际按键导航需在掌机上人工确认；设备配置和命令链已验证。
