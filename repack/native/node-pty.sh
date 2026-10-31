#!/usr/bin/env bash
# Cross-compile node-pty for Android arm64 (Bionic, API 24) with the NDK.
#
# Expects:
#   BUILD               npm --prefix build tree containing node_modules/node-pty
#   ANDROID_NDK_HOME    NDK root
#   NODE_TARGET_VERSION Node version whose headers are used
#   WORK                scratch directory (headers cache)
#   REPO_ROOT           repository root (for patches/)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/common.sh"

BUILD="${BUILD:?BUILD 未设置}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[[ -n "$NDK" && -d "$NDK" ]] || die "ANDROID_NDK_HOME 未设置或不存在"
NODE_TARGET_VERSION="${NODE_TARGET_VERSION:-$(node -p 'process.versions.node')}"
WORK="${WORK:?WORK 未设置}"
REPO_ROOT="${REPO_ROOT:?REPO_ROOT 未设置}"

PTY="$BUILD/node_modules/node-pty"
[[ -f "$PTY/package.json" ]] || die "缺 node-pty：$PTY"
PTY_VERSION="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$PTY/package.json")"
info "node-pty $PTY_VERSION → android_arm64 (API 24), Node $NODE_TARGET_VERSION"

# B4: Bionic provides PTY APIs in libc; the NDK sysroot has no libutil.
( cd "$PTY" && patch -p1 --forward --batch --dry-run < "$REPO_ROOT/patches/platform/node-pty-noutil.patch" ) \
  || die "锚点不匹配：node-pty-noutil.patch"
( cd "$PTY" && patch -p1 --forward --batch < "$REPO_ROOT/patches/platform/node-pty-noutil.patch" )

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
[[ -d "$TOOLCHAIN" ]] || die "缺 NDK llvm 工具链：$TOOLCHAIN"
API=24
export CC="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang"
export CXX="$TOOLCHAIN/bin/aarch64-linux-android${API}-clang++"
export AR="$TOOLCHAIN/bin/llvm-ar"
export LD="$TOOLCHAIN/bin/ld.lld"
export RANLIB="$TOOLCHAIN/bin/llvm-ranlib"
export NM="$TOOLCHAIN/bin/llvm-nm"
export STRIP="$TOOLCHAIN/bin/llvm-strip"
# Keep libc++ out of the runtime dependency set (Termux's Node may not expose
# the NDK libc++_shared.so to addons). NDK clang accepts this driver flag.
export CXXFLAGS="${CXXFLAGS:-} -static-libstdc++"
export LDFLAGS="${LDFLAGS:-} -static-libstdc++"
for t in "$CC" "$CXX" "$AR" "$LD" "$RANLIB"; do [[ -x "$t" ]] || die "缺编译器：$t"; done

HEADERS="$WORK/node-headers/node-v$NODE_TARGET_VERSION"
if [[ ! -f "$HEADERS/common.gypi" ]]; then
  mkdir -p "$WORK/node-headers"
  TGZ="$WORK/node-headers/node-v$NODE_TARGET_VERSION-headers.tar.gz"
  # npmmirror first (China-friendly), nodejs.org as fallback.
  dl "https://npmmirror.com/mirrors/node/v$NODE_TARGET_VERSION/node-v$NODE_TARGET_VERSION-headers.tar.gz" "$TGZ" \
    || dl "https://nodejs.org/dist/v$NODE_TARGET_VERSION/node-v$NODE_TARGET_VERSION-headers.tar.gz" "$TGZ"
  tar -xzf "$TGZ" -C "$WORK/node-headers"
fi
[[ -f "$HEADERS/common.gypi" ]] || die "Node headers 解包不完整：$HEADERS"

# node-gyp's bundled copy is not guaranteed; pin a known version.
NODE_GYP=(npx --yes node-gyp@11)
( cd "$PTY" && GYP_DEFINES="target_arch=arm64 host_arch=x64" \
    npm_config_arch=arm64 \
    "${NODE_GYP[@]}" rebuild --arch=arm64 --nodedir="$HEADERS" )

SRC="$PTY/build/Release/pty.node"
[[ -f "$SRC" ]] || die "node-pty 产物不存在：$SRC"
DST_DIR="$PTY/prebuilds/android-arm64"
mkdir -p "$DST_DIR"
cp -f "$SRC" "$DST_DIR/pty.node"
if have file; then
  file "$DST_DIR/pty.node" | grep -q 'ARM aarch64' || die "node-pty 产物不是 arm64：$(file "$DST_DIR/pty.node")"
fi
info "node-pty OK：$DST_DIR/pty.node"
