#!/bin/bash
# dArkOS 的 3DS 启动入口，装到 /usr/local/bin/3ds.sh。EmulationStation 以
# "3ds.sh %EMULATOR% %ROM%" 调用（es_systems 里 3ds 的 command，见 docs/qt-frontend.md）。
#
#   %EMULATOR% 为空或 retroarch  走 RetroArch 的 azahar_libretro 核心（原来的做法）
#   %EMULATOR% 为 azahar-qt       走 Azahar Qt 前端（/opt/azahar），保留原有按需解密

case "$1" in
azahar-qt)
	partition=$(dirname "$2" | cut -d/ -f2)
	[ -n "$partition" ] || partition=roms
	export AZAHAR_BIN=/opt/azahar/run.sh
	export AZAHAR_USER_DIR="/$partition/3ds/azahar/share/azahar-emu"
	exec /usr/local/bin/azahar-dec.sh "$2"
	;;
"" | retroarch | azahar)
	exec nice -n -19 /usr/local/bin/retroarch -L /home/ark/.config/retroarch/cores/azahar_libretro.so "$2"
	;;
*)
	echo "3ds.sh: 未知的模拟器 '$1'（可用：retroarch、azahar-qt）" >&2
	exit 1
	;;
esac
