#!/data/data/com.termux/files/usr/bin/bash
# Idempotently add the Termux toolchain environment to ~/.zshenv.
# Only appends once; removing the marked block is safe.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/../lib/common.sh"

ZSHRC="${ZSHRC:-$HOME/.zshenv}"
MARK="# >>> termux-dsh env >>>"
touch "$ZSHRC"
if grep -qF "$MARK" "$ZSHRC"; then
  info "环境块已存在：$ZSHRC"
  exit 0
fi
cat >>"$ZSHRC" <<'EOF'

# >>> termux-dsh env >>>
# Added by termux-dsh; remove this block to undo.
export PATH="$HOME/bin:$PATH"
export ANDROID_DATA="${ANDROID_DATA:-/data}"
export ANDROID_ROOT="${ANDROID_ROOT:-/system}"
if [ -d "$PREFIX/lib/jvm/java-21-openjdk" ]; then
  export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
fi
if [ -d "$HOME/Android/Sdk" ]; then
  export ANDROID_HOME="$HOME/Android/Sdk"
fi
export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"
# <<< termux-dsh env <<<
EOF
info "已写入环境块：$ZSHRC"
