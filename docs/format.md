# 配信形式（rules とアプリの取り決め）

このリポジトリのツールと iOS アプリは、この文書の形式に従います。形式を変えるときは両方を同時に直し、互換性がなくなる変更では `schema` を上げます。

## カテゴリと拡張

| カテゴリ | 区分 | 入れる拡張 | 拡張の中での順番 |
|---|---|---|---|
| `basic` | 無料 | BlockerBasic | 1 |
| `annoyance` | プレミアム（迷惑な表示） | BlockerPlus | 1 |
| `privacy` | プレミアム（トラッキング防止） | BlockerPlus | 2 |
| `scam` | プレミアム（第 2 段階） | BlockerPlus | 3 |

- 拡張ごとの JSON は、カテゴリの配列をこの順番でつなぎ、末尾に許可サイトのルールを 1 件足したものです。
- **例外ルールが効く範囲**：Safari の `ignore-previous-rules` は、同じ拡張のリストの中で、それより前にあるすべてのルールに効きます。そのため、拡張の中で 2 番目以降のカテゴリ（今は `privacy` と `scam`）の例外ルールは、前のカテゴリ（`annoyance` など）のルールにも効きます。
  - **すべての URL に効く例外ルール**（`ignore-previous-rules` で、`url-filter` が `.*`・`^https?://` など、すべての URL に一致するもの）は、前のカテゴリのルールをサイトごと（`if-domain` がなければすべてのサイトで）打ち消してしまいます。2 番目以降のカテゴリにこれがあれば、ツールは失敗します。`if-domain` や `resource-type` が付いていても失敗にします。「すべての URL に一致する」かは、ホストもパスも違う見本の URL のすべてに当たるかで決めます（`Sources/RulesKit/RuleListLint.swift` の `matchesEveryURL`）。
  - URL やホストを限った例外（`@@||example.com/track.js`、`@@||example.com^$domain=example.jp` など）は通します。一致する読み込みだけで、前のカテゴリのルールが効かなくなります。そのページの本体の読み込みに一致する例外は、前のカテゴリの要素隠しを止めることもあります（ほかの読み込みがすべて例外に当たるときだけ）。
  - ホストだけを限った例外（`@@||example.com^` を変換した形）は、そのホストへの読み込みをほぼすべて許します。件数を `report.json` の各カテゴリの `hostOnlyExceptionRules`（例外ルールの総数は `exceptionRules`）と、`summary.md` の「前のカテゴリにも効く例外ルール」に出します。
  - 拡張の 1 番目のカテゴリ（`basic`・`annoyance`）には、どんな例外ルールも書けます。その例外は、同じカテゴリの中だけで効きます。
- ルールが 1 件もないカテゴリは、manifest に載せません（アプリは「そのカテゴリはない」と扱います）。

## 配信するファイル

```
/v1/manifest.json
/v1/manifest.json.sig
/v1/lists/<category>.<hash8>.json
```

- `<hash8>` は、そのファイルの SHA-256（小文字の 16 進）の先頭 8 文字です。
- 1 ファイルは 25 MiB 未満（Cloudflare の上限）です。

## manifest.json（schema 1）

```json
{
  "lists" : [
    {
      "category" : "basic",
      "rule_count" : 12345,
      "sha256" : "<64 文字の小文字 16 進>",
      "size" : 1234567,
      "url" : "lists/basic.1a2b3c4d.json"
    }
  ],
  "min_app_build" : 1,
  "published_at" : "2026-10-05T03:00:00Z",
  "schema" : 1,
  "version" : "2026.10.05.1"
}
```

| 項目 | 形式 |
|---|---|
| `schema` | 整数。今は `1` |
| `version` | `YYYY.MM.DD.N`（N は 1 以上の整数）。アプリは「今の版と違えば適用する」。大小は比べない |
| `published_at` | RFC 3339 の UTC、秒まで（`2026-10-05T03:00:00Z`） |
| `min_app_build` | 整数（1 以上）。アプリの `CFBundleVersion`（整数）がこれより小さければ、アプリは適用せず「アプリを更新してください」と表示する |
| `lists[].category` | `basic`・`annoyance`・`privacy`・`scam`。この順に並べる。アプリは知らないカテゴリを無視する（前の版のアプリは `privacy` を知らないので、無視する）。同じカテゴリは 1 回だけ |
| `lists[].url` | `lists/<category>.<hash8>.json` の形の相対パス（`^lists/[a-z]+\.[0-9a-f]{8}\.json$`）。manifest.json と同じディレクトリを基準にする。アプリはこれ以外の形（絶対 URL・`..` を含むものなど）を拒否する |
| `lists[].sha256` | ファイルの SHA-256（小文字の 16 進、64 文字） |
| `lists[].size` | ファイルのバイト数（1 以上、25 MiB 未満） |
| `lists[].rule_count` | ファイルの配列の要素数（1 以上） |

- ツールはキーを並べ替えて出力します（読みやすさと差分のため）。アプリは形式には依存せず、受け取ったバイト列のまま署名を検証します。

## manifest.json.sig

- `manifest.json` のバイト列に対する Ed25519 署名（64 バイト）を、Base64（標準、パディングあり）にしたもの。末尾の改行はあってもよい（アプリは前後の空白を除いてから読む）。
- アプリは署名を検証してから、manifest を JSON として読みます。
- CryptoKit の署名は毎回違う値になります（Apple の仕様）。同じ manifest を署名し直すと `.sig` の中身は変わりますが、どれも正しく検証できます。

