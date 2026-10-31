#!/data/data/com.termux/files/usr/bin/bash
# One-command resurrect: deps → Release tarball → global install → env →
# profile overrides → workspace wiring → verify.
#
# The tarball is built by this repository's CI from the official
# @deepseek-ai/dsh npm package; the repository must have a published Release.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

# GitHub's /releases/latest/download excludes pre-releases, and this repo
# publishes rc builds as pre-releases. Resolve the newest tag through the API;
# TDSH_RELEASE_BASE still overrides everything.
resolve_release_base() {
  if [[ -n "${TDSH_RELEASE_BASE:-}" ]]; then
    printf '%s\n' "$TDSH_RELEASE_BASE"
    return 0
  fi
  local tag
  tag="$(curl -fsSL 'https://api.github.com/repos/Starsky16/termux-dsh/releases?per_page=10' 2>/dev/null \
    | sed -n 's/.*"tag_name":[[:space:]]*"\([^"]*\)".*/\1/p' | head -1 || true)"
  if [[ -n "$tag" ]]; then
    printf 'https://github.com/Starsky16/termux-dsh/releases/download/%s\n' "$tag"
  else
    printf 'https://github.com/Starsky16/termux-dsh/releases/latest/download\n'
  fi
}
WORK="${TMPDIR:-/tmp}/termux-dsh-install"
TGZ="$WORK/dsh-termux.tgz"
SHA="$WORK/dsh-termux.tgz.sha256"

# Non-interactive shells (and some agent shells) do not export PREFIX.
if [[ -z "${PREFIX:-}" && -d /data/data/com.termux/files/usr ]]; then
  PREFIX=/data/data/com.termux/files/usr
  export PREFIX
fi
[[ -n "${PREFIX:-}" && -d "${PREFIX:-}" ]] || die "不是 Termux 环境（PREFIX 未设置）"
[[ "$(uname -m)" == "aarch64" ]] || die "只支持 arm64/aarch64，当前 $(uname -m)"

info "[1/8] 依赖"
pkg install -y nodejs-lts python git curl ripgrep patch coreutils file
node -e 'const v=process.versions.node.split(".").map(Number);process.exit((v[0]>24||(v[0]==24&&v[1]>=2))?0:1)' \
  || die "需要 Node >= 24.2（pkg install nodejs-lts），当前 $(node -v)"

BASE="$(resolve_release_base)"
info "[2/8] 下载重组包"
mkdir -p "$WORK"
dl "$BASE/dsh-termux.tgz" "$TGZ" || die "下载失败：$BASE/dsh-termux.tgz（Release 是否已发布？）"
dl "$BASE/dsh-termux.tgz.sha256" "$SHA" || die "下载失败：$BASE/dsh-termux.tgz.sha256"
WANT="$(cut -d' ' -f1 "$SHA")"
[[ "$(sha "$TGZ")" == "$WANT" ]] || die "tarball sha256 不符"

info "[3/8] 全局安装（包内已含原生模块与 A/B 类补丁）"
npm i -g --ignore-scripts "$TGZ"
# npm 生成的 bin shebang 固定是 #!/usr/bin/env node，Termux 没有 /usr/bin/env。
if have termux-fix-shebang; then
  termux-fix-shebang "$(command -v dsh)"
  DSH_JS="$(npm root -g)/dsh-termux/lib/bin.js"
  [[ -f "$DSH_JS" ]] && termux-fix-shebang "$DSH_JS"
else
  warn "缺 termux-fix-shebang；若 dsh 报 bad interpreter，执行 pkg install termux-tools"
fi
if have dsh; then
  dsh --version | grep -q -- '-tdsh\.' || warn "dsh 版本未含 -tdsh.：$(dsh --version 2>&1 || true)"
else
  die "安装后找不到 dsh 命令"
fi

info "[4/8] 环境变量"
bash "$HERE/profile/setup-env.sh"

info "[5/8] profile 覆盖（sandbox/approval/web-fetch/HMR）"
bash "$HERE/profile/apply-overrides.sh"

info "[6/8] 接线（workflow-sync 存在时）"
if [[ -d "${CODE:-$HOME/code}/workflow-sync" ]]; then
  bash "$HERE/wiring/link-workspace.sh"
else
  warn "未找到 ${CODE:-$HOME/code}/workflow-sync，跳过记忆/技能接线"
fi

info "[7/8] profile 树补丁检查"
bash "$HERE/patches/apply.sh" --check || warn "profile 树有未打补丁的包（首次安装且未装插件时通常正常）"

info "[8/8] 回归"
bash "$HERE/verify.sh"

echo
echo "完成。启动：dsh web"
