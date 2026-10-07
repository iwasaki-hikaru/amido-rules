#!/bin/bash
# 管理画面で Worker にカスタムドメインをつなげないとき（「Add Domain」で「No zones match」と出るとき）に、
# 運営者の手元から 1 回だけ、配信ホスト（config/distribution.json の host）を Worker につなぐ。
#
# wrangler triggers deploy で、Worker のドメインの設定だけを変える（Worker の中身は変えない）。
# DNS のレコードと証明書は Cloudflare が作る。CI のトークンにはゾーンの権限がないので、ここは運営者のログインで行う。
# つないだあとは、CI の公開（wrangler.jsonc に routes がない wrangler deploy）はドメインに触れないので、そのまま使われる。
#
# 使い方：scripts/attach-domain.sh（先に scripts/first-deploy.sh で Worker を作っておく）
#   goalspace と同じ Cloudflare アカウントの ID を聞かれる（管理画面の URL の dash.cloudflare.com/<ID>/… の部分）。
set -euo pipefail
cd "$(dirname "$0")/.."

for command in node npm; do
  command -v "$command" >/dev/null || { echo "$command がありません" >&2; exit 1; }
done

node .github/scripts/check-config.mjs >/dev/null || {
  echo "設定の検査に通りません。node .github/scripts/check-config.mjs で内容を確かめてください" >&2
  exit 1
}

host=$(node -e 'console.log(JSON.parse(require("fs").readFileSync("config/distribution.json", "utf8")).host)')
if [[ "${host}" == *.workers.dev ]]; then
  echo "配信ホストが workers.dev（${host}）なので、つなぐドメインはありません" >&2
  exit 1
fi
read -r name date < <(node -e '
  const text = require("fs").readFileSync("wrangler.jsonc", "utf8");
  const name = /"name"\s*:\s*"([^"]+)"/.exec(text);
  const date = /"compatibility_date"\s*:\s*"([^"]+)"/.exec(text);
  console.log(`${name ? name[1] : ""} ${date ? date[1] : ""}`);
')
if [ -z "${name}" ] || [ -z "${date}" ]; then
  echo "wrangler.jsonc の name か compatibility_date を読めません" >&2
  exit 1
fi

unset CLOUDFLARE_API_TOKEN CLOUDFLARE_API_KEY CLOUDFLARE_EMAIL
read -r -p "goalspace と同じ Cloudflare アカウントの ID（32 文字）： " account_id
if ! [[ "${account_id}" =~ ^[0-9a-f]{32}$ ]]; then
  echo "アカウントの ID は 32 文字の英小文字と数字です" >&2
  exit 1
fi
export CLOUDFLARE_ACCOUNT_ID="${account_id}"

# ドメインをつなぐためだけの設定（Worker の中身は送らない）。build/ は git に入らない
mkdir -p build
config=build/attach-domain.wrangler.jsonc
HOST="${host}" NAME="${name}" DATE="${date}" node -e '
  const config = {
    name: process.env.NAME,
    compatibility_date: process.env.DATE,
    workers_dev: false,
    preview_urls: false,
    routes: [{ pattern: process.env.HOST, custom_domain: true }],
  };
  require("fs").writeFileSync("build/attach-domain.wrangler.jsonc", JSON.stringify(config, null, 2) + "\n");
'
trap 'rm -f ../build/attach-domain.wrangler.jsonc build/attach-domain.wrangler.jsonc' EXIT

cd deploy
npm ci --no-audit --no-fund
wrangler=./node_modules/.bin/wrangler
# wrangler whoami は、ログインしていなくても終了コード 0 で終わるので、表示で見分ける
if "${wrangler}" whoami 2>&1 | grep -q -i "not authenticated"; then
  "${wrangler}" login
fi
if "${wrangler}" whoami 2>&1 | grep -q -i "not authenticated"; then
  echo "Cloudflare にログインできませんでした" >&2
  exit 1
fi
echo
"${wrangler}" whoami
echo
echo "上のアカウントの一覧に、ID ${account_id}（goalspace と同じアカウント）があることを確かめてください。"
echo "Worker「${name}」に、カスタムドメイン「${host}」をつなぎます（Worker の中身は変えません）。"
echo "ほかの Worker がこのドメインを使っている、または同じ名前の DNS レコードがある、と聞かれたら、n で止めてください。"
read -r -p "続けますか？ [y/N] " answer
if [ "${answer}" != y ] && [ "${answer}" != Y ]; then
  echo "やめました"
  exit 1
fi
"${wrangler}" triggers deploy --config "../${config}"

cat <<EOF

つなぎました。数分待って、https://${host}/privacy が開き、https://${host}/v1/manifest.json が 404 になることを確かめてください。
EOF

read -r -p "wrangler のログインを消しますか？（ほかの作業で使っていなければ消してください） [Y/n] " logout
if [ "${logout}" != n ] && [ "${logout}" != N ]; then
  "${wrangler}" logout
fi
