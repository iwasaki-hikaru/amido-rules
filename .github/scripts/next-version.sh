#!/bin/bash
# 次に公開する manifest の版（YYYY.MM.DD.N）を決めて、標準出力に出す。
#
# アプリは「版が今と違えば適用する」ので、同じ版の名前を 2 度使うと、2 度目の中身が届かない人が出る。
# そこで N は、今日の日付のうち、これまでに使った N（本番の manifest と、タグ rules-<版>）の最大に 1 を足す。
# publish.yml は、デプロイの直前にタグを作って版の名前を確保する。
# 公開に失敗して戻した版もタグが残るので、同じ名前を使い直すことはない。
#
# 使い方：.github/scripts/next-version.sh <今日（UTC、YYYY.MM.DD）> [<本番の manifest.json>] < <タグの一覧>
#   標準入力：使ったタグの名前（rules-YYYY.MM.DD.N か refs/tags/rules-YYYY.MM.DD.N）を 1 行に 1 つ
set -euo pipefail

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  echo "使い方：$0 <YYYY.MM.DD> [<manifest.json>] < <タグの一覧>" >&2
  exit 2
fi
today=$1
live=${2:-}
if ! [[ "$today" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}$ ]]; then
  echo "日付は YYYY.MM.DD で指定してください：$today" >&2
  exit 2
fi

max=0
consider() {
  local version=$1
  if [[ "$version" =~ ^([0-9]{4}\.[0-9]{2}\.[0-9]{2})\.([1-9][0-9]*)$ ]] && [ "${BASH_REMATCH[1]}" = "$today" ]; then
    local n=$((10#${BASH_REMATCH[2]}))
    if [ "$n" -gt "$max" ]; then
      max=$n
    fi
  fi
}

if [ -n "$live" ] && [ -s "$live" ]; then
  consider "$(jq -r '.version // empty' "$live")"
fi
while IFS= read -r line; do
  line=${line#refs/tags/}
  consider "${line#rules-}"
done

echo "$today.$((max + 1))"
