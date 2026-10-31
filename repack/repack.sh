#!/usr/bin/env bash
# Build the Termux/Android repack of dsh from the official npm package.
#
# Pipeline:
#   1. npm install @deepseek-ai/dsh@<upstream> for android/arm64 (scripts off)
#   2. apply the A-class host patches and B5 to the build tree
#   3. add esbuild/sharp platform packages
#   4. NDK-cross-compile koffi and node-pty
#   5. assemble a dsh-termux package, npm pack it, hard-verify the tarball
#
# Usage: repack.sh [upstream-version] [--dry-run]
#   upstream-version  empty or "latest" → resolve @deepseek-ai/dsh@latest
#
# Env:
#   REV                 revision suffix, default 1
#   NODE_TARGET_VERSION Node version for native builds, default host node
#   ANDROID_NDK_HOME    NDK root; falls back to ANDROID_HOME/ndk/*
#   TDSH_WORK           scratch directory; default mktemp -d
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
source "$ROOT/lib/common.sh"

UPSTREAM_ARG="${1:-}"
DRY_RUN=0
[[ "${2:-}" == "--dry-run" ]] && DRY_RUN=1

REV="${REV:-1}"
[[ "$REV" =~ ^[0-9]+$ ]] || die "REV 必须是正整数：$REV"
NODE_TARGET_VERSION="${NODE_TARGET_VERSION:-$(node -p 'process.versions.node')}"
NODE_TARGET_VERSION="${NODE_TARGET_VERSION#v}"

for t in node npm patch tar curl sha256sum file python3 cmake; do
  have "$t" || die "缺构建依赖：$t"
done

if [[ -z "$UPSTREAM_ARG" || "$UPSTREAM_ARG" == "latest" ]]; then
  UPSTREAM="$(npm view @deepseek-ai/dsh version)"
else
  UPSTREAM="${UPSTREAM_ARG#v}"
fi
[[ -n "$UPSTREAM" ]] || die "无法解析上游版本"
VER="${UPSTREAM}-tdsh.${REV}"
info "上游 $UPSTREAM，产物版本 $VER，Node $NODE_TARGET_VERSION"

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$NDK" ]]; then
  SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-/usr/local/lib/android/sdk}}"
  NDK="$(ls -d "$SDK"/ndk/* 2>/dev/null | sort -V | tail -1 || true)"
fi
[[ -n "$NDK" && -d "$NDK" ]] || die "找不到 Android NDK（设置 ANDROID_NDK_HOME）"
export ANDROID_NDK_HOME="$NDK"
export ANDROID_NDK_ROOT="$NDK"
info "NDK：$NDK ($(basename "$NDK"))"

