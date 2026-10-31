#!/usr/bin/env bash
# Install the platform-specific optional packages that npm cannot select for
# android-arm64: esbuild's android binary and sharp's wasm32 fallback.
#
# We extract the published tarballs instead of running `npm install` inside the
# build tree: a second install can prune the packages the first install added.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

BUILD="${BUILD:?BUILD 未设置}"
WORK="${WORK:?WORK 未设置}"
PKGS="$WORK/platform-packages"
mkdir -p "$PKGS"

pkgver() {
  node -e 'process.stdout.write(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).version)' "$1"
}

extract_pkg() {
  local spec="$1" dest="$2"
  local tarball
  tarball="$(npm pack "$spec" --pack-destination "$PKGS" 2>/dev/null | tail -1)"
  [[ -n "$tarball" && -f "$PKGS/$tarball" ]] || die "下载失败：$spec"
  mkdir -p "$dest"
  tar -xzf "$PKGS/$tarball" -C "$dest" --strip-components=1
  info "installed $spec → $dest"
}

# esbuild: only needed when the dsh tree actually depends on it.
if [[ -f "$BUILD/node_modules/esbuild/package.json" ]]; then
  ESBUILD_VER="$(pkgver "$BUILD/node_modules/esbuild/package.json")"
  DEST="$BUILD/node_modules/@esbuild/android-arm64"
  if [[ ! -f "$DEST/package.json" ]]; then
    extract_pkg "@esbuild/android-arm64@$ESBUILD_VER" "$DEST"
  fi
  GOT="$(pkgver "$DEST/package.json")"
  [[ "$GOT" == "$ESBUILD_VER" ]] || die "esbuild 平台件版本不符：$GOT != $ESBUILD_VER"
  [[ -f "$DEST/bin/esbuild" ]] || die "esbuild 平台件缺 bin/esbuild"
  if have file; then
    file "$DEST/bin/esbuild" | grep -q 'ARM aarch64' || die "esbuild 平台件不是 arm64"
  fi
  info "esbuild android-arm64 $ESBUILD_VER OK"
else
  info "esbuild 未安装，跳过"
fi

# sharp: dsh core does not depend on it; only plugin/optional trees do.
if [[ -f "$BUILD/node_modules/sharp/package.json" ]]; then
  SHARP_VER="$(pkgver "$BUILD/node_modules/sharp/package.json")"
  DEST="$BUILD/node_modules/@img/sharp-wasm32"
  if [[ ! -f "$DEST/package.json" ]]; then
    extract_pkg "@img/sharp-wasm32@$SHARP_VER" "$DEST"
  fi
  GOT="$(pkgver "$DEST/package.json")"
  [[ "$GOT" == "$SHARP_VER" ]] || die "sharp wasm 版本不符：$GOT != $SHARP_VER"
  info "sharp wasm32 $SHARP_VER OK"
else
  info "sharp 未安装，跳过"
fi
