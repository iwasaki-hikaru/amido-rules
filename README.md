# rules（Safari 向けコンテンツブロッカーのルール）

iPhone 向けの Safari コンテンツブロッカー「あみど」が使う、ブロックのルールを作って配信するリポジトリです。ルールの作り方と中身を公開するために、このリポジトリは公開しています（アプリのコードは別の非公開リポジトリです）。

## しくみ

```
sources.yml（上流のリスト）＋ custom/（自作ルール）
  → rulestool build   取得 → カテゴリごとにまとめる → 変換（SafariConverterLib）→ 検査 → WebKit でコンパイル
  → rulestool sign    manifest.json に Ed25519 で署名（CI の production environment の中だけ）
  → rulestool site    site/ のページと v1/ をまとめて dist/ にする
  → wrangler deploy   Cloudflare Workers の Worker amido（静的アセットだけ）に公開 → https://amido.goalspace.jp/
  → アプリ            manifest の署名を検証 → 各リストの SHA-256 を検証 → 拡張ごとに組み立てて Safari に渡す
```

- 配信するファイルの形式（manifest・署名・鍵・リストの名前・ダミールール・許可サイトのルール）は、[docs/format.md](docs/format.md) で決めています。アプリとの取り決めなので、形式を変えるときは両方を同時に直します。
- ツール（rulestool）は Swift で書いていて、外部の依存はありません。WebKit で実際にコンパイルして確かめるので、macOS でだけ動きます。
  - CI では、macOS 26 の WebKit に加えて、iOS 18.6 のシミュレーターの WebKit でも、アプリが Safari に渡す形の JSON をコンパイルします（`.github/scripts/ios-webkit-check.sh`。通らなければ公開しない）。
  - iOS 17 は、手動のワークフロー `ios17-webkit.yml` で確かめます（iOS 17 のシミュレーターがある macos-14 のイメージは、2026-11-02 に使えなくなります）。
  - シミュレーターで確かめられるのは「その版の WebKit が読める書き方か」までです。件数や大きさで実機が失敗しないかは、実機で確かめます（アプリの `docs/device-verification.md`）。

### カテゴリと拡張

| カテゴリ | 区分 | 入る拡張 | 入力 |
|---|---|---|---|
| `basic` | 無料 | 基本（BlockerBasic） | EasyList ＋ `custom/basic.txt` |
| `annoyance` | プレミアム（迷惑な表示） | プラス（BlockerPlus）の 1 番目 | Fanboy's Social Blocking List ＋ Fanboy's Notifications List ＋ `custom/annoyance.txt`（Fanboy のリストから外す例外など） |
| `privacy` | プレミアム（トラッキング防止） | プラス（BlockerPlus）の 2 番目 | EasyPrivacy（CNAME の節を除く。ただし、その節の中でも `.jp` を含む行は残す） |
| `scam` | プレミアム（第 2 段階） | プラス（BlockerPlus）の 3 番目 | `custom/scam.txt`（今は空） |

