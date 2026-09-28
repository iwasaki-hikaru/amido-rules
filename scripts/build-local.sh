#!/bin/bash
# 手元で、配信するもの一式（dist/）を作る。開発用（本番の公開は CI の publish.yml だけが行う）。
#
# 使い方：
#   scripts/build-local.sh [--host <ホスト>] [--online] [--dev-sign] [--] [rulestool build に渡す引数…]
#
#   --host <ホスト>  /check 用のルールのホストを変える（例：シミュレーターで確かめるなら localhost）
#   --online         上流のリストを取得し直す（既定では、build/sources にキャッシュがあれば --offline で動かす）
#   --dev-sign       開発用の鍵で署名する。鍵は .local/dev-signing-key（なければ作る）、
#                    公開鍵は .local/dev-public-keys.json に書く。本番の keys/trusted-public-keys.json は使わない
#   それ以外の引数は、そのまま rulestool build に渡す（例：--skip-compile-check、--version 2026.10.05.2）
#
# 流れ：変換器を用意 → rulestool build（build/out）→（--dev-sign なら署名と検証）→ rulestool site（dist/）
set -euo pipefail
cd "$(dirname "$0")/.."

host=""
online=false
dev_sign=false
passthrough=()
while [ $# -gt 0 ]; do
  case "$1" in
    --host)
      [ $# -ge 2 ] || { echo "--host にホストを指定してください" >&2; exit 2; }
      host=$2
      shift 2
      ;;
    --online)
      online=true
      shift
      ;;
    --dev-sign)
      dev_sign=true
      shift
      ;;
    --)
      shift
      passthrough+=("$@")
      break
      ;;
    -h | --help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    *)
      passthrough+=("$1")
      shift
      ;;
  esac
done

echo "▶ 変換器を用意します（初回はソースからビルドするので時間がかかります）" >&2
converter=$(scripts/fetch-converter.sh)

echo "▶ rulestool をビルドします" >&2
swift build -c release --product rulestool >&2
rulestool="$(swift build -c release --show-bin-path)/rulestool"

build_args=(build --converter "$converter" --out build/out)
if [ -n "$host" ]; then
  build_args+=(--host "$host")
fi
# 上流のリストのキャッシュがあれば、取得し直さない（何度も試すときに上流へ負荷をかけないため）
if [ "$online" = false ] && compgen -G "build/sources/*.txt" > /dev/null; then
  echo "▶ build/sources のキャッシュを使います（取得し直すなら --online）" >&2
  build_args+=(--offline)
fi
if [ ${#passthrough[@]} -gt 0 ]; then
  build_args+=("${passthrough[@]}")
fi

echo "▶ rulestool ${build_args[*]}" >&2
if ! "$rulestool" "${build_args[@]}"; then
  echo "✘ build に失敗しました。build/out/summary.md と build/out/report.json を見てください" >&2
  if [[ " ${build_args[*]} " == *" --offline "* ]]; then
    echo "  新しい上流のソースを足したときは、--online を付けてもう一度実行してください" >&2
  fi
  exit 1
fi

if [ "$dev_sign" = true ]; then
  key_file=.local/dev-signing-key
  keys_file=.local/dev-public-keys.json
  mkdir -p .local
  chmod 700 .local
  if [ ! -f "$key_file" ]; then
    echo "▶ 開発用の鍵を作ります：$key_file（本番では使わない）" >&2
    public_key=$("$rulestool" keygen --out "$key_file")
    printf '{"keys":[{"id":"dev","publicKey":"%s"}]}\n' "$public_key" > "$keys_file"
  elif [ ! -f "$keys_file" ]; then
    echo "✘ $keys_file がありません。$key_file を消してから、もう一度実行してください（鍵を作り直します）" >&2
    exit 1
  fi
  echo "▶ 開発用の鍵で署名します" >&2
  RULES_SIGNING_KEY=$(cat "$key_file") "$rulestool" sign --manifest build/out/v1/manifest.json --keys "$keys_file"
  "$rulestool" verify --dir build/out --keys "$keys_file"
  if command -v node > /dev/null; then
    node .github/scripts/verify-manifest.mjs --dir build/out --keys "$keys_file"
  fi
fi

echo "▶ rulestool site で dist/ を組み立てます" >&2
"$rulestool" site --site site --rules build/out --out dist

cat >&2 << EOF

✔ dist/ に配信する一式を作りました。

手元で配信する（Mac から、シミュレーターの Safari からも開ける）：
  python3 -m http.server 8787 --bind 127.0.0.1 --directory dist

  - 動作確認のページ：http://localhost:8787/check.html
  - manifest：http://localhost:8787/v1/manifest.json
  - この簡易サーバーは /privacy → privacy.html の変換や _headers の反映をしません。
    本番と同じ動きで確かめるなら：cd deploy && npm ci && npx wrangler dev --config ../wrangler.jsonc
    （wrangler を node_modules に入れます。http://localhost:8787/check で開けます）
  - /check の枠を隠すルールのホストは ${host:-config/distribution.json の host} です。
    シミュレーターで「有効」になるか確かめるなら、--host localhost で作り直してください。
EOF
if [ "$dev_sign" = true ]; then
  cat >&2 << EOF
  - 署名は開発用の鍵です（公開鍵：$(jq -r '.keys[0].publicKey' .local/dev-public-keys.json)）。
    アプリの Debug ビルドで読み込ませる方法は、ios リポジトリの README を参照してください。
EOF
else
  cat >&2 << EOF
  - 署名していないので、アプリはこの manifest を受け入れません（署名するなら --dev-sign）。
EOF
fi
