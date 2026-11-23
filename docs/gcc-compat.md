# 用 gcc 15 编 Azahar 2126.2 的三处改动

上游按 clang 编写，C++20 的指定初始化器与三元运算符在 gcc 下有更严格的检查。三处均为等价改写，不改行为。

## 1. `src/video_core/pica/pica_core.cpp` — 三元运算符类型不一致

```cpp
// 改前
const u32 first = header.group_commands ? header.cmd_id + 1 : header.cmd_id;
const u32 last  = header.group_commands ? header.cmd_id + header.extra_data_length
                                       : header.cmd_id;

// 改后
const u32 first = header.group_commands ? static_cast<u32>(header.cmd_id) + 1
                                       : static_cast<u32>(header.cmd_id);
const u32 last  = header.group_commands ? static_cast<u32>(header.cmd_id) + header.extra_data_length
                                       : static_cast<u32>(header.cmd_id);
```

## 2. `src/video_core/renderer_vulkan/vk_pipeline_cache.cpp` — 指定初始化器顺序

`Pica::Shader::Profile` 里 `fs_mediump` / `light_skip` / `no_shadow` / `light_max` 声明在
`vk_disable_spirv_optimizer` 之前，初始化列表顺序必须一致：

```cpp
.hw_scissor = Settings::values.gammaos_hw_scissor,
.fs_mediump = Settings::values.gammaos_fs_mediump,
.light_skip = GammaFsProp("light_skip"),
.no_shadow  = GammaFsPropInt("no_shadow_map"),
.light_max  = GammaFsPropInt("light_max"),
.vk_disable_spirv_optimizer = Settings::values.disable_spirv_optimizer.GetValue(),
.vk_use_spirv_generator = Settings::values.spirv_shader_gen.GetValue(),
```

## 3. `src/video_core/renderer_vulkan/vk_instance.cpp` — `vk::PhysicalDeviceFeatures` 顺序

按 Vulkan-Hpp 的声明顺序重排：

```cpp
.depthClamp = features.depthClamp,
.samplerAnisotropy = features.samplerAnisotropy,
.occlusionQueryPrecise = features.occlusionQueryPrecise,
.pipelineStatisticsQuery = features.pipelineStatisticsQuery,
.fragmentStoresAndAtomics = features.fragmentStoresAndAtomics,
.shaderClipDistance = features.shaderClipDistance,
```