- ルールが 1 件もないカテゴリは、manifest に載せません。
- basic・annoyance・privacy には、ツールが動作確認ページ（`/check`）用のルールを 1 件ずつ足します（`<配信ホスト>##.cb-check-basic`・`<配信ホスト>##.cb-check-annoyance`・`<配信ホスト>##.cb-check-privacy`）。annoyance と privacy は同じ拡張に入りますが、アプリのホームで別々にオフにできるので、`/check` でも別々に判定します。
- EasyPrivacy の CNAME の節（特定のサイトのサブドメインを 1 件ずつ並べたもの。全体の約 6 割）は、件数を抑えるために除いています（`sources.yml` の `exclude_sections` と `keep_lines_containing`。書き方は [docs/format.md](docs/format.md#節を除くexclude_sectionskeep_lines_containing)）。

### 例外ルールが効く範囲

Safari の `ignore-previous-rules`（`@@||example.jp^$document` などの例外ルールを変換したもの）は、**同じ拡張のリストの中で、それより前にあるすべてのルール**に効きます。別の拡張のルールには効きません。

アプリは、拡張ごとにカテゴリの配列を決まった順番（プラスでは annoyance → privacy → scam）でつなぎ、末尾に許可サイトのルールを 1 件足します。そのため、privacy や scam の例外ルールは、前にある annoyance のルールにも効きます。

rulestool は「拡張の中で 2 番目以降のカテゴリ（今は privacy と scam）に、**すべての URL に効く**例外ルール（`url-filter` が `.*` など）があれば失敗」にしています。これがあると、前のカテゴリのルールをサイトごと打ち消してしまうためです。URL やホストを限った例外（EasyPrivacy の例外はすべてこの形）は通します。そのうち、ホストだけを限ったものの件数は `report.json` と `summary.md` に出します（[docs/format.md](docs/format.md)）。basic と annoyance は拡張の 1 番目なので、どんな例外ルールも書けます。

許可サイトのルールは末尾にあるので、その拡張のすべてのカテゴリに効きます（意図どおり）。

## 構成

| パス | 内容 |
|---|---|
| `sources.yml` | 上流のリストと自作ルールの一覧（YAML の一部だけを使う。書式は docs/format.md） |
| `custom/` | 自作ルール。各ルールのすぐ上に `! 根拠: <URL> (YYYY-MM-DD)` が必要 |
| `config/budgets.json` | 拡張ごとの件数・バイト数の予算と、件数の急な変化の検査のしきい値 |
| `config/denylist.json` | ライセンス上使えないリスト（URL に含む文字列。280blocker など） |
| `config/distribution.json` | 配信ホスト（アプリに埋め込むもの。`amido.goalspace.jp`）と `min_app_build` |
| `keys/trusted-public-keys.json` | 署名の公開鍵（アプリに埋め込むものと同じにする） |
| `Package.swift`・`Sources/`・`Tests/` | rulestool とそのテスト |
| `site/` | 配信サイトのページ（プライバシー・規約・サポート・ライセンス・動作確認・特定商取引法に基づく表記）、`demo/` の見本のページ（ニュース・レシピ・SNS）と `_headers` |
| `wrangler.jsonc` | Cloudflare Workers の設定（Worker 名 `amido`、静的アセットだけ。workers.dev とプレビュー URL は使わず、カスタムドメインは管理画面でつなぐ） |
| `deploy/` | wrangler の版の固定（`package.json` と `package-lock.json`。CI では `npm ci`） |
| `scripts/` | `fetch-converter.sh`（変換器のビルド）、`build-local.sh`（手元での一式の作成）、`keygen.sh`（本番の鍵の作成）、`first-deploy.sh`（最初の 1 回だけ、運営者の手元から Worker を作り、サイトのページだけを公開する） |
| `.github/workflows/` | `pr.yml`・`publish.yml`・`rollback.yml` |
| `.github/scripts/` | CI の補助（配信の設定の検査、Node での署名の検証、本番の manifest の取得、版の番号の決定） |
| `docs/` | [format.md](docs/format.md)（配信形式）、[runbook.md](docs/runbook.md)（運用の手順）、[licensing.md](docs/licensing.md)（ライセンスの判断材料）、[signing.md](docs/signing.md)（署名の鍵） |
| `LICENSE-rules`・`LICENSE`・`NOTICE` | ルールのライセンス（CC BY-SA 3.0）、ツールのコードのライセンス（MIT）、権利表記 |

`build/`・`dist/`・`.tools/`・`.local/`・`deploy/node_modules/` は、作業用なので git に入れません。

## 手元でビルドする

必要なもの：macOS、Xcode 26.6（Swift 6）、`jq`。Node（22 以降）があれば、署名と設定の検査も手元で動きます。

```bash
# 1. 変換器を用意する（初回だけ。SafariConverterLib と依存 3 つを取得して、ソースからビルドする）
scripts/fetch-converter.sh

# 2. テスト
swift test

# 3. 一式を作る（build/out → dist/）。上流のリストのキャッシュ（build/sources）があれば、取得し直さない
scripts/build-local.sh
scripts/build-local.sh --online          # 上流のリストを取得し直す
scripts/build-local.sh --host localhost  # /check 用のルールのホストを変える（シミュレーターで確かめるとき）
scripts/build-local.sh --dev-sign        # 開発用の鍵（.local/）で署名する。本番の鍵は使わない

# 4. 手元で配信する
python3 -m http.server 8787 --bind 127.0.0.1 --directory dist

# 配信の設定（wrangler.jsonc・_headers・site・deploy）の検査。CI と同じもの
node .github/scripts/check-config.mjs
```

rulestool は直接も使えます（`rules/` で実行する）。

```bash
swift run -c release rulestool --help
swift run -c release rulestool build --help
```

| コマンド | 内容 |
|---|---|
| `build` | 取得・変換・検査をして、`<out>/v1/manifest.json`（署名なし）・`<out>/v1/lists/*`・`report.json`・`summary.md` を書く |
| `sign` | manifest に署名する（秘密鍵は環境変数 `RULES_SIGNING_KEY`。公開鍵が鍵のファイルになければ署名しない） |
| `verify` | 署名と各リストを検証する（`--dir` か `--base-url`） |
| `compare` | 前の manifest と比べて `changed` か `unchanged` を出す |
| `site` | `site/` と `v1/` をまとめて `dist/` にする（`--keep-previous` で本番のリストも残す） |
| `keygen` | 署名の鍵を作る |
| `compile-check` | JSON のリストを macOS の WebKit でコンパイルする |
| `fixture` | iOS アプリのテスト用の小さな配信一式を書く（RFC 8032 のテスト用の鍵。本番では使わない） |

終了コードは、0 が成功（警告は可）、1 が検査の失敗、2 が使い方の誤りです。

自作ルールの足し方と、週 1 回の作業は [docs/runbook.md](docs/runbook.md) にあります。

## 変換器（SafariConverterLib）

- AdGuard の [SafariConverterLib](https://github.com/AdguardTeam/SafariConverterLib) の ConverterTool を使います。タグ `v4.3.0`（コミット `7a2e93f0afa70479cc59985f332025236c3f0c39`）をソースからビルドします（`scripts/fetch-converter.sh`）。タグのコミットが違えば止めます。
- ビルドのとき、SwiftPM が依存パッケージを 3 つ取得します。`--force-resolved-versions` で、変換器の `Package.resolved` の版に固定しています。
  - PunycodeSwift 3.0.0（`30a462bd…`）
  - swift-argument-parser 1.5.0（`41982a36…`）
  - swift-psl 1.1.43（`7ccee9d5…`）
- 変換器は GPLv3 です。別のプログラムとして実行するだけで、rulestool にはリンクしません。アプリにもサイトにも含めず、配布しません。
- 呼び出し方：`convert --safari-version 17 --advanced-blocking false --input-path <file>`。iOS 17 で使えないキーが出ないように、Safari の版を明示しています。
- 変換のあと、`resource-type` が `document` だけの block ルールに `load-context: ["top-frame"]` を足します（`Sources/RulesKit/DocumentRuleScope.swift`）。EasyList の `$popup` と `$document` はポップアップとページそのものを止める指定ですが、変換器の出力のままだと、WebKit では iframe の中のページにも当たります（iOS 17・18 でも 26 でも）。そのため、広告ブロック対策の仕組み（html-load.com など）を使うサイトが、本文を隠して「広告の表示を許可して」という全面の警告を出していました（2026-09-29 に WebKit で確認）。足した件数は `build/out/summary.md` の「トップの文書に限った件数」に出ます。
- CI では、ビルドした変換器をコミットごとにキャッシュします。

## CI

| ワークフロー | きっかけ | すること |
|---|---|---|
| `pr.yml` | PR | 設定の検査、テスト、ルールの変換と検査（WebKit でのコンパイルを含む）、dist の組み立て。秘密情報は使わない |
| `publish.yml` | main への push（配信に関係するファイルだけ）、週 1 回（月曜 03:37 JST）、手動 | 下の 3 つのジョブ |
| `rollback.yml` | 手動だけ | 前の版に戻す（`wrangler rollback`、または GitHub Release の一式を公開し直す） |

`publish.yml` のジョブ：

1. **build**（秘密情報なし）：テスト、変換と検査、本番の manifest との件数の比較。結果を artifact に保存する
2. **deploy**（`production` environment、main だけ）：本番と比べる（同じなら、週 1 回の実行では何もしない）→ 署名 → rulestool と Node の crypto の両方で検証 → `rulestool site --keep-previous` → `wrangler deploy` → 本番を取り直して検証（失敗したら自動で `wrangler rollback`）→ GitHub Release に保管
3. **report-failure**（`issues: write` だけ）：週 1 回の実行が失敗したら issue を作る

- アクションは GitHub 公式のもの（checkout・cache・upload-artifact・download-artifact）だけを、コミットの SHA で固定しています。
- `pull_request_target` は使いません。
- ランナーは `macos-26`、Xcode は `DEVELOPER_DIR` で 26.6 を明示して選びます。
- 秘密情報は `production` environment にだけ置きます：`RULES_SIGNING_KEY`（署名の秘密鍵、[docs/signing.md](docs/signing.md)）、`CLOUDFLARE_API_TOKEN`、`CLOUDFLARE_ACCOUNT_ID`（goalspace と同じアカウントの ID）。
  - `CLOUDFLARE_API_TOKEN` は、アカウントが持つトークン（Account API token）で、範囲を「Specified Workers」の `amido` だけ、役割を「Editor」にしたものです。ゾーンの権限は付けず、有効期限を付けます（[docs/runbook.md](docs/runbook.md#最初の公開の準備)）。同じアカウントにある goalspace の Worker やゾーン（DNS など）には触れられません。
  - この範囲のトークンでは Worker を新しく作れません。最初の 1 回だけ、運営者が手元から `scripts/first-deploy.sh` で作ります。
- 配信ホストが仮の値（`PLACEHOLDER`）のあいだは、build ジョブだけが動き、公開はしません。
- 本番と比べて件数が大きく変わると（30% 超かつ 100 件超）、PR の検査も公開も止まります。意図した変化なら、PR にはラベル `allow-count-change` を付け、公開は手動の実行で `allow_count_change` を指定します（[docs/runbook.md](docs/runbook.md#件数の変化で-ci-が止まったとき)）。

## 配信

| パス | 内容 | キャッシュ |
|---|---|---|
| `/v1/manifest.json` | manifest（署名の対象） | 5 分 |
| `/v1/manifest.json.sig` | 署名（Base64） | 5 分 |
| `/v1/lists/<category>.<hash8>.json` | ルールのリスト（名前に中身のハッシュが入る） | 1 年（immutable） |
| `/privacy`・`/terms`・`/support`・`/licenses`・`/check`・`/tokushoho` | サイトのページ | 既定 |
| `/demo/news`・`/demo/recipe`・`/demo/social` | 見本のページ（スクリーンショットと動作の確かめ用。検索には出さない） | 既定 |

- ページの URL は、拡張子なしの形（`/privacy`・`/demo/social` など）で書きます（`wrangler.jsonc` の `html_handling` が `auto-trailing-slash` のため）。
- Cloudflare Workers の静的アセットだけを使います。`wrangler.jsonc` に `main`・`cache`・`run_worker_first` を入れると、無料プランでもリクエストが Worker の実行として数えられるので、入れません（CI で検査しています）。
- 公開のたびに、本番の manifest が指している前の版のリストも一緒に置きます。更新の途中の利用者が 404 にならないようにするためです。

### 独自ドメインと共有アカウント

- 配信元は `https://amido.goalspace.jp/` です（カスタムドメイン）。Cloudflare のアカウントは goalspace と同じもので、その中の Worker `amido` で配信します（2026-10-07 に決定）。
  - 前は、amido 専用の Cloudflare アカウントと `www.amido.workers.dev`（Worker 名 `www`）にしていました（2026-10-01 に決定。2026-10-07 に amido.goalspace.jp に変えた。アプリをまだ公開していなかったので変えられた）。
- 独自ドメインにした理由：
  - Cloudflare は、本番には workers.dev ではなく独自ドメインを使うことをすすめています（[Cloudflare のドキュメント](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)）。
  - workers.dev のサブドメインはアカウントに 1 つで、同じアカウントの goalspace と共有になります。workers.dev のままだと、goalspace の都合でサブドメインを変えたときに、あみどの配信ホストも変わって壊れます。
  - 問い合わせ先（amido@goalspace.jp）と同じドメインになります。
- 共有のアカウントにした理由：このためだけに別のアカウントを作るのはもったいないため（運営者）。代わりに、CI のトークンを Worker `amido` だけに絞り、goalspace の Worker やゾーンには触れられないようにしています（上の「CI」）。
- **配信ホストはアプリに埋め込むので、アプリを公開したあとは変えられません。** 変えると、配布済みのアプリがルールを更新できなくなる前提で扱います。`config/distribution.json` の `host` と、アプリの `AppConfig.distributionHost` を同じにします。`wrangler.jsonc` の `name`（`amido`）も変えません（変えると、ドメインがつながっていない別の Worker ができる）。
- ドメインは、Cloudflare の管理画面で Worker `amido` につなぎます（Settings → Domains & Routes → Add → Custom domain）。DNS のレコードは先に作らず、Cloudflare に作らせます。`wrangler.jsonc` には `route`・`routes` を書かず、`workers_dev` と `preview_urls` は `false` にします（CI のトークンにゾーンの権限がないため。`check-config.mjs` で検査しています）。
- CI は、公開の前に本番の manifest を取りに行き、名前解決できないと止まります。そのため、最初の 1 回は、運営者が手元から `scripts/first-deploy.sh` で Worker を作り（サイトのページだけ。`/v1/manifest.json` はまだ 404）、ドメインをつないでから、CI の公開を承認します（[docs/runbook.md の「最初の公開の準備」](docs/runbook.md#最初の公開の準備)）。
- **goalspace.jp の登録の更新が切れると、アプリはルールを更新できなくなります**（今のルールのまま動き続ける）。ほかの人がそのドメインを取ると、サイトのページを置き換えたり、過去に正しく署名された版（GitHub Release にある）を配り直したりできます（[docs/signing.md](docs/signing.md#漏れたときの影響の範囲)）。goalspace.jp の更新を切らさないようにします。
- goalspace.jp のゾーンの設定は、amido.goalspace.jp のサイトとアプリの取得にも効きます。Bot Fight Mode、Web Analytics の自動の設定、HTML を書き換える機能（メールアドレスの難読化・Rocket Loader など）、リダイレクトのルール・ページルール・goalspace の Worker のルート、WAF のルールで、プライバシーポリシーの「Cookie・解析ツールを使わない」「記録を残さない」と食い違ったり、アプリや CI の取得が止まったりすることがあります。公開の前と、ゾーンの設定を変えるときに確かめます（[docs/runbook.md](docs/runbook.md#最初の公開の準備) の手順 3）。
- 同じアカウントの管理者は、Worker `amido` とドメインのつなぎ先も変えられます。アカウントのメンバーと 2 段階認証は、署名の鍵と同じくらい大事に守ります（[docs/runbook.md](docs/runbook.md#最初の公開の準備) の手順 2）。

## ライセンス

- ルール（`custom/` と、配信する変換後のリスト）：CC BY-SA 3.0。[LICENSE-rules](LICENSE-rules) と [NOTICE](NOTICE) を参照してください。EasyList（basic）と、Fanboy's Social Blocking List・Fanboy's Notifications List（annoyance）と、EasyPrivacy（privacy。CNAME の節は `.jp` を含む行を除いて外している）を変換して使っています。著作者は、どれも The EasyList authors です。このリポジトリと配信サイトは、Fanboy や EasyList・EasyPrivacy の作者とは関係がありません。
- ツールのコード（`Sources/`・`Tests/`・`scripts/`・`tools/`・`.github/`、`Package.swift`、`wrangler.jsonc`・`config/`・`deploy/` の設定ファイル）：MIT License。[LICENSE](LICENSE) を参照してください。
- それ以外（`site/` のページ・画像・スタイル・スクリプト、`docs/` の文書など）：権利は運営者にあります。
- 判断材料は [docs/licensing.md](docs/licensing.md) にまとめています。

## 公開前に埋める値

仮の値は「【要記入：…】」です。リポジトリの中を検索すると見つかります。手順は [docs/runbook.md の「最初の公開の準備」](docs/runbook.md#最初の公開の準備) にあります。
