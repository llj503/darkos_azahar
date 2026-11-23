#!/usr/bin/env bash
# 在 trixie chroot 内续跑 Azahar Qt 构建，并把日志写到 Windows 侧
set -u
ROOT=/root/trixie-amd64
LOG=/mnt/e/darkos4rk3562/.workbuddy/chroot_qt.log

for d in proc dev sys; do
	mountpoint -q "$ROOT/$d" || mount --bind "/$d" "$ROOT/$d" || true
done

exec >"$LOG" 2>&1
echo "===== $(date) 开始 ====="

chroot "$ROOT" /bin/bash -c '
set -e
cd /build-src/azahar/build-qt
ninja -k 0 -j"$(nproc)" azahar
echo "== ninja ok"
aarch64-linux-gnu-strip bin/Release/azahar
'

cp "$ROOT/build-src/azahar/build-qt/bin/Release/azahar" /mnt/e/darkos4rk3562/.workbuddy/out/azahar-qt-arm64-chroot
cd /mnt/e/darkos4rk3562/.workbuddy/out
ls -lh azahar-qt-arm64-chroot
sha256sum azahar-qt-arm64-chroot
aarch64-linux-gnu-readelf -V azahar-qt-arm64-chroot | grep -oE 'GLIBC_[0-9.]+' | sort -Vu | tail -2
echo "===== $(date) DONE ====="