WORK="${TDSH_WORK:-$(mktemp -d "${TMPDIR:-/tmp}/tdsh-repack.XXXXXX")}"
BUILD="$WORK/build"
PKGDIR="$WORK/package"
DIST="$ROOT/dist"
mkdir -p "$BUILD" "$DIST"
rm -rf "$DIST"/* "$PKGDIR"
info "工作目录：$WORK"

# 1) Official npm package, android/arm64 optional deps, no install scripts.
info "[1/6] 安装官方 npm 包"
npm install --prefix "$BUILD" --ignore-scripts --include=optional \
  --os=android --cpu=arm64 --no-audit --no-fund \
  "@deepseek-ai/dsh@$UPSTREAM"
[[ -f "$BUILD/node_modules/@deepseek-ai/dsh/package.json" ]] || die "npm 安装不完整"

# 2) A-class host patches + B5. Every target must be present; a missing one
# means the upstream dependency graph changed and the tarball must not ship.
info "[2/6] 应用 A 类宿主补丁"
APPLIED=0
while IFS= read -r row; do
  IFS=$'\x1f' read -r pkg rel patchref pristine patched create <<<"$row"
  pkg_dir="$BUILD/node_modules/$pkg"
  dest="$pkg_dir/$rel"
  [[ -d "$pkg_dir" ]] || die "A 类目标包缺失：$pkg"
  if [[ -f "$dest" ]]; then
    got="$(sha "$dest")"
    if [[ "$got" == "$patched" ]]; then
      info "  已打：$pkg/$rel"
      continue
    fi
    [[ -z "$pristine" || "$got" == "$pristine" ]] || die "A 类漂移：$pkg/$rel（$got）"
  else
    [[ "$create" == "1" ]] || die "A 类目标文件缺失：$pkg/$rel"
  fi
  [[ -f "$ROOT/patches/$patchref" ]] || die "缺补丁：$patchref"
  ( cd "$pkg_dir" && patch -p1 --forward --batch < "$ROOT/patches/$patchref" ) \
    || die "A 类补丁失败：$patchref"
  got="$(sha "$dest")"
  [[ "$got" == "$patched" ]] || die "A 类补丁后哈希不符：$pkg/$rel"
  APPLIED=$((APPLIED + 1))
done < <(node -e '
const fs = require("fs");
const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const t of m.targets) {
  if (t.section !== "core") continue;
  process.stdout.write([t.pkg, t.rel, t.patch, t.pristine_sha256 ?? "", t.patched_sha256 ?? "", t.create ? "1" : "0"].join("\u001f") + "\n");
}' "$ROOT/patches/manifest.json")
info "  A 类新打 $APPLIED 个文件"

SESSION="$BUILD/node_modules/@deepseek-ai/dsh-session-persistence-jsonl"
[[ -d "$SESSION" ]] || die "缺 session-persistence-jsonl"
( cd "$SESSION" && patch -p1 --forward --batch --dry-run < "$ROOT/patches/platform/session-rename.patch" ) \
  || die "B5 锚点不匹配"
( cd "$SESSION" && patch -p1 --forward --batch < "$ROOT/patches/platform/session-rename.patch" )
grep -q 'rename(tmp, finalPath)' "$SESSION/lib/index.js" || die "B5 未生效"
info "  B5 session rename OK"

DSHMETA="$BUILD/node_modules/@deepseek-ai/dsh"
[[ -d "$DSHMETA" ]] || die "缺 @deepseek-ai/dsh"
( cd "$DSHMETA" && patch -p1 --forward --batch --dry-run < "$ROOT/patches/platform/tdsh-version.patch" ) \
  || die "B10 锚点不匹配"
( cd "$DSHMETA" && patch -p1 --forward --batch < "$ROOT/patches/platform/tdsh-version.patch" )
grep -q 'manifest.name === "dsh-termux"' "$DSHMETA/lib/bin.js" || die "B10 未生效"
info "  B10 CLI version OK"

# 3) Platform-specific optional packages.
info "[3/6] 平台件"
BUILD="$BUILD" WORK="$WORK" bash "$HERE/platforms.sh"

# 4) Native modules.
info "[4/6] 原生模块（NDK 交叉编译）"
BUILD="$BUILD" WORK="$WORK" NODE_TARGET_VERSION="$NODE_TARGET_VERSION" REPO_ROOT="$ROOT" \
  bash "$HERE/native/koffi.sh"
BUILD="$BUILD" WORK="$WORK" NODE_TARGET_VERSION="$NODE_TARGET_VERSION" REPO_ROOT="$ROOT" \
  bash "$HERE/native/node-pty.sh"

# Drop host prebuilds/build caches: the tarball must contain only the Android
# payload, otherwise a valid-looking package can carry x64/win32 binaries.
PTY="$BUILD/node_modules/node-pty"
find "$PTY/prebuilds" -mindepth 1 -maxdepth 1 -type d ! -name android-arm64 -exec rm -rf {} + 2>/dev/null || true
rm -rf "$PTY/build"
KOFFI="$BUILD/node_modules/koffi"
if [[ -d "$KOFFI/build" ]]; then
  find "$KOFFI/build" -mindepth 1 -maxdepth 1 ! -name koffi -exec rm -rf {} + 2>/dev/null || true
  find "$KOFFI/build/koffi" -mindepth 1 -maxdepth 1 -type d ! -name android_arm64 -exec rm -rf {} + 2>/dev/null || true
fi

# 5) Assemble the package: dsh root + every dependency except @deepseek-ai/dsh.
info "[5/6] 组装包"
mkdir -p "$PKGDIR"
cp -a "$BUILD/node_modules/@deepseek-ai/dsh/." "$PKGDIR/"
mkdir -p "$PKGDIR/node_modules/@deepseek-ai"
for entry in "$BUILD/node_modules"/* "$BUILD/node_modules"/.bin; do
  [[ -e "$entry" ]] || continue
  base="$(basename "$entry")"
  if [[ "$base" == "@deepseek-ai" ]]; then
    for child in "$entry"/*; do
      [[ "$(basename "$child")" == "dsh" ]] && continue
      cp -a "$child" "$PKGDIR/node_modules/@deepseek-ai/"
    done
  elif [[ "$base" == ".bin" ]]; then
    cp -a "$entry" "$PKGDIR/node_modules/.bin"
  else
    cp -a "$entry" "$PKGDIR/node_modules/"
  fi
done

node - "$PKGDIR/package.json" "$VER" "$UPSTREAM" "$REV" "$NODE_TARGET_VERSION" "$NDK" <<'NODE'
const fs = require("fs");
const [file, ver, upstream, rev, nodeVersion, ndk] = process.argv.slice(2);
const p = JSON.parse(fs.readFileSync(file, "utf8"));
p.name = "dsh-termux";
p.version = ver;
delete p.dependencies;
delete p.optionalDependencies;
delete p.peerDependencies;
delete p.devDependencies;
delete p.scripts;
delete p.files;
delete p.publishConfig;
delete p.repository;
delete p.bugs;
delete p.homepage;
p.tdsh = {
  upstream,
  rev: Number(rev),
  node: nodeVersion,
  ndk: ndk.split("/").pop(),
  builtAt: new Date().toISOString(),
};
fs.writeFileSync(file, JSON.stringify(p, null, 2) + "\n");
NODE

# npm pack excludes node_modules unless every bundled package is listed in
# bundledDependencies. Build that list from the actual assembled tree so the
# tarball is self-contained and `npm i -g` does not reach the registry.
node - "$PKGDIR" <<'NODE'
const fs = require("fs");
const path = require("path");
const pkgDir = process.argv[2];
const nm = path.join(pkgDir, "node_modules");
const file = path.join(pkgDir, "package.json");
const p = JSON.parse(fs.readFileSync(file, "utf8"));
const names = [];
for (const entry of fs.readdirSync(nm)) {
  if (entry === ".bin" || entry === ".package-lock.json") continue;
  if (entry.startsWith("@")) {
    for (const child of fs.readdirSync(path.join(nm, entry))) names.push(`${entry}/${child}`);
  } else {
    names.push(entry);
  }
}
p.dependencies = {};
p.bundledDependencies = [];
for (const name of names.sort()) {
  const meta = path.join(nm, name, "package.json");
  if (!fs.existsSync(meta)) continue;
  const version = JSON.parse(fs.readFileSync(meta, "utf8")).version;
  p.dependencies[name] = version;
  p.bundledDependencies.push(name);
}
fs.writeFileSync(file, JSON.stringify(p, null, 2) + "\n");
console.log(`bundled ${p.bundledDependencies.length} packages`);
NODE

TARBALL="$(cd "$PKGDIR" && npm pack --pack-destination "$DIST" 2>"$WORK/npm-pack.err" | tail -1)"[[ -n "$TARBALL" && -f "$DIST/$TARBALL" ]] || { cat "$WORK/npm-pack.err" >&2; die "npm pack 失败"; }
cp -f "$DIST/$TARBALL" "$DIST/dsh-termux.tgz"
sha256sum "$DIST/dsh-termux.tgz" | awk '{print $1"  dsh-termux.tgz"}' > "$DIST/dsh-termux.tgz.sha256"
printf '%s\n' "$VER" > "$DIST/version.txt"
cat > "$DIST/release-notes.md" <<EOF
# dsh $VER (Termux arm64)

- 上游：\`@deepseek-ai/dsh@$UPSTREAM\`
- 原生：koffi（NDK 交叉编译，API 24 / arm64-v8a）、node-pty（Node $NODE_TARGET_VERSION headers）
- 补丁：A 类宿主 7 target / 8 文件；B1–B5；HMR 通过 profile 覆盖禁用
- 非上游官方产物；由 Starsky16/termux-dsh 的 CI 从官方 npm 包重组
- 安装：\`npm i -g dsh-termux-$VER.tgz\`（或按仓库 README 的 bootstrap）
EOF

# 6) Hard verification.
info "[6/6] 校验产物"
bash "$HERE/verify-package.sh" "$DIST/dsh-termux.tgz" "$VER"

echo
info "完成：$DIST/dsh-termux.tgz ($(du -h "$DIST/dsh-termux.tgz" | cut -f1))"
[[ "$DRY_RUN" == "1" ]] && info "dry-run：不发布"
exit 0
