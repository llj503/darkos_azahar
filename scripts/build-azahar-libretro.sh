#!/usr/bin/env bash
# 本地编 mamaich 配方里的 Azahar libretro 核心（2126.2 + 补丁 000-029,034 + PGO）
# 仅用于对比调试，不改任何仓库。
set -euo pipefail

BUILD=/root/azahar-build
SRC=$BUILD/azahar
PATCHES=/mnt/e/darkos4rk3562/.workbuddy/tmp/core_builds/patches
PGO=/mnt/e/darkos4rk3562/.workbuddy/tmp/core_builds/pgo/azahar-nano-merged-20261020.profdata.gz
OUT=/mnt/e/darkos4rk3562/.workbuddy/out
TAG=2126.2

mkdir -p "$BUILD" "$OUT"
cd "$BUILD"

if [ ! -d "$SRC/.git" ]; then
	echo "== clone azahar $TAG"
	git clone --recursive --depth=1 --shallow-submodules -b "$TAG" \
		https://github.com/azahar-emu/azahar.git azahar
else
	echo "== reuse $SRC"
fi

cd "$SRC"
echo "== 清理上次的补丁残留"
rm -f azahar-patch* azahar.profdata

cp "$PATCHES"/azahar-patch* .
gunzip -c "$PGO" > azahar.profdata
sha256sum azahar.profdata

echo "== 应用补丁"
for p in $(ls azahar-patch* | sort); do
	echo "-- $p"
	if ! patch -Np1 < "$p" >/tmp/patch.out 2>&1; then
		echo "补丁失败: $p"
		cat /tmp/patch.out | head -20
		exit 1
	fi
	tail -3 /tmp/patch.out
	rm -f "$p"
done

echo "== cmake"
rm -rf build
mkdir build
cd build
PGOFLAGS="-fprofile-use=$SRC/azahar.profdata -Wno-profile-instr-unprofiled -Wno-profile-instr-out-of-date"
cmake .. -G Ninja \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_C_COMPILER=clang \
	-DCMAKE_CXX_COMPILER=clang++ \
	-DENABLE_LIBRETRO=ON \
	-DENABLE_OPENGL=ON \
	-DENABLE_VULKAN=ON \
	-DENABLE_TESTS=OFF \
	-DENABLE_LTO=OFF \
	-DCITRA_WARNINGS_AS_ERRORS=OFF \
	-DCMAKE_C_FLAGS="$PGOFLAGS" \
	-DCMAKE_CXX_FLAGS="-DUSING_GLES $PGOFLAGS"

echo "== ninja"
ninja -j"$(nproc)" citra_libretro

echo "== strip + 输出"
strip bin/Release/azahar_libretro.so
cp bin/Release/azahar_libretro.so "$OUT/azahar_libretro-src2126.2-pgo.so"
cd "$OUT"
sha256sum azahar_libretro-src2126.2-pgo.so
ls -lh azahar_libretro-src2126.2-pgo.so
echo "DONE"
