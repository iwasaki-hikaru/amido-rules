#!/bin/bash
# 本番の manifest.json を取得して、<保存先> に置く。結果を標準出力に 1 語で出す。
#   present … 取得できた
#   absent  … まだない（404・410）、または配信ホストが仮の値（PLACEHOLDER）
# それ以外（名前解決やネットワークの失敗、5xx、リダイレクトなど）は失敗にする。
# 取れなかったのに「ない」と扱うと、件数の比較や版の決め方を黙って飛ばしてしまうため。
#
# 使い方：.github/scripts/live-manifest.sh <配信ホスト> <保存先>
set -euo pipefail

if [ $# -ne 2 ]; then
  echo "使い方：$0 <配信ホスト> <保存先>" >&2
  exit 2
fi
host=$1
out=$2
rm -f "$out"

if [ -z "$host" ] || [[ "$host" == *PLACEHOLDER* ]]; then
  echo "配信ホストが仮の値なので、本番の manifest は取得しません（${host}）" >&2
  echo absent
  exit 0
fi

url="https://$host/v1/manifest.json"
tmp="$out.part"
mkdir -p "$(dirname "$out")"
# 一時的な失敗（タイムアウト・429・5xx の一部）だけ、少し待って取り直す
code=$(curl --silent --show-error --proto '=https' --retry 3 --retry-delay 5 \
  --header 'Cache-Control: no-cache' --output "$tmp" --write-out '%{http_code}' "$url") || {
  rm -f "$tmp"
  echo "本番の manifest を取得できません：$url" >&2
  exit 1
}

case "$code" in
  200)
    mv "$tmp" "$out"
    echo "本番の manifest を取得しました：$url" >&2
    echo present
    ;;
  404 | 410)
    rm -f "$tmp"
    echo "本番の manifest はまだありません（HTTP ${code}）：$url" >&2
    echo absent
    ;;
  *)
    rm -f "$tmp"
    echo "本番の manifest を取得できません（HTTP ${code}）：$url" >&2
    exit 1
    ;;
esac
