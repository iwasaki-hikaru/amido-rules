# rules（Safari 向けコンテンツブロッカーのルール）

iPhone 向けの Safari コンテンツブロッカー「【要記入：アプリ名】」が使う、ブロックのルールを作って配信するリポジトリです。ルールの作り方と中身を公開するために、このリポジトリは公開しています（アプリのコードは別の非公開リポジトリです）。

## しくみ

```
sources.yml（上流のリスト）＋ custom/（自作ルール）
  → rulestool build   取得 → カテゴリごとにまとめる → 変換（SafariConverterLib）→ 検査 → WebKit でコンパイル
  → rulestool sign    manifest.json に Ed25519 で署名（CI の production environment の中だけ）
  → rulestool site    site/ のページと v1/ をまとめて dist/ にする
  → wrangler deploy   Cloudflare Workers（workers.dev、静的アセットだけ）に公開
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
| `annoyance` | プレミアム | プラス（BlockerPlus）の 1 番目 | `custom/annoyance.txt` |
| `scam` | プレミアム（第 2 段階） | プラス（BlockerPlus）の 2 番目 | `custom/scam.txt`（今は空） |

- ルールが 1 件もないカテゴリは、manifest に載せません。
- basic と annoyance には、ツールが動作確認ページ（`/check`）用のルールを 1 件ずつ足します（`<配信ホスト>##.cb-check-basic` と `<配信ホスト>##.cb-check-annoyance`）。

### 例外ルールが効く範囲

Safari の `ignore-previous-rules`（`@@||example.jp^$document` などの例外ルールを変換したもの）は、**同じ拡張のリストの中で、それより前にあるすべてのルール**に効きます。別の拡張のルールには効きません。

アプリは、拡張ごとにカテゴリの配列を決まった順番（プラスでは annoyance → scam）でつなぎ、末尾に許可サイトのルールを 1 件足します。そのため、scam に例外ルールがあると、前にある annoyance のルールまで打ち消してしまいます。

これを防ぐため、rulestool は「拡張の中で 2 番目以降のカテゴリ（今は scam）に `ignore-previous-rules` があれば失敗」にしています。これで「例外ルールは同じカテゴリの中だけで効く」が保たれます。basic と annoyance は拡張の 1 番目なので、例外ルールを書けます。

許可サイトのルールは末尾にあるので、その拡張のすべてのカテゴリに効きます（意図どおり）。

## 構成

