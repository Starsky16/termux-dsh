#!/data/data/com.termux/files/usr/bin/bash
# One-command resurrect: deps → Release tarball → global install → env →
# profile overrides → workspace wiring → verify.
#
# The tarball is built by this repository's CI from the official
# @deepseek-ai/dsh npm package; the repository must have a published Release.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$HERE/lib/common.sh"

BASE="${TDSH_RELEASE_BASE:-https://github.com/Starsky16/termux-dsh/releases/latest/download}"
WORK="${TMPDIR:-/tmp}/termux-dsh-install"
TGZ="$WORK/dsh-termux.tgz"
SHA="$WORK/dsh-termux.tgz.sha256"

[[ -n "${PREFIX:-}" && -d "${PREFIX:-}" ]] || die "不是 Termux 环境（PREFIX 未设置）"
[[ "$(uname -m)" == "aarch64" ]] || die "只支持 arm64/aarch64，当前 $(uname -m)"

info "[1/8] 依赖"
pkg install -y nodejs-lts python git curl ripgrep patch coreutils file
node -e 'const v=process.versions.node.split(".").map(Number);process.exit((v[0]>24||(v[0]==24&&v[1]>=2))?0:1)' \
  || die "需要 Node >= 24.2（pkg install nodejs-lts），当前 $(node -v)"

info "[2/8] 下载重组包"
mkdir -p "$WORK"
dl "$BASE/dsh-termux.tgz" "$TGZ" || die "下载失败：$BASE/dsh-termux.tgz（Release 是否已发布？）"
dl "$BASE/dsh-termux.tgz.sha256" "$SHA" || die "下载失败：$BASE/dsh-termux.tgz.sha256"
WANT="$(cut -d' ' -f1 "$SHA")"
[[ "$(sha "$TGZ")" == "$WANT" ]] || die "tarball sha256 不符"

info "[3/8] 全局安装（包内已含原生模块与 A/B 类补丁）"
npm i -g "$TGZ"
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
