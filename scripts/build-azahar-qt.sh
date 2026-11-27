#!/usr/bin/env bash
# 交叉编译 Azahar Qt 前端：在 trixie-amd64 chroot 里用 aarch64 交叉 gcc 和 arm64 Qt 6.8.2。
# 宿主工具、目标库、glibc 同属 trixie，产物 GLIBC 上限低于设备的 2.41。
#
# 用法：
#   build-azahar-qt.sh deps     # chroot 里加 arm64 架构并装依赖（幂等）
#   build-azahar-qt.sh build    # 装依赖、取源码、配置、全量编译、取产物
#   build-azahar-qt.sh resume   # 中断后续编
#   build-azahar-qt.sh collect  # 取产物并打印 GLIBC 上限与依赖
#
# 环境：DARKOS_BUILD、AZAHAR_TAG（默认 2126.2）、OUT_DIR、JOBS
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="${DARKOS_BUILD:-$HOME/darkos-build}"
TAG="${AZAHAR_TAG:-2126.2}"
SRC="$BASE/src/azahar"
SRC_IN_CHROOT=/build-src/azahar
OUT="${OUT_DIR:-$BASE/out}"
ARTIFACT="$OUT/azahar-qt-arm64-$TAG"
LOG="$BASE/logs/build-qt.log"
JOBS="${JOBS:-$(nproc)}"

# libasound2-dev:arm64：内嵌的 SDL2、cubeb、OpenAL 在编译期探测音频后端，没有 ALSA 开发包
# 就一个都探测不到，编出来的前端没有声音。
DEPS="gcc-aarch64-linux-gnu g++-aarch64-linux-gnu pkg-config qt6-base-dev-tools \
	qt6-base-dev:arm64 qt6-base-private-dev:arm64 qt6-multimedia-dev:arm64 libqt6opengl6-dev \
	libgl-dev:arm64 libglx-dev:arm64 libopengl-dev:arm64 libegl-dev:arm64 libgles-dev:arm64 \
	libasound2-dev:arm64 libxext-dev:arm64"

# 在 chroot 内执行；输出同时写日志。
ns() {
	mkdir -p "$BASE/logs"
	"$ROOT/scripts/ns-chroot.sh" run amd64 "$@" 2>&1 | tee -a "$LOG"
	return "${PIPESTATUS[0]}"
}

deps() {
	export DARKOS_BUILD="$BASE" JOBS="$JOBS"
	ns bash -c 'export DEBIAN_FRONTEND=noninteractive
		dpkg --add-architecture arm64
		apt-get update -qq
		apt-get install -y -qq --no-install-recommends '"$DEPS"'
		aarch64-linux-gnu-g++ --version | head -1'
}

# 与之前在 WSL chroot 里跑通的配置一致，另加了 ALSA 与 aarch64 库目录（见 CMAKE_CMD）。
# 多架构 chroot 不是 sysroot：CMAKE_LIBRARY_ARCHITECTURE 让 find_library 去
# /usr/lib/aarch64-linux-gnu 找，PKG_CONFIG_LIBDIR 让 pkg-config 不落到 amd64 的包上。
CMAKE_CMD='export PKG_CONFIG_LIBDIR=/usr/lib/aarch64-linux-gnu/pkgconfig:/usr/share/pkgconfig
	cmake .. -G Ninja \
	-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
	-DCMAKE_LIBRARY_ARCHITECTURE=aarch64-linux-gnu \
	-DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_PREFIX_PATH=/usr/lib/aarch64-linux-gnu/cmake \
	-DENABLE_QT=ON -DENABLE_LIBRETRO=OFF -DENABLE_SDL2=ON -DENABLE_OPENGL=ON \
	-DENABLE_QT_TRANSLATION=OFF -DENABLE_QT_UPDATE_CHECKER=OFF \
	-DENABLE_TESTS=OFF -DENABLE_LTO=ON -DCITRA_WARNINGS_AS_ERRORS=OFF \
	-DCMAKE_C_FLAGS="-DUSING_GLES -march=armv8-a -moutline-atomics -fno-math-errno" \
	-DCMAKE_CXX_FLAGS="-DUSING_GLES -march=armv8-a -moutline-atomics -fno-math-errno" \
	-DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc"'