## 鍵

- 公開鍵：Ed25519 の 32 バイトの生の値を Base64 にしたもの（44 文字）。アプリは最大 2 本（本番用と予備）を埋め込み、どちらかで検証できれば受け入れます。
- 秘密鍵：32 バイトの seed（CryptoKit の `rawRepresentation`）を Base64 にしたもの。GitHub Secrets の `RULES_SIGNING_KEY` だけに置きます。
- `keys/trusted-public-keys.json` に公開鍵を置きます。署名ツールは、秘密鍵から求めた公開鍵がここにないとき、署名しません。

## ルールのリスト（lists/*.json）

- Safari のコンテンツブロッカーの形式の JSON 配列（空でない）。UTF-8。
- SafariConverterLib の ConverterTool で、`--safari-version 17` を指定して変換したもの。
- 変換のあと、ツールが `resource-type` が `["document"]` だけで `load-context` のない block ルールに、`"load-context": ["top-frame"]` を足す（ポップアップとページそのものを止める指定が、iframe の中のページまで止めないようにするため。README の「変換器」）。そのリストは、キーを並べ替えた形で書き直す。

## 絶対に一致しないダミールール

ルールを入れない拡張には、空配列の代わりにこの 1 件だけを渡します（空配列は Safari が読み込めない）。

```json
[{"trigger":{"url-filter":"^https?://never-matches\\.invalid/"},"action":{"type":"block"}}]
```

変換器は、変換結果が 0 件のときに独自のルール（`if-domain: ["domain.com"]` の `ignore-previous-rules`）を出力します。ツールはこれをそのまま使わず、ルールが 0 件のカテゴリは manifest に載せません。

## 許可サイトのルール（アプリが末尾に足す）

変換器が `@@||example.com^$document` を変換した形と同じにし、すべてのドメインを 1 件にまとめます。ドメインは並べ替えます。

```json
{"trigger":{"url-filter":".*","if-domain":["*a.example","*b.example"]},"action":{"type":"ignore-previous-rules"}}
```

## 件数とバイト数の予算

`config/budgets.json` にあります（アプリの `Budgets` と値を合わせる）。1 拡張あたりの件数とバイト数は、その拡張に入るカテゴリの合計に、アプリが足す分（許可サイトの 1 件と、利用者の「自分のルール」）を加えたものです。アプリが足す分は、どの拡張にも足して確かめます。

- 件数は `appReservedRules`（201 件）を足して確かめます。許可サイトの 1 件と、自分のルールの上限 `userRulesMaxCount`（200 件）の合計です。
- バイト数は `appReservedBytes`（256 KiB）を足して確かめます。許可サイトの上限 `allowlistMaxDomains`（500 件）が、どれも最大の長さ（253 文字）だったときのルールの大きさ（約 126 KiB）と、自分のルールの合計の上限 `userRulesMaxBytes`（128 KiB）を足したものより大きくしてあります。

どちらも、ツールが設定を読むときに確かめます。こうしておけば、ツールが予算内と判断したリストは、アプリが許可サイトと自分のルールを上限まで足しても予算を超えません。

## sources.yml

YAML のうち、次の形だけを使います（ツールが自前で読みます）。

```yaml
sources:
  - name: EasyList
    url: https://easylist.to/easylist/easylist.txt
    license: CC-BY-SA-3.0
    attribution: The EasyList authors (https://easylist.to/)
    category: basic
    enabled: true
```

- 値は 1 行の文字列、または `true` / `false`。文字列は `"…"` で囲んでもよい。
- `url` か `path`（リポジトリの中のファイル）のどちらか 1 つが必要。
- `#` から行末まではコメント（行の先頭か、空白の直後の `#` だけ）。

### 節を除く（`exclude_sections`・`keep_lines_containing`）

EasyList の仲間のリストは、元のファイルごとに `! *** easylist:easyprivacy/easyprivacy_general.txt ***` のような見出しの行で区切られています。リストの一部の節だけを除くときは、次の 2 つを書きます（どちらも書かなくてよい）。

```yaml
  - name: EasyPrivacy
    url: https://easylist.to/easylist/easyprivacy.txt
    license: CC-BY-SA-3.0
    attribution: The EasyList authors (https://easylist.to/)
    category: privacy
    enabled: true
    exclude_sections: "! *** easylist:easyprivacy/easyprivacy_specific_cname_"
    keep_lines_containing: .jp
```

| キー | 意味 |
|---|---|
| `exclude_sections` | 除く節の見出しの行の始まり。`! *** ` で始めます（`!` で始まるので `"…"` で囲む）。節は、見出しの行（`! *** ` で始まる行）から、次の見出しの行の前までです。この文字列で始まる見出しの節を、すべて除きます。1 つの項目に 1 つだけ書けます |
| `keep_lines_containing` | 除く節の中でも、この文字列を含むルールの行は残します（大文字と小文字は区別する）。`exclude_sections` と一緒に書きます |

- 先頭の `[Adblock …]` の行を取り除いたあとに、節を除きます。除く節の中のコメントと空行は残しません。
- 当たる節が 1 つもなければ、ツールは失敗します（上流が節の名前を変えると、除くつもりの行が全部入ってしまうため。対応は docs/runbook.md）。
- 除いた節の見出し・除いたルールの行の数・残した行の数を、`report.json` の各ソースの `excludedSections`・`excludedRuleLines`・`keptRuleLines` に記録し、`summary.md` の「ソース」にも出します。
