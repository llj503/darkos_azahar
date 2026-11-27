#!/usr/bin/env bash
# 把 azahar-qt 打成设备上解压即用的运行包：二进制 + 私有 libs/ + Qt 插件 + 启动脚本。
#
# 闭包里的库都取自 trixie 的 arm64 包，所以不依赖设备镜像装了哪些包。
# 不带两类库：glibc（必须用设备的加载器）和图形驱动（设备上 libEGL、libGLESv2、
# libgbm 都是 libmali 的符号链接，带上 mesa 的会把它盖掉）。
#
# 用法：
#   make-azahar-qt-bundle.sh          # 取包、算闭包、打包
#   make-azahar-qt-bundle.sh repack   # 库已取好，只重新算闭包并打包
#
# 环境：DARKOS_BUILD、AZAHAR_TAG、OUT_DIR、BUNDLE_ROOT_PKGS（追加的 arm64 运行库包）
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="${DARKOS_BUILD:-$HOME/darkos-build}"
TAG="${AZAHAR_TAG:-2126.2}"
OUT="${OUT_DIR:-$BASE/out}"
BIN="$OUT/azahar-qt-arm64-$TAG"
STAGE="$BASE/bundle"
DEBS="$BASE/trixie-amd64/var/cache/azahar-debs"
POOL="$STAGE/pool"
BUNDLE="$STAGE/azahar"
# 宿主机通用的 readelf 即可；中文 locale 下它的字段名会被翻译，统一用 C locale
export LC_ALL=C

# 闭包的起点包（Debian 的 Qt 插件分散在几个包里）：
#   libqt6widgets6 libqt6concurrent6   azahar-qt 直接依赖的运行库
#   libqt6opengl6                      eglfs 平台插件和它的设备后端
#   qt6-wayland                        wayland 平台插件和 shell integration
#   qt6-svg-plugins                    svg 图标
#   libqt6multimedia6                  azahar-qt 链接了它；不带它的 ffmpeg 后端；
#                                      后端只为摄像头输入服务，会把整套编解码库拉进来
#   librtmp1                           见下面的 EXTRA_LIBS
#   fonts-dejavu-core                   运行包自带的西文字体，见 resolve 里对 fontconfig 的处理
#   libopengl0                          GLVND 的 libOpenGL，libQt6Gui 链接了它；镜像的包清单里没有
ROOT_PKGS="libqt6widgets6 libqt6concurrent6 libqt6opengl6 qt6-wayland qt6-svg-plugins libqt6multimedia6 librtmp1 fonts-dejavu-core libopengl0 ${BUNDLE_ROOT_PKGS:-}"
# 不在 NEEDED 链上、运行时被 dlopen 的库：libproxy 的后端需要 librtmp（librtmp1 在取包列表里）
EXTRA_LIBS="librtmp.so.1 ${BUNDLE_EXTRA_LIBS:-}"

fetch() {
	[ -f "$BIN" ] || { echo "没有 $BIN，先运行 scripts/build-azahar-qt.sh" >&2; exit 1; }
	mkdir -p "$DEBS/partial"
	export DARKOS_BUILD="$BASE"
	# 读空的 status 文件并令 arm64 为主架构：已经装过的依赖也会被下载，
	# 结果只取决于 trixie 的包关系，与 chroot 里装了什么无关
	"$ROOT/scripts/ns-chroot.sh" run amd64 bash -c "
		apt-get update -qq
		cd /var/cache/azahar-debs
		apt-get install -y -qq --no-install-recommends --download-only \
			-o APT::Architecture=arm64 -o Dir::State::status=/dev/null \
			-o Dir::Cache::archives=/var/cache/azahar-debs $ROOT_PKGS"
}

