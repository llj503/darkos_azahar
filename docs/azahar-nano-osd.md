# azahar-nano 的 OSD 菜单结构

来源：`GammaOSNext-RG52mini/frameworks/base/cmds/azahar-nano/`

| 文件 | 作用 |
|---|---|
| `Overlay.cpp`（63 KB） | 菜单渲染主体 |
| `NanoInput.cpp` | 手柄输入 |
| `TouchCursor.cpp` | 摇杆驱动指针 |
| `Hud.cpp` | 状态浮层 |
| `AzaharSettings.cpp` | 设置读写 + 每游戏覆盖 |

## 菜单模型

- **Page**：顶层页（继续游戏 / 存读档 / 退出）+ 选项页（Video 等）+ 金手指页
- **Row**：`ROW_ACTION` / `ROW_CHOICE` / `ROW_PAGE`
- 页面导航用栈（`mStack`），支持从子页返回

## 设置与每游戏覆盖

- 全局：Android 属性 `persist.gammaos.azahar_nano.*` + 核心 `config.ini`
- 每游戏：`<user folder>/overrides/<rom 基名>.cfg`，一行一个 `key=value`
  - 属性用短键：`lcd_top=4`
  - 核心配置用 `Section/key`：`Renderer/resolution_factor=2`
- 覆盖生效期间**读写都走覆盖文件，绝不写全局**，崩溃或断电不会污染默认值
- 写入在工作线程合并，退出时 flush

## 对应到 dArkOS 的实现建议

| Android | dArkOS |
|---|---|
| `Overlay.cpp` | 自绘 OSD 叠层（DRM/Wayland），参照 `vita3k-osd` |
| `NanoInput.cpp` | `azahar-pad.py`：evdev 读 + `/dev/uinput` 注入 |
| `TouchCursor.cpp` | 摇杆转指针（Vita3K 同款） |
| `AzaharSettings` | `/roms/3ds/azahar/overrides/<rom>.cfg` |
| `Hud.cpp` | 帧率/电量/温度浮层 |