| パス | 内容 |
|---|---|
| `sources.yml` | 上流のリストと自作ルールの一覧（YAML の一部だけを使う。書式は docs/format.md） |
| `custom/` | 自作ルール。各ルールのすぐ上に `! 根拠: <URL> (YYYY-MM-DD)` が必要 |
| `config/budgets.json` | 拡張ごとの件数・バイト数の予算と、件数の急な変化の検査のしきい値 |
| `config/denylist.json` | ライセンス上使えないリスト（URL に含む文字列。280blocker など） |
| `config/distribution.json` | 配信ホスト（アプリに埋め込むもの）と `min_app_build` |
| `keys/trusted-public-keys.json` | 署名の公開鍵（アプリに埋め込むものと同じにする） |
| `Package.swift`・`Sources/`・`Tests/` | rulestool とそのテスト |
| `site/` | 配信サイトのページ（プライバシー・規約・サポート・ライセンス・動作確認）と `_headers` |
| `wrangler.jsonc` | Cloudflare Workers の設定（静的アセットだけ） |
| `deploy/` | wrangler の版の固定（`package.json` と `package-lock.json`。CI では `npm ci`） |
| `scripts/` | `fetch-converter.sh`（変換器のビルド）、`build-local.sh`（手元での一式の作成）、`keygen.sh`（本番の鍵の作成） |
| `.github/workflows/` | `pr.yml`・`publish.yml`・`rollback.yml` |
| `.github/scripts/` | CI の補助（配信の設定の検査、Node での署名の検証、本番の manifest の取得、版の番号の決定） |
| `docs/` | [format.md](docs/format.md)（配信形式）、[runbook.md](docs/runbook.md)（運用の手順）、[licensing.md](docs/licensing.md)（ライセンスの判断材料）、[signing.md](docs/signing.md)（署名の鍵） |
| `LICENSE-rules`・`NOTICE` | ルールのライセンス（CC BY-SA 3.0）と権利表記 |

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
- 秘密情報は `production` environment にだけ置きます：`RULES_SIGNING_KEY`（署名の秘密鍵、[docs/signing.md](docs/signing.md)）、`CLOUDFLARE_API_TOKEN`（Account → Workers Scripts → Edit だけのトークン）、`CLOUDFLARE_ACCOUNT_ID`。
- 配信ホストが仮の値（`PLACEHOLDER`）のあいだは、build ジョブだけが動き、公開はしません。
- 本番と比べて件数が大きく変わると（30% 超かつ 100 件超）、PR の検査も公開も止まります。意図した変化なら、PR にはラベル `allow-count-change` を付け、公開は手動の実行で `allow_count_change` を指定します（[docs/runbook.md](docs/runbook.md#件数の変化で-ci-が止まったとき)）。

## 配信

| パス | 内容 | キャッシュ |
|---|---|---|
| `/v1/manifest.json` | manifest（署名の対象） | 5 分 |
| `/v1/manifest.json.sig` | 署名（Base64） | 5 分 |
| `/v1/lists/<category>.<hash8>.json` | ルールのリスト（名前に中身のハッシュが入る） | 1 年（immutable） |
| `/privacy`・`/terms`・`/support`・`/licenses`・`/check` | サイトのページ | 既定 |

- Cloudflare Workers の静的アセットだけを使います。`wrangler.jsonc` に `main`・`cache`・`run_worker_first` を入れると、無料プランでもリクエストが Worker の実行として数えられるので、入れません（CI で検査しています）。
- 公開のたびに、本番の manifest が指している前の版のリストも一緒に置きます。更新の途中の利用者が 404 にならないようにするためです。

### workers.dev を使うことのリスク

- 配信元は `<Worker 名>.<アカウントのサブドメイン>.workers.dev` です。Cloudflare は、workers.dev のサブドメインを「無料のウェブサイトとして扱い、個人や趣味のプロジェクト向け」と説明しています（業務上重要な用途向けではない。[Cloudflare のドキュメント](https://developers.cloudflare.com/workers/configuration/routing/workers-dev/)）。禁止はされていないので、リスクを記録したうえで使っています。
- **配信ホストはアプリに埋め込むので、アプリを公開したあとは変えられません。** Worker の名前やアカウントのサブドメインを変えたとき、古い URL がどうなるか（転送されるか）は、Cloudflare のドキュメントに書かれていません。変えると、配布済みのアプリがルールを更新できなくなる前提で扱います。
- そのため、Worker の名前とサブドメインは、アプリの公開前に確定します（`config/distribution.json` の `host`、`wrangler.jsonc` の `name`、アプリの `AppConfig.distributionHost` の 3 か所を同じにする）。
- CI から初めてデプロイする前に、Cloudflare の管理画面で workers.dev のサブドメインを一度作っておく必要があります。

## ライセンス

- ルール（`custom/` と、配信する変換後のリスト）：CC BY-SA 3.0。[LICENSE-rules](LICENSE-rules) と [NOTICE](NOTICE) を参照してください。EasyList を変換して使っています。
- ツール（`Sources/`・`Tests/`・`scripts/`・`.github/`・`site/` など）：**ライセンスは未定です。** 決まるまで LICENSE は置いていません。
- 判断材料は [docs/licensing.md](docs/licensing.md) にまとめています。

## 公開前に埋める値

仮の値は「PLACEHOLDER」と「【要記入：…】」です。リポジトリの中を検索すると見つかります。手順は [docs/runbook.md の「最初の公開の準備」](docs/runbook.md#最初の公開の準備) にあります。
