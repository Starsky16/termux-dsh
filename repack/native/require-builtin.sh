#!/usr/bin/env bash
# Cross-compile node-addon-require-builtin for Android arm64 (Bionic, API 24).
#
# This addon is required by @deepseek-ai/cordis-plugin-loader at host
# preparation time; HMR being disabled does NOT remove the dependency.
# Upstream publishes no android optional package, so build the nodeabi backend
# from the public source and place it where the loader's local-build lookup
# expects it:
#   build/nodeabi/node-v<modules>-android-arm64/require_builtin.node
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/common.sh"

BUILD="${BUILD:?BUILD 未设置}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[[ -n "$NDK" && -d "$NDK" ]] || die "ANDROID_NDK_HOME 未设置或不存在"
NODE_TARGET_VERSION="${NODE_TARGET_VERSION:-$(node -p 'process.versions.node')}"
WORK="${WORK:?WORK 未设置}"
REPO_ROOT="${REPO_ROOT:?REPO_ROOT 未设置}"

PKG="$BUILD/node_modules/node-addon-require-builtin"
[[ -f "$PKG/package.json" ]] || die "缺 node-addon-require-builtin：$PKG"
PKG_VERSION="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$PKG/package.json")"
info "node-addon-require-builtin $PKG_VERSION → android_arm64 (API 24), Node $NODE_TARGET_VERSION"

# Pin the public source tag/commit that matches the npm package version.
SRC_COMMIT="a58d3599a2e551d7d706d1ff796c9fd4bbaff63c"
SRC="$WORK/node-addon-require-builtin-src"
if [[ ! -d "$SRC/.git" ]]; then
  rm -rf "$SRC"
  mkdir -p "$SRC"
  git -C "$SRC" init -q
  git -C "$SRC" remote add origin https://github.com/deepseek-ai/dsh-node-addon-require-builtin.git
fi
if ! git -C "$SRC" cat-file -e "$SRC_COMMIT^{commit}" 2>/dev/null; then
  git -C "$SRC" fetch --depth 1 origin "$SRC_COMMIT"
fi
git -C "$SRC" checkout -q --detach "$SRC_COMMIT"
# Keep libc++ static: Termux's Node does not expose the NDK libc++_shared.so.
( cd "$SRC" && patch -p1 --forward --batch < "$REPO_ROOT/patches/platform/require-builtin-static.patch" )

# binding.gyp resolves node-addon-api from the source tree. The dsh dependency
# tree may carry an older 7.x; this source pins 8.9.0, which has the
# string_view overloads used by node_api_addon.cc.
NAA_VERSION="8.9.0"
if [[ ! -f "$SRC/node_modules/node-addon-api/package.json" ]] \
  || [[ "$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$SRC/node_modules/node-addon-api/package.json" 2>/dev/null || true)" != "$NAA_VERSION" ]]; then
  rm -rf "$SRC/node_modules/node-addon-api"
  mkdir -p "$SRC/node_modules/node-addon-api"
  NAA_TGZ="$(cd "$WORK" && npm pack "node-addon-api@$NAA_VERSION" --pack-destination "$WORK" 2>/dev/null | tail -1)"
  [[ -f "$WORK/$NAA_TGZ" ]] || die "node-addon-api $NAA_VERSION 下载失败"
  tar -xzf "$WORK/$NAA_TGZ" -C "$SRC/node_modules/node-addon-api" --strip-components=1
fi

HEADERS="$WORK/node-headers/node-v$NODE_TARGET_VERSION"
if [[ ! -f "$HEADERS/include/node/common.gypi" ]]; then
  mkdir -p "$WORK/node-headers"
  TGZ="$WORK/node-headers/node-v$NODE_TARGET_VERSION-headers.tar.gz"
  dl "https://npmmirror.com/mirrors/node/v$NODE_TARGET_VERSION/node-v$NODE_TARGET_VERSION-headers.tar.gz" "$TGZ" \
    || dl "https://nodejs.org/dist/v$NODE_TARGET_VERSION/node-v$NODE_TARGET_VERSION-headers.tar.gz" "$TGZ"
  tar -xzf "$TGZ" -C "$WORK/node-headers"
fi
[[ -f "$HEADERS/include/node/common.gypi" ]] || die "Node headers 解包不完整：$HEADERS"

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
export CXXFLAGS="${CXXFLAGS:-} -static-libstdc++"
export LDFLAGS="${LDFLAGS:-} -static-libstdc++"

info "  编译 nodeabi backend"
( cd "$SRC/packages/native" \
  && GYP_DEFINES="narb_backend=nodeabi narb_product=require-builtin enable_lto=false enable_thin_lto=false lto_jobs=" \
     NODE_JS_PUBLIC_INCLUDE_DIRS="$HEADERS/include/node" \
     npx --yes node-gyp@11 rebuild --arch=arm64 --nodedir="$HEADERS" )

SRC_NODE="$SRC/packages/native/build/Release/require_builtin.node"
[[ -f "$SRC_NODE" ]] || die "require_builtin.node 不存在：$SRC_NODE"
ABI="$(node -p 'process.versions.modules')"
DST_DIR="$PKG/build/nodeabi/node-v$ABI-android-arm64"
mkdir -p "$DST_DIR"
cp -f "$SRC_NODE" "$DST_DIR/require_builtin.node"
if have file; then
  file "$DST_DIR/require_builtin.node" | grep -q 'ARM aarch64' \
    || die "require_builtin.node 不是 arm64：$(file "$DST_DIR/require_builtin.node")"
fi
info "  require-builtin OK：$DST_DIR/require_builtin.node"
