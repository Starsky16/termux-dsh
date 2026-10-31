#!/data/data/com.termux/files/usr/bin/bash
#
# x86_64 垫片：在 arm64 Termux 上用 qemu-user 跑 x86_64 Linux 工具。
#
# 用途：Android SDK 的 aapt2 / zipalign / aapt 只有 **x86-64 glibc** 构建，
# arm64 上直接跑会 `Exec format error`。本脚本装 Termux 的 qemu-user-x86-64，
# 拉一份 amd64 Ubuntu base rootfs 当 sysroot，并生成 shim 脚本供 Gradle/AGP 调用。
#
# 用法：./android-sdk-x86-shims.sh            （幂等：已存在的 rootfs / shim 会跳过）
# 卸载：rm -rf ~/Android/x86_64-rootfs ~/Android/Sdk/toolchain-shims
set -euo pipefail

ROOTFS_DIR="${ROOTFS_DIR:-$HOME/Android/x86_64-rootfs}"
SHIM_DIR="${SHIM_DIR:-$HOME/Android/Sdk/toolchain-shims}"
SDK_BUILD_TOOLS="${SDK_BUILD_TOOLS:-$HOME/Android/Sdk/build-tools/36.0.0}"
UBUNTU_URL="${UBUNTU_URL:-https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-amd64.tar.gz}"

command -v qemu-x86_64 >/dev/null || { echo "请先: pkg install qemu-user-x86-64" >&2; exit 1; }

echo "[1/3] 准备 amd64 rootfs（当作 x86_64 的 /lib 来源）"
if [[ -x "$ROOTFS_DIR/bin/sh" ]]; then
  echo "    已存在，跳过"
else
  mkdir -p "$ROOTFS_DIR"
  tmp=$(mktemp -d)
  curl -fL --retry 3 -o "$tmp/rootfs.tar.gz" "$UBUNTU_URL"
  # SELinux 禁止 app data 内建硬链接；rootfs 里少数硬链接（perl/gunzip 别名）会报错，
  # 这些文件对本用途无关，故容忍失败，随后补成普通副本。
  tar -xzf "$tmp/rootfs.tar.gz" -C "$ROOTFS_DIR" 2>"$tmp/tar.err" || true
  if [[ -s "$tmp/tar.err" ]]; then sed 's/^/    tar: /' "$tmp/tar.err" | head -3; fi
  for pair in "usr/bin/perl:usr/bin/perl5.38.2" "usr/bin/gunzip:usr/bin/uncompress"; do
    src="$ROOTFS_DIR/${pair%%:*}"; dst="$ROOTFS_DIR/${pair##*:}"
    if [[ -f "$src" && ! -e "$dst" ]]; then cp "$src" "$dst"; fi
  done
  rm -rf "$tmp"
  echo "    已解包到 $ROOTFS_DIR"
fi

echo "[2/3] 生成 shim"
mkdir -p "$SHIM_DIR"
make_shim() { # $1 = 工具名
  cat > "$SHIM_DIR/$1" <<SH
#!/data/data/com.termux/files/usr/bin/bash
# 由 termux-dsh/toolchain/android-sdk-x86-shims.sh 生成：用 qemu-user 跑 x86_64 的 $1
exec env -u LD_PRELOAD qemu-x86_64 -L "$ROOTFS_DIR" "$SDK_BUILD_TOOLS/$1" "\$@"
SH
  chmod +x "$SHIM_DIR/$1"
  echo "    $SHIM_DIR/$1"
}
for t in aapt2 zipalign aapt; do
  [[ -f "$SDK_BUILD_TOOLS/$t" ]] && make_shim "$t"
done

echo "[3/3] 告诉 Gradle/AGP 用 shim 版本的 aapt2"
GRADLE_PROPS="$HOME/.gradle/gradle.properties"
mkdir -p "$(dirname "$GRADLE_PROPS")"
touch "$GRADLE_PROPS"
if grep -q 'android.aapt2FromMavenOverride' "$GRADLE_PROPS"; then
  echo "    已配置，跳过"
else
  cat >> "$GRADLE_PROPS" <<PROPS
# Termux/arm64：SDK 自带的 aapt2 是 x86-64 glibc 二进制，改走 qemu 垫片
android.aapt2FromMavenOverride=$SHIM_DIR/aapt2
PROPS
  echo "    已写入 $GRADLE_PROPS"
fi

echo
echo "验证："
echo "  $SHIM_DIR/aapt2 version"
echo "  PATH=\"$SHIM_DIR:\$PATH\" flutter build apk --debug"
