#!/data/data/com.termux/files/usr/bin/bash
# 共用函数：日志、断言、哈希、幂等下载。
#
# 只被本仓脚本 source，不单独执行。调用方负责在执行前安装 curl / sha256sum。
set -euo pipefail

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

sha() {
  [[ -f "$1" ]] || die "文件不存在：$1"
  sha256sum "$1" | cut -d' ' -f1
}

# 幂等下载 + 校验：dl <url> <dest> [sha256]
# 目标已存在时不重复下载；给了 sha256 就必须一致。
# 仓库为 public，Release 资产直连下载，不拼 gh-proxy 前缀。
dl() {
  local url="$1" dest="$2" want="${3:-}"
  if [[ ! -f "$dest" ]]; then
    mkdir -p "$(dirname "$dest")"
    curl -fL --retry 3 --retry-delay 2 -o "$dest" "$url" || { rm -f "$dest"; return 1; }
  fi
  [[ -s "$dest" ]] || { rm -f "$dest"; return 1; }
  [[ -z "$want" ]] || [[ "$(sha "$dest")" == "$want" ]] || die "sha256 不符：$dest"
}
