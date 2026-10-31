#!/data/data/com.termux/files/usr/bin/bash
#
# 预置 Gradle 分发包到 wrapper 缓存，绕过 Java 的 DNS 问题。
#
# 背景（2026-10-25 实测）：本机 DNS 对部分域名（mirrors.cloud.tencent.com 等）解析失败/不稳定，
# curl（走 IPv6 或不同解析路径）能下，而 Java 的 URLConnection 报
#   java.net.UnknownHostException: mirrors.cloud.tencent.com
# wrapper 因此永远装不上 Gradle。本脚本用 curl 把 zip 放到 Gradle 期望的目录并写 .ok 标记。
#
# 用法：./gradle-seed.sh <仓库目录>          （读取该仓 android/gradle/wrapper/gradle-wrapper.properties）
#      ./gradle-seed.sh --url <URL> [--name <dist>]
set -euo pipefail

GRADLE_HOME_CACHE="${GRADLE_USER_HOME:-$HOME/.gradle}/wrapper/dists"

if [[ "${1:-}" == "--url" ]]; then
  url="$2"; name="${4:-$(basename "$url" .zip)}"
else
  repo="${1:?用法: ./gradle-seed.sh <仓库目录> | --url <URL>}"
  props="$repo/android/gradle/wrapper/gradle-wrapper.properties"
  [[ -f "$props" ]] || { echo "找不到 $props" >&2; exit 1; }
  url=$(sed -n 's/^distributionUrl=//p' "$props" | sed 's/\\:/:/g' | tr -d '\r')
  name=$(basename "$url" .zip)
fi
name="${name%-all}"; name="${name%-bin}"
[[ "$name" == gradle-*-* ]] || true
echo "分发 URL : $url"

# Gradle 的目录名 = base36(md5(url))
hash=$(python3 - "$url" <<'PY'
import hashlib, sys
d = hashlib.md5(sys.argv[1].encode()).digest()
n = int.from_bytes(d, "big")
digits = "0123456789abcdefghijklmnopqrstuvwxyz"
out = ""
while n: out = digits[n % 36] + out; n //= 36
print(out or "0")
PY
)
dist="$GRADLE_HOME_CACHE/$name/$hash"
echo "目标目录 : $dist"
if [[ -f "$dist/.ok" ]]; then echo "已预置，跳过"; exit 0; fi

mkdir -p "$dist"
echo "[1/2] curl 下载"
curl -fL --retry 3 -o "$dist/$name.zip" "$url"
echo "[2/2] 解包"
python3 - "$dist/$name.zip" "$dist" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
rm -f "$dist/$name.zip"
touch "$dist/.ok"
echo "完成。再次运行构建即可。"
