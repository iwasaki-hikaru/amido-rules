#!/bin/bash
# 本番の署名の鍵（本番用 primary と予備 standby の 2 本）を作る。手順の詳細は docs/signing.md。
#
# 使い方：
#   scripts/keygen.sh <保存先のディレクトリ>
#
# - 保存先は、このリポジトリ・隣の ios リポジトリ・ほかの git リポジトリの外にしてください。
#   中を指定すると止めます。秘密鍵を誤ってコミットしないためです。
# - 秘密鍵（32 バイトの seed の Base64）は、<保存先>/rules-signing-primary.key と
#   <保存先>/rules-signing-standby.key に、権限 0600 で書きます。すでにあれば上書きしません。
# - 公開鍵と、このあとの手順（公開鍵の登録、GitHub Secrets への登録、保管）を表示します。
set -euo pipefail
cd "$(dirname "$0")/.."
repo_root=$(pwd -P)
workspace_root=$(cd .. && pwd -P)

if [ $# -ne 1 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
  exit 2
fi

# 保存先の絶対パスを求める（まだなければ、親ディレクトリから求める）
target=$1
if [ -d "$target" ]; then
  target_abs=$(cd "$target" && pwd -P)
else
  parent=$(dirname "$target")
  if [ ! -d "$parent" ]; then
    echo "✘ $parent がありません。先に作ってください" >&2
    exit 1
  fi
  target_abs="$(cd "$parent" && pwd -P)/$(basename "$target")"
fi

# 保存先（またはその上のどれか）が、このリポジトリか隣の ios リポジトリと同じディレクトリなら止める。
# 文字列ではなく、同じファイルか（-ef、inode）で比べる（大文字・小文字の違いや、別名のパスでもすり抜けない）
ios_root="$workspace_root/ios"
dir="$target_abs"
while [ ! -d "$dir" ]; do
  dir=$(dirname "$dir")
done
while :; do
  if [ "$dir" -ef "$repo_root" ] || { [ -d "$ios_root" ] && [ "$dir" -ef "$ios_root" ]; }; then
    echo "✘ 保存先がリポジトリの中です：$target_abs" >&2
    echo "  秘密鍵をコミットしないように、リポジトリの外（例：~/rules-signing-keys）を指定してください" >&2
    exit 1
  fi
  [ "$dir" = "/" ] && break
  dir=$(dirname "$dir")
done
if git -C "$(dirname "$target_abs")" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
  echo "✘ 保存先が git リポジトリの中です：$target_abs" >&2
  echo "  秘密鍵を誤ってコミットしないように、git の管理外のディレクトリを指定してください" >&2
  exit 1
fi

primary="$target_abs/rules-signing-primary.key"
standby="$target_abs/rules-signing-standby.key"
for file in "$primary" "$standby"; do
  if [ -e "$file" ]; then
    echo "✘ $file がすでにあります。上書きしません（作り直すなら、中身を確かめてから自分で消してください）" >&2
    exit 1
  fi
done

mkdir -p "$target_abs"
chmod 700 "$target_abs"

echo "▶ rulestool をビルドします" >&2
swift build -c release --product rulestool >&2
rulestool="$(swift build -c release --show-bin-path)/rulestool"

primary_public=$("$rulestool" keygen --out "$primary")
standby_public=$("$rulestool" keygen --out "$standby")

cat << EOF

✔ 鍵を 2 本作りました（秘密鍵の中身は表示しません）。
  本番用（primary）：$primary
  予備（standby）  ：$standby

公開鍵（Base64）：
  primary：$primary_public
  standby：$standby_public

━━ このあとの手順 ━━

1. 公開鍵を rules リポジトリに登録する（PR で）
   keys/trusted-public-keys.json を次の内容にします：

{"keys":[{"id":"primary","publicKey":"$primary_public"},{"id":"standby","publicKey":"$standby_public"}]}

2. 同じ 2 本の公開鍵を、iOS アプリ（ios/App/Config/AppConfig.swift の公開鍵の定数）に登録する
   1. の JSON を保存したあと、ios リポジトリで次を実行すると写せます（--apply を付けるまでは表示だけ）：
       swift scripts/configure.swift --install-keys --apply
   アプリはどちらかの鍵で検証できれば受け入れます。2 本とも入れたアプリを公開してから、鍵を入れ替えられるようになります。

3. 本番用（primary）の秘密鍵を、GitHub の production environment の Secret「RULES_SIGNING_KEY」に登録する
   - GitHub の画面：Settings → Environments → production → Environment secrets → Add secret
     名前 RULES_SIGNING_KEY、値は $primary の中身（1 行）
   - gh を使う場合（中身を画面に出さずに登録できる）：
       gh secret set RULES_SIGNING_KEY --env production --repo <owner>/<rules リポジトリ> < "$primary"

4. 秘密鍵を保管する
   - 2 本とも、パスワードマネージャーなど、GitHub の外の安全な場所に保管してください。
     GitHub Secrets は、登録したあとに中身を読み出せません。
   - 予備（standby）の秘密鍵は、GitHub には登録しません。本番用が漏れたときや、入れ替えのときだけ使います。
   - 保管が終わったら、このファイルは消してかまいません（ゴミ箱を経由しない rm で）：
       rm "$primary" "$standby"

詳しくは docs/signing.md を参照してください。
EOF
