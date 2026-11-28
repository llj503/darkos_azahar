import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "."
os.chdir(ROOT)

# 三处 gcc/clang 差异修正（详见 docs/gcc-compat.md）

def patch(path, pairs):
    s = open(path, encoding="utf-8").read()
    for old, new in pairs:
        if new in s:
            print("skip(already):", path)
            return
        if s.count(old) != 1:
            print("FAIL match", path, s.count(old))
            sys.exit(1)
        s = s.replace(old, new)
    open(path, "w", encoding="utf-8", newline="\n").write(s)
    print("patched:", path)

patch("src/video_core/pica/pica_core.cpp", [(
"""            const u32 first = header.group_commands ? header.cmd_id + 1 : header.cmd_id;
            const u32 last = header.group_commands ? header.cmd_id + header.extra_data_length
                                                   : header.cmd_id;""",
"""            const u32 first = header.group_commands ? static_cast<u32>(header.cmd_id) + 1
                                                   : static_cast<u32>(header.cmd_id);
            const u32 last = header.group_commands ? static_cast<u32>(header.cmd_id) + header.extra_data_length
                                                   : static_cast<u32>(header.cmd_id);""")])

patch("src/video_core/renderer_vulkan/vk_pipeline_cache.cpp", [(
"""        .vk_disable_spirv_optimizer = Settings::values.disable_spirv_optimizer.GetValue(),
        // GammaOS: medium precision fragment shaders (both generators); in the profile so the
        // disk shader cache regenerates when it is switched.
        .fs_mediump = Settings::values.gammaos_fs_mediump,
        .light_skip = GammaFsProp("light_skip"),
        .no_shadow = GammaFsPropInt("no_shadow_map"),
        .light_max = GammaFsPropInt("light_max"),""",
"""        // GammaOS: medium precision fragment shaders (both generators); in the profile so the
        // disk shader cache regenerates when it is switched.
        .fs_mediump = Settings::values.gammaos_fs_mediump,
        .light_skip = GammaFsProp("light_skip"),
        .no_shadow = GammaFsPropInt("no_shadow_map"),
        .light_max = GammaFsPropInt("light_max"),
        .vk_disable_spirv_optimizer = Settings::values.disable_spirv_optimizer.GetValue(),""")])

patch("src/video_core/renderer_vulkan/vk_instance.cpp", [(
"""                .samplerAnisotropy = features.samplerAnisotropy,
                .fragmentStoresAndAtomics = features.fragmentStoresAndAtomics,
                .depthClamp = features.depthClamp,
                .occlusionQueryPrecise = features.occlusionQueryPrecise,
                .pipelineStatisticsQuery = features.pipelineStatisticsQuery,
                .shaderClipDistance = features.shaderClipDistance,""",
"""                .depthClamp = features.depthClamp,
                .samplerAnisotropy = features.samplerAnisotropy,
                .occlusionQueryPrecise = features.occlusionQueryPrecise,
                .pipelineStatisticsQuery = features.pipelineStatisticsQuery,
                .fragmentStoresAndAtomics = features.fragmentStoresAndAtomics,
                .shaderClipDistance = features.shaderClipDistance,""")])
