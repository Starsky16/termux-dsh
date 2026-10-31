#!/data/data/com.termux/files/usr/bin/bash
#
# Flutter on Termux（原生 arm64/Bionic）一键接线。
#
# 背景：官方 flutter_linux_*-stable.tar.xz 自带的是 **glibc** dart 与 **x64**
# 的 flutter_tools 快照，arm64 Android 上直接 exec 就报
#   `cannot execute binary file: Exec format error`
#   `Snapshot not compatible with the current VM configuration: ... x64 linux ... arm64 android`
# 本脚本把 dart-sdk 换成 Termux 原生 dart（版本必须与 Flutter 内置的 Dart 一致），
# 再给 flutter_tools 打 4 处「android 当 linux」补丁并重编快照。
#
# 用法：./flutter.sh [FLUTTER_DIR]   （默认 ~/flutter）
# 前置：pkg install dart which unzip xz-utils openjdk-21
# 幂等：已换过的软链/已打过的补丁会跳过。
set -euo pipefail

FLUTTER_DIR="${1:-$HOME/flutter}"
DART_SDK_TERMUX="${DART_SDK_TERMUX:-/data/data/com.termux/files/usr/lib/dart-sdk}"

[[ -d "$FLUTTER_DIR" ]] || { echo "找不到 Flutter 目录：$FLUTTER_DIR" >&2; exit 1; }
[[ -x "$DART_SDK_TERMUX/bin/dart" ]] || { echo "找不到 Termux dart-sdk：$DART_SDK_TERMUX" >&2; exit 1; }

# dart-sdk 版本必须与 Flutter 内置的一致，否则快照不兼容
FLUTTER_DART=$("$DART_SDK_TERMUX/bin/dart" --version 2>&1 | sed -n 's/^Dart SDK version: \([^ ]*\).*/\1/p')
WANT_DART=$(cat "$FLUTTER_DIR/bin/cache/dart-sdk/version" 2>/dev/null || cat "$FLUTTER_DIR/bin/cache/dart-sdk.glibc/version" 2>/dev/null || echo "?")
echo "Flutter 内置 Dart: $WANT_DART ／ Termux dart: $FLUTTER_DART"
[[ "$FLUTTER_DART" == "$WANT_DART" ]] || echo "⚠️  版本不一致，快照可能不兼容（继续，失败就换 dart 版本）" >&2

echo "[1/4] 把 dart-sdk 换成 Termux 原生版"
cd "$FLUTTER_DIR/bin/cache"
if [[ -L dart-sdk ]]; then
  echo "    已是软链，跳过"
else
  [[ -d dart-sdk.glibc ]] || mv dart-sdk dart-sdk.glibc
  ln -sfn "$DART_SDK_TERMUX" dart-sdk
  echo "    已建软链（原 glibc 版留作 dart-sdk.glibc）"
fi

echo "[2/4] 拉 flutter_tools 依赖（走 pub 镜像）"
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
(cd "$FLUTTER_DIR/packages/flutter_tools" && "$DART_SDK_TERMUX/bin/dart" pub get >/dev/null)
echo "    ok"

echo "[3/4] 打 android-as-linux 补丁"
python3 - "$FLUTTER_DIR" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1]) / "packages/flutter_tools/lib/src"

def patch(rel, old, new, marker):
    p = root / rel
    s = p.read_text(encoding="utf-8")
    if marker in s:
        print(f"    {rel}: 已打过，跳过"); return
    if s.count(old) != 1:
        raise SystemExit(f"    {rel}: 找不到唯一锚点（Flutter 版本可能变了），请在 setup.sh 里更新锚点")
    p.write_text(s.replace(old, new), encoding="utf-8")
    print(f"    {rel}: patched")

# a) dart:ffi 在 Android 上报 android_*，映射成 linux_*
patch("base/os.dart",
      "    final Abi resolvedAbi = currentAbi ?? Abi.current();",
      "    final Abi resolvedAbi = _normalizeHostAbi(currentAbi ?? Abi.current());",
      "_normalizeHostAbi")
s = (root / "base/os.dart").read_text(encoding="utf-8")
if "_normalizeHostAbi(Abi abi)" not in s:
    helper = '''/// Termux/Android: `dart:ffi` reports the `android*` ABIs, but the Flutter tool
/// only models Linux/macOS/Windows hosts and throws `Unsupported host platform`
/// on anything else. Map Android to the matching Linux ABI.
Abi _normalizeHostAbi(Abi abi) {
  return switch (abi) {
    Abi.androidArm => Abi.linuxArm,
    Abi.androidArm64 => Abi.linuxArm64,
    Abi.androidX64 => Abi.linuxX64,
    Abi.androidRiscv64 => Abi.linuxRiscv64,
    _ => abi,
  };
}

'''
    anchor = "/// Utilities for interacting with the host operating system."
    (root / "base/os.dart").write_text(s.replace(anchor, helper + anchor, 1), encoding="utf-8")
    print("    base/os.dart: 插入 _normalizeHostAbi")

# b) Platform.isLinux 把 android 计入
patch("base/platform.dart",
      "  bool get isLinux => operatingSystem == 'linux';",
      "  /// Termux/Android reports `android`; treat it as Linux so host detection,\n"
      "  /// artifact selection and doctor checks take the Linux path.\n"
      "  bool get isLinux => operatingSystem == 'linux' || operatingSystem == 'android';",
      "operatingSystem == 'android'")

# c) 缓存工件表按 linux 查
patch("flutter_cache.dart",
      "      final List<String>? binaryDirs = artifacts[_platform.operatingSystem];",
      "      final String hostKey = _platform.operatingSystem == 'android' ? 'linux' : _platform.operatingSystem;\n"
      "      final List<String>? binaryDirs = artifacts[hostKey];",
      "final String hostKey =")

# d) NDK llvm 宿主目录按 linux 查
patch("android/android_sdk.dart",
      "          .childDirectory(_llvmHostDirectoryName[platform.operatingSystem]!)",
      "          .childDirectory(_llvmHostDirectoryName[platform.operatingSystem == 'android' ? 'linux' : platform.operatingSystem]!)",
      "platform.operatingSystem == 'android' ? 'linux' : platform.operatingSystem]!)")
PY

echo "[4/4] 重编 flutter_tools 快照"
cd "$FLUTTER_DIR"
"$DART_SDK_TERMUX/bin/dart" --snapshot=bin/cache/flutter_tools.snapshot \
  --packages=packages/flutter_tools/.dart_tool/package_config.json \
  packages/flutter_tools/bin/flutter_tools.dart
echo
echo "完成。验证："
echo "  export PATH=\"\$HOME/flutter/bin:\$PATH\""
echo "  flutter --version && flutter doctor"