build() {
	deps
	mkdir -p "$BASE/src" "$OUT"
	if [ ! -d "$SRC/.git" ]; then
		git clone --recursive --depth=1 --shallow-submodules -b "$TAG" \
			https://github.com/azahar-emu/azahar.git "$SRC"
	fi
	# 拷贝在宿主机上做：chroot 里看不到宿主机的路径
	if [ ! -d "$BASE/trixie-amd64$SRC_IN_CHROOT" ]; then
		mkdir -p "$BASE/trixie-amd64$(dirname "$SRC_IN_CHROOT")"
		cp -a "$SRC" "$BASE/trixie-amd64$SRC_IN_CHROOT"
	fi
	if ! grep -Fq 'Setting<bool> use_gles{true' "$BASE/trixie-amd64$SRC_IN_CHROOT/src/common/settings.h"; then
		ns patch -Np1 -d "$SRC_IN_CHROOT" < "$ROOT/patches/azahar-qt-wayland-gles.patch"
	fi
	if ! grep -Fq 'CompressDataZSTD(std::istream' "$BASE/trixie-amd64$SRC_IN_CHROOT/src/common/zstd_compression.h"; then
		ns patch -Np1 -d "$SRC_IN_CHROOT" < "$ROOT/patches/azahar-qt-streaming-savestate.patch"
	fi
	if [ ! -f "$BASE/trixie-amd64$SRC_IN_CHROOT/src/citra_qt/osd_overlay.cpp" ]; then
		ns patch -Np1 -d "$SRC_IN_CHROOT" < "$ROOT/patches/azahar-qt-osd.patch"
	fi
	export DARKOS_BUILD="$BASE" JOBS="$JOBS"
	ns bash -c "set -e; cd $SRC_IN_CHROOT; rm -rf build-qt; mkdir build-qt; cd build-qt
		$CMAKE_CMD > /tmp/cmake.log 2>&1 || { echo '== cmake 失败'; tail -40 /tmp/cmake.log; exit 1; }
		echo '== cmake ok'
		ninja -k 0 -j\$JOBS azahar > /tmp/ninja.log 2>&1 || { echo '== ninja 失败'; grep -E 'FAILED:|error:' /tmp/ninja.log | head -20; exit 1; }
		echo '== ninja ok'" || exit 1
	collect
}

resume() {
	export DARKOS_BUILD="$BASE" JOBS="$JOBS"
	ns bash -c "set -e; cd $SRC_IN_CHROOT/build-qt
		ninja -k 0 -j\$JOBS azahar > /tmp/ninja.log 2>&1 || { echo '== ninja 失败'; grep -E 'FAILED:|error:' /tmp/ninja.log | head -20; exit 1; }
		echo '== ninja ok'" || exit 1
	collect
}

collect() {
	local rel="$SRC_IN_CHROOT/build-qt/bin/Release/azahar"
	export DARKOS_BUILD="$BASE"
	"$ROOT/scripts/ns-chroot.sh" run amd64 aarch64-linux-gnu-strip -o "$rel.stripped" "$rel"
	cp "$BASE/trixie-amd64$rel.stripped" "$ARTIFACT"
	local glibc needed
	# 宿主机可能是中文 locale，readelf 的字段名会被翻译
	export LC_ALL=C
	glibc=$(readelf -V "$ARTIFACT" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -1)
	needed=$(readelf -d "$ARTIFACT" | sed -n 's/.*(NEEDED).*\[\(.*\)\]/\1/p' | tr '\n' ' ')
	{
		echo "产物: $ARTIFACT"
		ls -lh "$ARTIFACT"
		sha256sum "$ARTIFACT"
		readelf -h "$ARTIFACT" | grep -E 'Class|Machine|Type'
		echo "GLIBC 上限: $glibc（设备 2.41）"
		echo "NEEDED: $needed"
	} | tee -a "$LOG"
}

case "${1:-}" in
deps) deps ;;
build) build ;;
resume) resume ;;
collect) collect ;;
*)
	sed -n '2,11p' "$0" | sed -E 's/^# ?//' >&2
	exit 2
	;;
esac
