#!/usr/bin/env bash
# 无 root 的 Debian trixie chroot：在用户命名空间里建树并进入执行。
#
# 依赖 /etc/subuid、/etc/subgid 的范围（uidmap 包），所以 chown 和 dpkg 正常工作。
# /proc 属于初始命名空间，不能绑定：这里新建 PID 命名空间后挂自己的 /proc。
# mknod 被内核拒绝，/dev 用逐个绑定宿主机节点的方式补最小集合。
#
# 用法：
#   ns-chroot.sh setup <amd64|arm64>          # debootstrap（幂等）并写 sources.list
#   ns-chroot.sh run   <amd64|arm64> <cmd...> # chroot 内执行
#   ns-chroot.sh shell <amd64|arm64>          # chroot 内开 shell
#
# 环境：DARKOS_BUILD（根目录，默认 ~/darkos-build）、DEBIAN_MIRROR、DEBIAN_SECURITY_MIRROR
set -euo pipefail

BASE="${DARKOS_BUILD:-$HOME/darkos-build}"
MIRROR="${DEBIAN_MIRROR:-http://mirrors.tuna.tsinghua.edu.cn/debian}"
SECURITY_MIRROR="${DEBIAN_SECURITY_MIRROR:-http://mirrors.tuna.tsinghua.edu.cn/debian-security}"
DEV_NODES="null zero full random urandom tty"

usage() {
	sed -n '2,16p' "$0" | sed -E 's/^# ?//' >&2
	exit 2
}

# 在命名空间内执行 cmd...；mode 为 chroot 时先进入 root。
# 参数通过位置传入，函数体不引用宿主机的变量。
ns_exec() {
	local arch=$1 root=$2 mode=$3
	shift 3
	exec unshare -U -m -r --map-users auto --map-groups auto \
		--fork --pid --mount-proc="$root/proc" \
		env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY -u all_proxy -u ALL_PROXY \
		NS_XTOOL="${NS_XTOOL:-0}" \
		bash --noprofile --norc -c '
			set -e
			root=$1; mode=$2; nodes=$3; amd=$4; shift 4
			mount --make-rprivate /
			for n in $nodes; do
				[ -e "$root/dev/$n" ] || : >"$root/dev/$n"
				mountpoint -q "$root/dev/$n" || mount --bind "/dev/$n" "$root/dev/$n"
			done
			ln -sfn /proc/self/fd "$root/dev/fd"
			ln -sfn fd/0 "$root/dev/stdin"
			ln -sfn fd/1 "$root/dev/stdout"
			ln -sfn fd/2 "$root/dev/stderr"
			mkdir -p "$root/dev/pts" "$root/dev/shm"
			# ptmx 必须在 devpts 上，绑定宿主机的那个打不开
			[ -L "$root/dev/ptmx" ] || rm -f "$root/dev/ptmx"
			ln -sfn pts/ptmx "$root/dev/ptmx"
			mountpoint -q "$root/dev/pts" || mount -t devpts -o ptmxmode=0666,newinstance devpts "$root/dev/pts"
			mountpoint -q "$root/dev/shm" || mount -t tmpfs tmpfs "$root/dev/shm"
			chmod 1777 "$root/dev/shm"
			# NS_XTOOL=1：把 trixie-amd64 的 clang-19 和 amd64 运行库挂进来（同上游 xtool.sh），
			# 在 arm64 chroot 里原生运行 ${XTOOL_LLVM}/bin/aarch64-linux-gnu-clang
			if [ "${NS_XTOOL:-0}" = 1 ]; then
				xtool=/usr/lib/llvm-19-amd64
				[ -d "$amd/usr/lib/llvm-19" ] || { echo "没有 $amd/usr/lib/llvm-19" >&2; exit 1; }
				ln -sfn usr/lib/x86_64-linux-gnu "$root/lib64"
				mkdir -p "$root/usr/lib/x86_64-linux-gnu" "$root$xtool"
				mount --bind "$amd/usr/lib/x86_64-linux-gnu" "$root/usr/lib/x86_64-linux-gnu"
				mount --bind "$amd/usr/lib/llvm-19" "$root$xtool"
			fi
			if [ "$mode" = chroot ]; then exec chroot "$root" "$@"; fi
			exec "$@"' ns "$root" "$mode" "$DEV_NODES" "$BASE/trixie-amd64" "$@"
}

ns() {
	local arch=$1 root="$BASE/trixie-$1"
	[ -x "$root/bin/bash" ] || { echo "没有 $root，先运行: $0 setup $arch" >&2; exit 1; }
	ns_exec "$arch" "$root" chroot "${@:2}"
}

write_sources() {
	cat >"$1/etc/apt/sources.list" <<EOF
deb $MIRROR trixie main
deb $MIRROR trixie-updates main
deb $SECURITY_MIRROR trixie-security main
EOF
	cp -L /etc/resolv.conf "$1/etc/resolv.conf"
}

setup() {
	local arch=$1 root="$BASE/trixie-$1"
	if [ ! -x "$root/bin/bash" ]; then
		mkdir -p "$root/proc" "$root/dev"
		echo "== debootstrap trixie $arch -> $root"
		ns_exec "$arch" "$root" host debootstrap \
			--variant=minbase --arch="$arch" --no-check-gpg trixie "$root" "$MIRROR"
	fi
	write_sources "$root"
}

case "${1:-}" in
setup) setup "${2:-}" ;;
run)
	[ $# -ge 3 ] || usage
	ns "$2" "${@:3}"
	;;
shell)
	ns "${2:-}" bash -l
	;;
*) usage ;;
esac
