#!/usr/bin/env bash
# 重配 + 重编 Azahar Qt 前端（宿主 moc 已切回 Debian 6.8.2）
set -e
cd /root/azahar-build/azahar
rm -rf build-qt
mkdir build-qt
cd build-qt
cmake .. -G Ninja -DCMAKE_TOOLCHAIN_FILE=/root/azahar-build/toolchain-trixie.cmake \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH=/root/trixie-sysroot/usr/lib/aarch64-linux-gnu/cmake \
  -DQT_HOST_PATH=/usr \
  -DENABLE_QT=ON -DENABLE_LIBRETRO=OFF -DENABLE_SDL2=ON \
  -DENABLE_QT_TRANSLATION=OFF -DENABLE_QT_UPDATE_CHECKER=OFF \
  -DENABLE_TESTS=OFF -DENABLE_LTO=OFF -DCITRA_WARNINGS_AS_ERRORS=OFF \
  -DCMAKE_CXX_FLAGS='-DUSING_GLES -fno-math-errno' \
  -DCMAKE_EXE_LINKER_FLAGS='-static-libstdc++ -static-libgcc' > /mnt/e/darkos4rk3562/.workbuddy/qt_cmake.log 2>&1

echo "== cmake ok, 开始编译 =="
ninja -k 0 -j"$(nproc)" azahar > /mnt/e/darkos4rk3562/.workbuddy/qt_build4.log 2>&1 || {
	echo "== 编译失败 =="
	grep -m5 'error:' /mnt/e/darkos4rk3562/.workbuddy/qt_build4.log
	exit 1
}

ls -la bin/Release/azahar
cp bin/Release/azahar /mnt/e/darkos4rk3562/.workbuddy/out/azahar-qt-arm64
cd /mnt/e/darkos4rk3562/.workbuddy/out
ls -lh azahar-qt-arm64
sha256sum azahar-qt-arm64
aarch64-linux-gnu-readelf -h azahar-qt-arm64 | grep -E 'Machine|Type'
aarch64-linux-gnu-readelf -V azahar-qt-arm64 | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -2
echo DONE
