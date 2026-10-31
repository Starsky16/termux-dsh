#!/data/data/com.termux/files/usr/bin/bash
#
# Flutter 的 Linux 宿主工具（arm64 但 glibc 链接）在 Termux 原生跑不了：
#   impellerc / gen_snapshot / flutter_tester / dartaotruntime 都依赖 /lib/ld-linux-aarch64.so.1
# arm64 架构对得上，缺的只是 glibc 运行时 ⇒ 用 proot + 一份 arm64 rootfs 直接执行（无 CPU 模拟）。
#
# 用法：./flutter-glibc-shims.sh [FLUTTER_DIR]     幂等；原文件保留为 <name>.glibc
set -euo pipefail

FLUTTER_DIR="${1:-$HOME/flutter}"
ROOTFS="${ROOTFS_DIR:-$HOME/Android/arm64-rootfs}"
ENGINE="$FLUTTER_DIR/bin/cache/artifacts/engine/linux-arm64"
UBUNTU_URL="${UBUNTU_URL:-https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-arm64.tar.gz}"

command -v proot >/dev/null || { echo "请先: pkg install proot" >&2; exit 1; }

if [[ ! -x "$ROOTFS/bin/sh" ]]; then
  echo "[1/3] 准备 arm64 rootfs（提供 glibc 装载器）"
  mkdir -p "$ROOTFS"; tmp=$(mktemp -d)
  curl -fL --retry 3 -o "$tmp/r.tar.gz" "$UBUNTU_URL"
  tar -xzf "$tmp/r.tar.gz" -C "$ROOTFS" 2>"$tmp/err" || true
  rm -rf "$tmp"
  echo "    已解包到 $ROOTFS"
else
  echo "[1/3] rootfs 已存在"
fi

echo "[2/3] 生成 proot 垫片"
shim() { # $1 = 文件名
  local f="$ENGINE/$1"
  [[ -e "$f" ]] || { echo "    跳过 $1（不存在）"; return; }
  if [[ -f "$f.glibc" ]]; then echo "    已垫片 $1"; return; fi
  mv "$f" "$f.glibc"
  cat > "$f" <<SH
#!/data/data/com.termux/files/usr/bin/bash
# 由 termux-dsh/toolchain/flutter-glibc-shims.sh 生成：proot + $ROOTFS 提供 glibc
exec env -u LD_PRELOAD proot -R "$ROOTFS" -b "\$HOME" -0 -w / "$f.glibc" "\$@"
SH
  chmod +x "$f"
  echo "    已垫片 $1"
}
for t in impellerc gen_snapshot flutter_tester dartaotruntime; do shim "$t"; done

echo "[3/3] 完成"
echo "注意：flutter precache --force 会覆盖这些垫片，重跑本脚本即可。"
