#!/usr/bin/env bash
# Cross-compile koffi for Android arm64 (Bionic, API 24) with the NDK.
#
# Expects:
#   BUILD               npm --prefix build tree containing node_modules/koffi
#   ANDROID_NDK_HOME    NDK root (also accepts ANDROID_NDK_ROOT)
#   NODE_TARGET_VERSION Node version used for the cnoke build directory
#   REPO_ROOT           repository root (for patches/)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../../lib/common.sh"

BUILD="${BUILD:?BUILD 未设置}"
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
[[ -n "$NDK" && -d "$NDK" ]] || die "ANDROID_NDK_HOME 未设置或不存在"
NODE_TARGET_VERSION="${NODE_TARGET_VERSION:-$(node -p 'process.versions.node')}"
REPO_ROOT="${REPO_ROOT:?REPO_ROOT 未设置}"

KOFFI="$BUILD/node_modules/koffi"
[[ -f "$KOFFI/package.json" ]] || die "缺 koffi：$KOFFI"
KOFFI_VERSION="$(node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$KOFFI/package.json")"
info "koffi $KOFFI_VERSION → android_arm64 (API 24), Node $NODE_TARGET_VERSION"

# Re-assert the one-match anchors before patching; a changed upstream must fail
# loudly instead of producing a silently-wrong binary.
for p in koffi-statx.patch koffi-commandline.patch koffi-cmake.patch; do
  ( cd "$KOFFI" && patch -p1 --forward --batch --dry-run < "$REPO_ROOT/patches/platform/$p" ) \
    || die "锚点不匹配：$p（上游 koffi 已变化，先更新补丁）"
done
for p in koffi-statx.patch koffi-commandline.patch koffi-cmake.patch; do
  ( cd "$KOFFI" && patch -p1 --forward --batch < "$REPO_ROOT/patches/platform/$p" )
done

TOOLCHAIN="$NDK/build/cmake/android.toolchain.cmake"
[[ -f "$TOOLCHAIN" ]] || die "缺 NDK cmake toolchain：$TOOLCHAIN"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"

# cnoke: -P package dir, -D source dir, -d is a CMake cache define.
( cd "$KOFFI" && node cnoke.cjs build \
    -P "$KOFFI" -D "$KOFFI/src/koffi" \
    -t android_arm64 \
    -d "CMAKE_TOOLCHAIN_FILE=$TOOLCHAIN" \
    -d ANDROID_ABI=arm64-v8a \
    -d ANDROID_PLATFORM=android-24 \
    -d ANDROID_STL=c++_static \
    --runtime "$NODE_TARGET_VERSION" --release )

NODE_FILE="$KOFFI/build/koffi/android_arm64/koffi.node"
[[ -f "$NODE_FILE" ]] || die "koffi 产物不存在：$NODE_FILE"
if have file; then
  file "$NODE_FILE" | grep -q 'ARM aarch64' || die "koffi 产物不是 arm64：$(file "$NODE_FILE")"
fi
info "koffi OK：$NODE_FILE"
