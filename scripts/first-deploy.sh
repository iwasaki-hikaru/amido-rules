#!/bin/bash
# 最初の 1 回だけ、運営者の手元から、サイトのページだけ（v1/ なし）を Cloudflare Workers に公開する。
#
# なぜ要るか：
# - 配信ホスト（カスタムドメイン）は、Cloudflare の管理画面で Worker につなぐ。つなぐには、Worker が先にあることが要る。
# - CI のトークンは「この Worker だけ」に絞る（goalspace の Worker と同じアカウントのため）。絞ったトークンでは Worker を作れない。
# - CI は公開の前に本番の manifest を取りに行き、名前解決できないと止まる。
# そこで、ここで Worker を作り（v1/ を含めないので、本番の manifest はまだない＝404）、管理画面でドメインをつないでから、
# CI の公開（publish.yml）を承認する。2 回目からは CI だけが公開する。本番で動いている Worker には使わない（v1/ が消える）。
#
# 使い方：scripts/first-deploy.sh
#   goalspace と同じ Cloudflare アカウントの ID を聞かれる（管理画面の URL の dash.cloudflare.com/<ID>/… の部分）。
#   wrangler にログインしていなければ、ブラウザでのログインを求める。
#   手順の全体は docs/runbook.md の「最初の公開の準備」。
set -euo pipefail
cd "$(dirname "$0")/.."

for command in node npm perl; do
  command -v "$command" >/dev/null || { echo "$command がありません" >&2; exit 1; }
done

# 設定が公開できる形か（カスタムドメインなら workers_dev が false・routes なし、など）
node .github/scripts/check-config.mjs >/dev/null || {
  echo "設定の検査に通りません。node .github/scripts/check-config.mjs で内容を確かめてください" >&2
  exit 1
}

host=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("config/distribution.json", "utf8")).host)')
name=$(node -e '
  const text = require("fs").readFileSync("wrangler.jsonc", "utf8");
  const match = /"name"\s*:\s*"([^"]+)"/.exec(text);
  console.log(match ? match[1] : "");
')
if [ -z "${name}" ]; then
  echo "wrangler.jsonc の name を読めません" >&2
  exit 1
fi

# 公開先のアカウントを固定する（ログインしたユーザーが複数のアカウントに入っていても、ほかに出さないように）。
# 環境変数のトークンがあると、それが使われてしまうので外す（ここでは運営者のログインを使う）
unset CLOUDFLARE_API_TOKEN CLOUDFLARE_API_KEY CLOUDFLARE_EMAIL
read -r -p "goalspace と同じ Cloudflare アカウントの ID（32 文字）： " account_id
if ! [[ "${account_id}" =~ ^[0-9a-f]{32}$ ]]; then
  echo "アカウントの ID は 32 文字の英小文字と数字です" >&2
  exit 1
fi
export CLOUDFLARE_ACCOUNT_ID="${account_id}"

# dist/ は手元の開発用の一式（開発用の鍵で署名したものなど）が残っていることがあるので、作り直す。
# CI（rulestool site）と同じく、運営者向けの HTML のコメントと .DS_Store は配信しない
rm -rf dist
mkdir dist
cp -R site/. dist/
find dist -name .DS_Store -delete
find dist -name '*.html' -exec perl -CSD -Mutf8 -0pi -e 's/<!--\s*運営者へ[\s\S]*?-->\n?//g' {} +
if [ -e dist/v1 ]; then
  echo "dist/v1 があります。最初の公開には含めません" >&2
  exit 1
fi
if grep -rl '運営者へ' dist >/dev/null; then
  echo "dist に運営者向けのメモが残っています" >&2
  exit 1
fi

cd deploy
npm ci --no-audit --no-fund
wrangler=./node_modules/.bin/wrangler
"${wrangler}" whoami >/dev/null 2>&1 || "${wrangler}" login
echo
"${wrangler}" whoami
echo
echo "上のアカウントの一覧に、ID ${account_id}（goalspace と同じアカウント）があることを確かめてください。"
echo "Worker「${name}」に、サイトのページだけ（v1/ なし）を公開します。"
echo "同じ名前の Worker がすでにあると、上書きします（誤って作った Worker は、先に管理画面で消してください）。"
read -r -p "続けますか？ [y/N] " answer
if [ "${answer}" != y ] && [ "${answer}" != Y ]; then
  echo "やめました"
  rm -rf ../dist
  exit 1
fi
"${wrangler}" deploy --config ../wrangler.jsonc --message "first deploy (site only)"
rm -rf ../dist

cat <<EOF

公開しました（サイトのページだけ）。次の手順（docs/runbook.md の「最初の公開の準備」の 17.〜21.）：
  1. 管理画面の Workers & Pages → ${name} → Settings → Domains & Routes → Add → Custom domain で「${host}」をつなぐ
     （DNS レコードは自分で作らない。Cloudflare が作る）
  2. 数分待って、https://${host}/privacy が開き、https://${host}/v1/manifest.json が 404 になることを確かめる
  3. Worker「${name}」の Observability（Workers Logs）が無効になっていることを確かめる
  4. この Worker だけに絞ったトークン（Specified Workers → ${name}、Editor）を作り、
     GitHub の production 環境の Environment secrets に CLOUDFLARE_API_TOKEN・CLOUDFLARE_ACCOUNT_ID・RULES_SIGNING_KEY を入れる
  5. 前のホスト向けに承認待ちになっている「ルールの公開」の実行があれば、承認せずに Reject する
  6. ホストを変えたコミットを push したあとの、新しい「ルールの公開」の実行だけを承認する
EOF

# 手元のログインは、goalspace の Worker やゾーンにも届く広い権限なので、使い終わったら消す
read -r -p "wrangler のログインを消しますか？（ほかの作業で使っていなければ消してください） [Y/n] " logout
if [ "${logout}" != n ] && [ "${logout}" != N ]; then
  "${wrangler}" logout
fi