# 解到 pool；files.txt 是文件清单：包名<TAB>相对 pool 的路径
extract() {
	rm -rf "$POOL"
	mkdir -p "$POOL"
	: >"$STAGE/files.txt"
	local deb name
	for deb in "$DEBS"/*.deb; do
		name=$(basename "$deb" .deb)
		dpkg-deb -c "$deb" | awk -v p="$name" '!d && $1 !~ /^d/ {print p "\t" substr($6, 3)}' >>"$STAGE/files.txt"
		dpkg-deb -x "$deb" "$POOL"
	done
	echo "已解包 $(wc -l <"$STAGE/files.txt") 个文件，来自 $(ls "$DEBS"/*.deb | wc -l) 个包"
}

# 算闭包并摆好目录。任何 NEEDED 都解析不到就报错退出，不给出一个缺库的包。
resolve() {
	rm -rf "$BUNDLE"
	mkdir -p "$BUNDLE/libs" "$BUNDLE/qt-plugins"
	cp "$BIN" "$BUNDLE/azahar-qt"
	install -m 755 "$ROOT/device/azahar-qt.sh" "$BUNDLE/run.sh"
	# Qt 的文字全靠 fontconfig。镜像里有没有 fontconfig 的配置文件不确定，没有它 Qt 一个字也画不出来，
	# 所以自带配置和一个西文字体；设备上装的字体照常扫描
	mkdir -p "$BUNDLE/fonts"
	cp "$POOL"/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf "$BUNDLE/fonts/"
	cat >"$BUNDLE/fonts.conf" <<'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
	<dir>/usr/share/fonts</dir>
	<dir>/usr/local/share/fonts</dir>
	<dir>/opt/azahar/fonts</dir>
	<cachedir prefix="xdg">fontconfig</cachedir>
</fontconfig>
EOF
	python3 - "$STAGE" "$BUNDLE" "$ROOT_PKGS" "$EXTRA_LIBS" <<'PY'
import os, re, shutil, subprocess, sys

stage, bundle = sys.argv[1], sys.argv[2]
root_pkgs, extra = set(sys.argv[3].split()), sys.argv[4].split()
pool = os.path.join(stage, "pool")
skip = re.compile(
    r"^(ld-linux|libc\.so|libm\.so|libmvec|libgcc_s\.so|libpthread\.so|libdl\.so|librt\.so|libresolv\.so|libutil\.so|libanl\.so|libBrokenLocale|libSegFault"
    r"|libEGL\.so|libGLESv|libGL\.so|libgbm\.so|libglapi\.so|libvulkan\.so|libwayland-egl\.so)")

# 只带用得到的 Qt 插件：eglfs 与其设备后端、wayland 与其 shell integration、svg。
# xcb 和 linuxfb 会把各自整套依赖拉进来，窗口装饰插件用不到。
plugins = re.compile(r"qt6/plugins/(platforms/libq(eglfs|wayland-[a-z]+)\.so|egldeviceintegrations/libqeglfs-kms.*\.so"
                     r"|wayland-shell-integration/.*\.so|imageformats/libqsvg\.so|iconengines/.*\.so)$")

def elf(path):
    try:
        with open(path, "rb") as f:
            return f.read(4) == b"\x7fELF"
    except OSError:
        return False

def dynamic(path):
    out = subprocess.run(["readelf", "-d", path], capture_output=True, text=True).stdout
    soname = re.search(r"\(SONAME\).*\[(.*)\]", out)
    needed = re.findall(r"\(NEEDED\).*\[(.*)\]", out)
    return (soname.group(1) if soname else None), needed

# path -> 包；Qt 插件从起点包里选
owner, root_files = {}, {}
for line in open(os.path.join(stage, "files.txt")):
    pkg, path = line.rstrip("\n").split("\t")
    owner[path] = pkg
    if pkg.split("_")[0] in root_pkgs:
        root_files[path] = pkg

by_soname = {}
for d, _, fs in os.walk(pool):
    for f in fs:
        p = os.path.join(d, f)
        if elf(p):
            soname, _ = dynamic(p)
            if soname:
                by_soname.setdefault(soname, p)

seen, manifest, missing, queue = set(), [], {}, []
for path, pkg in sorted(root_files.items()):
    src = os.path.join(pool, path)
    if plugins.search(path) and os.path.isfile(src):
        rel = path.split("qt6/plugins/", 1)[1]
        dst = os.path.join(bundle, "qt-plugins", rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        manifest.append(f"{pkg}\tqt-plugins/{rel}")
        queue.append(dst)
queue.append(os.path.join(bundle, "azahar-qt"))

# 从 azahar-qt 和 Qt 插件出发，广度优先走 NEEDED；EXTRA_LIBS 作为另一组起点
def take(n, used_by):
    if n in seen or skip.match(n):
        return
    seen.add(n)
    src = by_soname.get(n)
    if not src:
        missing.setdefault(n, used_by)
        return
    # 以 SONAME 命名：加载器按这个名字找
    dst = os.path.join(bundle, "libs", n)
    if not os.path.exists(dst):
        shutil.copy2(src, dst)
        pkg = owner.get(os.path.relpath(src, pool), "?")
        manifest.append(f"{pkg}\tlibs/{n}")
        queue.append(dst)

queue.append(os.path.join(bundle, "azahar-qt"))
for n in extra:
    take(n, "EXTRA_LIBS")
while queue:
    path = queue.pop()
    _, needed = dynamic(path)
    for n in needed:
        take(n, os.path.basename(path))

if missing:
    print("闭包里解析不到的库（把提供它的 arm64 运行库包加进 BUNDLE_ROOT_PKGS）：")
    for n, used_by in sorted(missing.items()):
        print(f"  {n}  <- {used_by}")
    sys.exit(1)
with open(os.path.join(bundle, "LIBS.txt"), "w") as f:
    f.write("# 运行包里的每个库来自哪个 trixie 包\n" + "\n".join(sorted(manifest, key=lambda s: s.split("\t")[1])) + "\n")
print(f"libs/ {len(os.listdir(os.path.join(bundle, 'libs')))} 个库，qt-plugins/ 下 "
      f"{sum(len(fs) for _, _, fs in os.walk(os.path.join(bundle, 'qt-plugins')))} 个插件")
PY
}

pack() {
	local tgz="$OUT/azahar-qt-bundle-$TAG.tar.zst"
	tar -C "$STAGE" --zstd -cf "$tgz" azahar
	{
		echo "运行包: $tgz"
		ls -lh "$tgz" "$BUNDLE/azahar-qt"
		sha256sum "$tgz"
		du -sh "$BUNDLE"
	} | tee "$OUT/azahar-qt-bundle-$TAG.txt"
}

case "${1:-all}" in
all) fetch && extract && resolve && pack ;;
repack) extract && resolve && pack ;;
*)
	sed -n '2,13p' "$0" | sed -E 's/^# ?//' >&2
	exit 2
	;;
esac
