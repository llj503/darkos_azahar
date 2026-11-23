#!/usr/bin/env bash
# B 方案：在 amd64 Debian trixie chroot 里编 Azahar Qt 前端
# 目标：宿主工具、目标库、glibc 全部同一发行版，避免 2.43 符号问题。
set -euo pipefail

ROOT=/root/trixie-amd64
SRC_IN=/root/azahar-build/azahar
SRC_OUT=$ROOT/build-src/azahar
LOG=/mnt/e/darkos4rk3562/.workbuddy/chroot_build.log
OUT=/mnt/e/darkos4rk3562/.workbuddy/out

exec >>"$LOG" 2>&1
echo "===== $(date) 开始 ====="

# 1. debootstrap（幂等）
if [ ! -x "$ROOT/bin/bash" ]; then
	echo "== debootstrap trixie amd64"
	command -v debootstrap >/dev/null || { apt-get -y update -qq && apt-get -y install -qq debootstrap; }
	debootstrap --arch=amd64 --variant=minbase trixie "$ROOT" http://deb.debian.org/debian
fi

cp -f /etc/resolv.conf "$ROOT/etc/resolv.conf"
echo 'deb http://deb.debian.org/debian trixie main' > "$ROOT/etc/apt/sources.list"

for d in proc dev sys; do
	mountpoint -q "$ROOT/$d" || mount --bind "/$d" "$ROOT/$d"
done

# 2. 装工具链 + 双架构 Qt
chroot "$ROOT" bash -lc '
set -e
export DEBIAN_FRONTEND=noninteractive
dpkg --add-architecture arm64 2>/dev/null || true
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential cmake ninja-build git python3 ca-certificates pkg-config \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu \
  qt6-base-dev qt6-base-dev-tools qt6-base-private-dev qt6-multimedia-dev libqt6opengl6-dev \
  qt6-base-dev:arm64 qt6-base-private-dev:arm64 qt6-multimedia-dev:arm64 libqt6opengl6-dev:arm64 \
  libgl-dev libglx-dev libopengl-dev libegl-dev libgles-dev \
  libgl-dev:arm64 libglx-dev:arm64 libopengl-dev:arm64 libegl-dev:arm64 libgles-dev:arm64 \
  file
echo "== chroot 依赖安装完成"
'

# 3. 拷源码（已打好补丁）
mkdir -p "$ROOT/build-src"
if [ ! -d "$SRC_OUT" ]; then
	echo "== 拷贝源码"
	cp -a "$SRC_IN" "$SRC_OUT"
	rm -rf "$SRC_OUT"/build "$SRC_OUT"/build-* 2>/dev/null || true
fi

# 4. 配置 + 编译
chroot "$ROOT" bash -lc '
set -e
cd /build-src/azahar
rm -rf build-qt && mkdir build-qt && cd build-qt
cmake .. -G Ninja \
  -DCMAKE_SYSTEM_NAME=Linux -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
  -DCMAKE_C_COMPILER=aarch64-linux-gnu-gcc \
  -DCMAKE_CXX_COMPILER=aarch64-linux-gnu-g++ \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/usr/lib/aarch64-linux-gnu/cmake \
  -DENABLE_QT=ON -DENABLE_LIBRETRO=OFF -DENABLE_SDL2=ON \
  -DENABLE_QT_TRANSLATION=OFF -DENABLE_QT_UPDATE_CHECKER=OFF \
  -DENABLE_TESTS=OFF -DENABLE_LTO=OFF -DCITRA_WARNINGS_AS_ERRORS=OFF \
  -DCMAKE_CXX_FLAGS="-DUSING_GLES" \
  -DCMAKE_EXE_LINKER_FLAGS="-static-libstdc++ -static-libgcc" > /tmp/cm.log 2>&1 || { tail -30 /tmp/cm.log; exit 1; }
echo "== cmake ok"
ninja -k 0 -j"$(nproc)" azahar > /tmp/nb.log 2>&1 || { grep -m5 "error:" /tmp/nb.log; exit 1; }
echo "== ninja ok"
aarch64-linux-gnu-strip bin/Release/azahar
'

# 5. 取出产物
cp "$SRC_OUT/build-qt/bin/Release/azahar" "$OUT/azahar-qt-arm64-chroot"
cd "$OUT"
ls -lh azahar-qt-arm64-chroot
sha256sum azahar-qt-arm64-chroot
aarch64-linux-gnu-readelf -V azahar-qt-arm64-chroot 2>/dev/null | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -2 || true
echo "===== $(date) DONE ====="
