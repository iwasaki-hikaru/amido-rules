# ライセンスの判断材料

ルールのライセンスと、使えるリスト・使えないリストについて、調べてわかった事実をまとめています。**決めるのは運営者です。** この文書は法的な助言ではありません。判断に迷うものは、専門家に確認してください。

- 調べた日：2026-09-28。ライセンスのページ、README、GitHub の API のメタデータ、変換器のソースを読みました。EasyList 以外のリストの本体は取得していません。
  - 2026-10-01：annoyance に入れた Fanboy の 2 つのリストの先頭の行と、EasyList のライセンスのページを確かめました（[2.](#2-easylist) の「Fanboy's Social Blocking List・Fanboy's Notifications List」）。
  - 2026-10-02：privacy に入れた EasyPrivacy の先頭の行と、EasyList のライセンスのページを確かめました（[2.](#2-easylist) の「EasyPrivacy」）。
- 確かさの印：
  - ［確認済］：一次資料（ライセンスのページ、規約、リポジトリの LICENSE など）を読んで確かめた
  - ［二次情報］：FilterLists.com の記録、検索結果の要約、README の要約など、一次資料を直接は確かめていない
  - ［未確認］：読めなかった・確かめられなかった
- 採用する前には、リストの先頭の `! License:` などの行と、リポジトリの LICENSE を、その時点のもので確かめ直してください。rulestool は、上流のリストの先頭のライセンス・ホームページ・版の行を `report.json`（各ソースの `headerLines`）に記録しています。

---

## 1. 今の状態

| 対象 | ライセンス | 表記の場所 | 状態 |
|---|---|---|---|
| 配信する変換後のリスト（`/v1/lists/*.json`、GitHub Release の一式） | CC BY-SA 3.0 | `LICENSE-rules`、`NOTICE`、`site/licenses.html`、Release の説明と添付 | **2026-10-04 に 3.0 のままと決定**（運営者が作業者の案を採用。[3.](#3-cc-by-sa-30-と-40)） |
| 自作ルール（`custom/*.txt`） | CC BY-SA 3.0 | 各ファイルの先頭、`LICENSE-rules` | 同上 |
| アプリに同梱するリスト | 配信するものと同じ | アプリのライセンスの画面（ios の `App/Settings/SettingsView.swift` の `LicensesView`。EasyList・Fanboy・EasyPrivacy の節がある） | 実装済み（annoyance と privacy は同梱せず、配信元から取得） |
| ツールのコード（`Sources/`・`Tests/`・`scripts/`・`tools/`・`.github/`、`Package.swift`、`wrangler.jsonc`・`config/`・`deploy/`） | MIT | `LICENSE`、`NOTICE`、README、`site/licenses.html` | 2026-10-05 に決定（[9.](#9-ツールのライセンス)） |
| サイトのページ（`site/`）・文書（`docs/`） | 権利は運営者（ライセンスを与えない） | `site/licenses.html`、`NOTICE` | 2026-10-05 に決定（[9.](#9-ツールのライセンス)） |
| 変換器（SafariConverterLib） | GPLv3 | `site/licenses.html`、`NOTICE` | CI で実行するだけで、配布しない（[5.](#5-変換器safariconverterlib)） |

使っている上流のリストは、次の 4 つです（`sources.yml`）。

| リスト | カテゴリ | 配るときのライセンス | 説明 |
|---|---|---|---|
| EasyList | basic（無料） | CC BY-SA 3.0 | [2.](#2-easylist) |
| Fanboy's Social Blocking List | annoyance（プレミアム） | CC BY-SA 3.0 | 2026-10-01 に採用。[2.](#2-easylist) の「Fanboy's Social Blocking List・Fanboy's Notifications List」 |
| Fanboy's Notifications List | annoyance（プレミアム） | CC BY-SA 3.0 | 同上 |
| EasyPrivacy | privacy（プレミアム） | CC BY-SA 3.0 | 2026-10-02 に採用。CNAME の節は、`.jp` を含む行を除いて外している。[2.](#2-easylist) の「EasyPrivacy」 |

---

## 2. EasyList

［確認済］ https://easylist.to/pages/licence.html

- EasyList のリポジトリは、次の 2 つのデュアルライセンスです。どちらか一方を選んで、変更して使えます。
  - GNU General Public License 第 3 版、またはそれ以降（利用者が選べる）
  - Creative Commons Attribution-ShareAlike 3.0 Unported、またはそれ以降（利用者が選べる）
- 表示する著作者の名前：「The EasyList authors (https://easylist.to/)」
- 非営利に限る条件はありません。
- 外部に置かれたファイルや、参照している別の購読リストは、条件が違うことがあり、それぞれの権利者の許可が要ります。
- EasyList のファイルの先頭には `! Licence: https://easylist.to/pages/licence.html` の行があります（取得したファイルで確認）。
- ダウンロードの URL：https://easylist.to/easylist/easylist.txt （`sources.yml` で使っているもの）

このリポジトリでは、CC BY-SA の道を選んでいます（3.0。2026-10-04 に決定）。

### Fanboy's Social Blocking List・Fanboy's Notifications List（annoyance）

2026-10-01 に、annoyance（プレミアム）の中身として採用しました（運営者の決定）。

- 配布物：
  - https://secure.fanboy.co.nz/fanboy-social.txt
  - https://secure.fanboy.co.nz/fanboy-notifications.txt
- ライセンスの表示が 2 つあります。
  - 配布物の 8 行目は `! License: http://creativecommons.org/licenses/by/3.0/` です（CC BY 3.0）。［確認済：2026-10-01］
  - easylist.to がリンクしている同じ Social（https://easylist.to/easylist/fanboy-social.txt ）は、先頭が EasyList のライセンス（`! Licence: https://easylist.to/pages/licence.html`）です。GNU GPL 第 3 版以降と CC BY-SA 3.0 以降のデュアルライセンスです。［確認済：2026-10-01］
  - 2 つのリストの元のファイルは、EasyList のリポジトリ（github.com/easylist/easylist の `fanboy-addon/`）にあります。［確認済：2026-10-01］
- 扱い：どちらの読み方でも条件を満たすように、次のようにします。
  - 変換したものは、annoyance として CC BY-SA 3.0 で配る。
  - 著作者は「The EasyList authors (https://easylist.to/)」と表示する。
  - 「CC BY 3.0」とだけ書かない（`LICENSE-rules`・`NOTICE`・`site/licenses.html` では、2 つの表示を両方書いている）。
  - CC BY 3.0 の作品を変えたもの（翻案）を CC BY-SA で配ってよいことは、Creative Commons の FAQ の「Adapter's license chart」（BY の行・BY-SA の列）で確かめた。［確認済：2026-10-01］ https://creativecommons.org/faq/
- 推薦の禁止：CC BY 3.0 §4(b) は、作者がこちらを支持・推薦していると示すことを禁じています。そのため、名前を出す場所には「このアプリ（と配信サイト）は、Fanboy や EasyList の作者とは関係がありません」を添えます（`NOTICE`・`site/licenses.html`・`site/support.html`・アプリの `LicensesView`）。`LICENSE-rules`・`README.md`・publish.yml の Release の説明では「このリポジトリと配信サイトは」と書いています。
- 除いたルール：同意のダイアログ・ログイン・有料記事の案内・コメント欄・アフィリエイトの表示を隠すルールのうち、2026-10-01 に見つけた 7 つを、`custom/annoyance.txt` の例外（`#@#`）で除いています（7 行。それぞれに根拠と理由の行がある）。年齢確認を隠すルールは 0 件でした。
  - annoyance のカテゴリは、Fanboy の 2 つと `custom/annoyance.txt` を 1 つにつないで 1 回で変換するので（`Sources/RulesKit/BuildPipeline.swift` の `convertCategories`）、例外はこのカテゴリの中で効きます。
- まだ解決していないこと：
  - App Store（FairPlay、標準の EULA）で配ることと、技術的な手段・追加の条件の禁止との関係は、EasyList と同じ論点です（[3.](#確かめていないこと)）。BY-SA で読めば、EasyList と同じ BY-SA 3.0 §4(b) がかかります。【要確認】（専門家に確認）
  - Fanboy の日本のサイト向けのルール（`.jp`）の出どころ（[6.](#6-使わないと決めたもの使えないもの) の Yuki's uBlock Japanese filters との関係）は［未確認］です。basic の EasyList にも同じ懸念があります。

### EasyPrivacy（privacy）

2026-10-02 に、privacy（プレミアムのトラッキング防止）の中身として採用しました（運営者の決定）。

- 配布物：https://easylist.to/easylist/easyprivacy.txt
- ライセンス：EasyList のリポジトリのデュアルライセンス（GNU GPL 第 3 版以降と CC BY-SA 3.0 以降）に入ります。
  - 配布物の先頭に `! Licence: https://easylist.to/pages/licence.html` の行があります。［確認済：2026-10-01T17:42Z と 18:11Z に取得したもの。Version 202610011728 と 202610011802］
  - ライセンスのページ（https://easylist.to/pages/licence.html ）は、外部に置かれたファイルなどは別の条件のことがある、とする説明の中で、EasyList と EasyPrivacy をその対象から除いています（"other than EasyList, EasyPrivacy"）。［確認済：2026-10-01］
- 扱い：
  - 変換したものは、privacy として CC BY-SA 3.0 で配る（EasyList・annoyance と同じ）。
  - 著作者は「The EasyList authors (https://easylist.to/)」と表示する。
  - 名前を出す場所には、作者とは関係がないことを添える（`NOTICE`・`site/licenses.html`・`site/support.html`・アプリの `LicensesView`）。
- 除いた部分：CNAME の節（見出しが `! *** easylist:easyprivacy/easyprivacy_specific_cname_` で始まる 20 の節。特定のサイトのサブドメインを 1 件ずつ並べたもので、ルールの行の約 6 割）を除いています。ただし、日本のサイトの計測を逃さないように、その節の中でも `.jp` を含む行は残しています（`sources.yml` の `exclude_sections` と `keep_lines_containing`）。件数を抑えるためです（全部入れると、変換後に約 5.6 万件）。除いたことは、`NOTICE`・`LICENSE-rules`・`site/licenses.html`・Release の説明に書いています。
- 先頭の行は `[Adblock Plus 1.1]` です（EasyList は 2.0）。rulestool は `[Adblock …]` の行をすべて取り除きます。

---

## 3. CC BY-SA 3.0 と 4.0

### 3.0 で使うときの義務

［確認済］ https://creativecommons.org/licenses/by-sa/3.0/legalcode

| 条項 | 内容 | このリポジトリでの対応 |
|---|---|---|
| 3 | 営利目的の利用も許される | ― |
| 4(a) | 配るすべての複製に、ライセンスの本文か URI を付ける。受け取った人の権利を狭める条件を足したり、技術的な手段で制限したりしない | `LICENSE-rules`・`NOTICE`・`site/licenses.html` に URI を書いている。Release には `NOTICE` と `LICENSE-rules` を添付し、説明にも URI を書く |
| 4(b) | 翻案（Adaptation）は、BY-SA 3.0、同じ要素を持つ後の版、または互換の CC ライセンスで配る。ライセンスの URI を付け、受け取った人の権利を狭める条件を足したり、技術的な手段で制限したりしない | 変換後のリストを CC BY-SA 3.0 で配っている |
| 4(c) | 著作者名、題名、URI を表示し、翻案では元の作品をどう使ったか（例：「EasyList を変換したもの」）を示す | `NOTICE`・`site/licenses.html` に、著作者・元の URL・変換と除外と組み合わせの説明を書いている。`LICENSE-rules` と Release の説明にも、元のリスト（EasyList と Fanboy の 2 つと EasyPrivacy）と著作者を書いている |

- 変換後の JSON は、EasyList（basic）と、Fanboy's Social Blocking List・Fanboy's Notifications List（annoyance）と、EasyPrivacy（privacy）の翻案（Adaptation）にあたります。
- 3.0 について、Creative Commons は「BY-SA 3.0 と互換と指定された CC 以外のライセンスはない」としています。［確認済］ https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/

### 確かめていないこと

- **アプリに同梱するリストと「技術的な手段」**：アプリに同梱するリストは、App Store の配布の仕組みを通ります。同じリストを、このリポジトリと配信サイトで制限なく配っていることが、この条項との関係でどう評価されるかは、確かめていません。［未確認］【要確認】
  - 2026-09-29 に調べたこと（法的な助言ではない）：
    - 変換したリストは「翻案（Adaptation）」なので、当たるのは 3.0 の §4(b)（4(a) ではない）。4.0 では §3(b)(3)（https://creativecommons.org/licenses/by-sa/3.0/legalcode 、https://creativecommons.org/licenses/by-sa/4.0/legalcode.en ）
    - App Store の FairPlay は実行ファイルを暗号化するもの（Apple「Reducing your app's size」、OWASP MASTG）。JSON などのリソースも暗号化されるかは、Apple が公開しておらず未確認
    - Creative Commons の FAQ は、DRM を使う場所に置くには、ライセンサーの明示の許可が必要としている。CC の wiki（2013 年、アーカイブ）は、App Store の仕組みが「アプリの中の内容に対する技術的な手段に当たりうる」としている。DRM なしの版を並べて配る（並行配布）ことは、3.0・4.0 のどちらでも許可の仕組みとしては採られなかった（https://wiki.creativecommons.org/wiki/4.0/Technical_protection_measures ）
    - Apple の標準の使用許諾契約（EULA）は、アプリの再配布を禁じ、アプリから使える内容にも及ぶ書き方で、CC BY-SA の「追加の条件を課さない」とぶつかる可能性がある。このサイトの利用規約 第 5 条は「ルールはそれぞれのライセンスに従って利用できる」としている
    - 取れる手：4.0 にする（違反を 30 日以内に直せば権利が戻る。§6(b)）、独自の EULA でルールに CC BY-SA が適用されると明記する、EasyList の作者に明示の許可をもらう、EasyList 由来のリストを同梱しない、など。公開の前に専門家の意見を聞くことをおすすめする
- **配信する JSON そのものへの表記**：JSON の配列にはコメントを書けないので、リストのファイル自体にはライセンスの表記がありません。同じサイトの `/licenses` と、公開リポジトリの `LICENSE-rules`・`NOTICE` で表記しています。これで足りるかは確かめていません。【要確認】
  - 案：manifest にライセンスの URI と著作者の表記を足す（形式の変更になるので、足すなら `docs/format.md` とアプリを同時に直す。アプリが知らないキーを無視するかどうかも確かめる）。

### 4.0 にする案（2026-10-04 に、今は採らないと決めた）

- 決めたこと：3.0 のまま。4.0 にしても、技術的保護手段（App Store）と EULA の論点は残るため。「以降」の許可があるので、あとから 4.0 にできる。App Store では Apple の標準の EULA のまま使い、DRM なしの同じリストを配信サイトと GitHub Release で公開し続ける

- EasyList は「3.0 またはそれ以降」を許しているので、変換後のリストを CC BY-SA 4.0 で配ることもできます。
- CC BY-SA 4.0 は、GPLv3 と一方向の互換があります（BY-SA 4.0 の作品を GPLv3 の作品に組み込める）。［確認済］ https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/
  - 将来、GPLv3 のリスト（AdGuard など）と組み合わせる可能性があるなら、4.0 のほうが選択肢が広がります。
- 4.0 にするなら、次を同時に直します：`LICENSE-rules`、`NOTICE`、`site/licenses.html`、`sources.yml` の自作ルールの `license`、`custom/*.txt` の先頭、publish.yml の Release の説明、アプリのライセンスの画面、README。
- 自作ルールは運営者の著作物なので、どのライセンスにするかは自由に決められます（EasyList と同じ JSON に入れるので、合わせておくのが簡単です）。

---

## 4. 配る場所ごとの義務のまとめ

| 配る場所 | 配るもの | 必要なこと（CC BY-SA の場合） | 状態 |
|---|---|---|---|
| 公開リポジトリ（rules） | 自作ルール、ツール、（変換後の JSON は置かない） | ライセンスの URI、著作者、変更の説明 | `LICENSE-rules`・`NOTICE` あり（どちらも EasyList と Fanboy の 2 つと EasyPrivacy を挙げている） |
| 配信サイト（`/v1/lists/*.json`） | 変換後のリスト | 同上 | `/licenses` に表記。JSON 自体には書けない（[3.](#確かめていないこと)） |
| GitHub Release | 公開した一式（`dist/` の tar.gz） | 同上 | 説明に URI と著作者（EasyList と Fanboy の 2 つと EasyPrivacy。作者とは関係がないことも書く。publish.yml の「GitHub Release に保管する」）、`NOTICE`・`LICENSE-rules` を添付 |
| アプリ | 同梱のリスト、ダウンロードしたリスト | 同上。アプリのライセンスの画面に同じ表記を出す | `LicensesView` に表記あり（EasyList・Fanboy・EasyPrivacy・自作のルール） |

---

## 5. 変換器（SafariConverterLib）

- ライセンス：GPLv3。［確認済］ https://github.com/AdguardTeam/SafariConverterLib （リポジトリの LICENSE）
- 使い方：CI の中で、別のプログラムとして実行するだけです。rulestool にもアプリにもリンクせず、配布もしません。ソースからビルドするときに取得する依存 3 つ（PunycodeSwift・swift-argument-parser・swift-psl）も同じです。
- 変換の出力（JSON）に、変換器の GPL の義務がかかるかどうかは、FSF の GPL の FAQ（「GPLOutput」の項）で扱われていますが、調べたときに読めませんでした（HTTP 429）。［未確認］【要確認】 https://www.gnu.org/licenses/gpl-faq.html#GPLOutput
  - 出力のライセンスは、入力のリスト（EasyList なら CC BY-SA または GPLv3）で決まる、という前提で今は扱っています。

---

## 6. 使わないと決めたもの・使えないもの

### AdGuard Japanese filter（今は無効）

`sources.yml` に `enabled: false` で入れてあります。**使わない**（2026-10-04 に運営者が作業者の案を採用。GPLv3 のリストを混ぜると、配るリストのライセンスが複雑になるため）。

- AdGuard の資料では、ID 7、日本語向けの推奨リスト、「Fanboy's Japanese filter を元にした」とされています。［確認済］ https://adguard.com/kb/general/ad-filtering/adguard-filters/
- ソースは AdguardTeam/AdguardFilters リポジトリにあり、その LICENSE は GPLv3 です。［確認済］ https://github.com/AdguardTeam/AdguardFilters
  - 配布用の FiltersRegistry リポジトリは LGPL-3.0 です。［確認済］ https://github.com/AdguardTeam/FiltersRegistry
  - FilterLists.com は、このリストを CC BY-SA 3.0 と記録していて、リポジトリの LICENSE と食い違っています（FilterLists の API の id 163・2207 で確認。2026-09-29）。
  - Safari 版（https://filters.adtidy.org/extension/safari/filters/7.txt ）の先頭の行 `License:` は、AdguardFilters の LICENSE（GPLv3）を指しています。［確認済：2026-09-29］
- 使う場合の影響：
  - GPLv3 のリストとして扱うと、変換後の JSON も GPLv3 で配ることになります。
  - basic に入れると、EasyList と同じ JSON になるので、1 つのライセンスにそろえる必要があります（EasyList は GPLv3 も選べるので、GPLv3 にそろえることになる）。
  - GPLv3 のデータを App Store のアプリに同梱して配ることについては、専門家の意見を聞くことをすすめます。【要確認】
- 件数：Safari 版を手元の変換器（`--safari-version 17`）で測ると、Safari のルール 6,367 件（1.18 MB）、変換できないもの 32 件でした（2026-09-29）。今の basic（58,951 件）に足すと約 65,300 件になり、上限の 65,000 件を超えます。

### 280blocker（使用禁止）

［確認済］

- ダウンロードのページのファイルの利用条件：著作権法で許される個人の利用に限る。営利目的での使用・再配布などは禁止。 https://280blocker.net/download/
- iOS アプリの利用規約（運営：トビラシステムズ株式会社）：第 7 条で、インストール以外の複製、第三者への販売・譲渡・貸与・公衆送信・利用許諾を禁止。第 14 条で、権利は同社または権利者に帰属。 https://280blocker.net/terms-ios/ 、 https://280blocker.net/terms/
- 対応：
  - `config/denylist.json` に `280blocker` を入れ、URL にこれを含むソースを rulestool が拒否します。
  - 自作ルールに、280blocker のルールを写しません。そのために、自作ルールには 1 件ごとに根拠（自分で確かめたページと日付）を書きます。
  - 「280blocker と一緒に使う」ことを前提にした有志のリスト（nanj-filter など）も、中身の出どころを確かめるまで使いません。

### 豆腐フィルタ（使用禁止）

- ライセンスのファイルはなく、README に「営利目的で使用することは禁止します」とあります。［二次情報：README の要約］ https://github.com/tofukko/filter
- `config/denylist.json` に `tofukko` を入れています。

### 「All Rights Reserved」と記録されている日本のリスト

FilterLists.com で「All Rights Reserved」と記録されているもの（作者の許可がなければ使わない）［二次情報］ https://filterlists.com/

- Japanese Site Adblock Filter（ver 1・ver 2）
- Ayucat Powerful List
- AdAway JP hosts の派生
- Warui Hosts
- Japan Hosts Ultimate

### 出どころが使用禁止のリストを含むもの・営利で使えないもの（2026-09-29 に確認）

ライセンスの表示が緩くても、作者が「280blocker や豆腐フィルタから取った・参考にした」と書いているものは使いません（中身の権利が、表示のライセンスでは与えられないため）。

| リスト | 表示されているライセンス | 使わない理由 | 出典 |
|---|---|---|---|
| もちフィルタ（mochi・ichigo など） | README と各リストの先頭に「CC0 (Public Domain)」。LICENSE のファイルはない | 公式ページに「EasyListと豆腐フィルタから必要最小限のフィルタを抜き出したもの」とある。FilterLists は All Rights Reserved と記録 | https://eeii0a5l.github.io/mochifilter_homepage/mochi.html 、 https://github.com/eEIi0A5L/adblock_filter |
| Yuki's uBlock Japanese filters | CC BY-SA 4.0（LICENSE.md） | README-JP の脚注で、280blocker のドメインリストと豆腐フィルタを参考にしたと書いている。2022-12-01 にアーカイブ | https://github.com/Yuki2718/adblock/blob/master/japanese/README-JP.md |
| k2jp ABP Japanese filters | 先頭の行に「Code license: GNU GPL v3」「Content license: CC BY-NC-SA 4.0」 | 中身が非営利の条件（NC）。2021-05 で更新が止まっている | https://github.com/k2jp/abp-japanese-filters |
| hosts-jp（tiuxo/hosts の ads） | CC BY 4.0（LICENSE） | ライセンスは使える形だが、2019-04-26 のまとめての追加（約 2,100 件）に出典の記載がなく、そのうち 58% がライセンスのない古いリスト（adawaylist-jp。FilterLists では All Rights Reserved）にも入っている。アフィリエイトの転送用のホストも入っている。まとめて取り込まず、使うなら 1 件ずつ根拠を確かめて自作ルールにする | https://github.com/tiuxo/hosts |
| nanj-filter | CC0 | 280blocker と一緒に使う前提のもの | https://github.com/nanj-adguard/nanj-filter |

---

## 7. ほかの候補（広告・不快な要素・日本向け）

Fanboy's Social Blocking List と Fanboy's Notifications List は、2026-10-01 に annoyance に採用しました（表の先頭の 2 行。[2.](#2-easylist) を参照）。EasyPrivacy は、2026-10-02 に privacy に採用しました（表の 3 行目）。ほかは、採用するかどうかは未決定です。どれも、採用する前に、ライセンスと Safari での効果（変換できる割合、件数）を確かめます。

| リスト | URL | ライセンス | 確かさ | メモ |
|---|---|---|---|---|
| **Fanboy's Social Blocking List（採用）** | https://secure.fanboy.co.nz/fanboy-social.txt | 先頭の行に CC BY 3.0。元のファイルは EasyList のリポジトリにあり、EasyList のライセンス（GPLv3 以降と CC BY-SA 3.0 以降）。CC BY-SA 3.0 で配る | ［確認済：2026-10-01］ | annoyance。SNS の共有・いいね・フォローのボタンやウィジェット。約 75% はサイトを指定しない汎用のルール。サイトを指定したルールのうち `.jp` は 1.5%（52/3,474）。記事に埋め込まれた投稿（`.twitter-tweet` など）を隠すルールは 0 件 |
| **Fanboy's Notifications List（採用）** | https://secure.fanboy.co.nz/fanboy-notifications.txt | 同上 | ［確認済：2026-10-01］ | annoyance。「通知を受け取りますか」などの案内、アプリへの誘導の表示。サイトを指定したルールのうち `.jp` は 5.6%（51/918） |
| **EasyPrivacy（採用）** | https://easylist.to/easylist/easyprivacy.txt | EasyList のリポジトリのデュアルライセンス（リポジトリ全体にかかる）。CC BY-SA 3.0 で配る | ［確認済：2026-10-01］ | privacy（トラッキング防止）。2026-10-02 に採用。CNAME の節は `.jp` を含む行を除いて外す（[2.](#2-easylist) の「EasyPrivacy」） |
| Fanboy's Annoyance List | https://secure.fanboy.co.nz/fanboy-annoyance.txt | 先頭の行に CC BY 3.0。easylist.to のライセンスのページは「EasyList・EasyPrivacy・EasyList Germany・EasyList Italy 以外は別の条件のことがある」としているので、根拠にするのは先頭の行の CC BY 3.0 | ［確認済：2026-09-29］ | 中身の 52% が Cookie の同意の表示。年齢確認の画面を隠すルール（Fanboy Agegate）が 347 件ある。日本のサイト向けは 0.7%。「不快な広告」には当たらない |
| Fanboy's Japanese | https://fanboy.co.nz/fanboy-japanese.txt | 先頭の行に CC BY 3.0 | ［確認済：2026-09-29］ | 2019-07 で更新が止まっている |
| EasyList Cookie List | https://secure.fanboy.co.nz/fanboy-cookiemonster.txt | 同上 | ［二次情報］ | Cookie の同意の表示 |
| AdGuard Cookie Notices（ID 18） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_18_Annoyances_Cookies/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Popups（ID 19） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_19_Annoyances_Popups/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Mobile App Banners（ID 20） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_20_Annoyances_MobileApp/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Other Annoyances（ID 21） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_21_Annoyances_Other/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Widgets（ID 22） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_22_Annoyances_Widgets/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Mobile Ads（ID 11） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Annoyances（ID 14） | ― | ― | ［二次情報］ | メタデータで非推奨（deprecated） |
| uBlock filters – Annoyances | https://ublockorigin.github.io/uAssets/filters/annoyances.txt | GPLv3（uAssets の LICENSE） | ［二次情報］ | URL は assets.json の要約から |
| AdGuard Japanese filter Plus | https://yuki2718.github.io/adblock2/japanese/jpf-plus.txt | GPLv3（リポジトリの LICENSE.md） | ［確認済：2026-09-29］ | Safari・iOS は正式には対象外（多くのルールが動かない、とされている） |

もちフィルタ・Yuki's uBlock Japanese filters・nanj-filter・hosts-jp は、[6.](#出どころが使用禁止のリストを含むもの営利で使えないもの2026-09-29-に確認) に移しました（使いません）。

**日本向け・不快な広告のリストについて（2026-09-29 の調べ）**：FilterLists で日本語向けとされる 52 件を一次資料で確かめましたが、営利のアプリで使えて、今も更新されている日本向けのリストは見つかりませんでした。「不快な広告」（性的な広告・過激な漫画の広告・コンプレックスをあおる広告）を対象にしたリストもありません。日本のサイト向けのルールは、根拠を 1 件ずつ付けて自作します。

出典：https://adguard.com/kb/general/ad-filtering/adguard-filters/ 、 https://easylist.to/ 、 https://easylist.to/pages/licence.html 、 https://github.com/uBlockOrigin/uAssets 、 https://github.com/Yuki2718/adblock2 、 https://api.filterlists.com/lists

- GPLv3 のリストを使うと、そのカテゴリの JSON は GPLv3 で配ることになります（[AdGuard Japanese filter](#adguard-japanese-filter今は無効) と同じ注意）。
- annoyance（プレミアム）のカテゴリに入れるなら、今の annoyance には Fanboy の 2 つのリスト（CC BY-SA 3.0 で配っている）と自作ルールが入っているので、それらとライセンスをそろえられるかを先に確かめます。GPLv3 のリストを足す場合、Fanboy の部分を GPLv3 で配れるかは、配布物の先頭の CC BY 3.0 で読むと［未確認］です。

---

## 8. 詐欺サイトのデータの候補（scam、第 2 段階）

「詐欺サイトのブロック」に使えるデータを調べた結果です。**全体として、営利のアプリで再配布できると明確に言える大きなデータは見つかっていません。** 集めたリスト自体のライセンスが緩くても、その元のデータの権利までは与えられていないことがあるので、元のデータまでさかのぼって確かめる必要があります。

| データ | ライセンス・条件 | 営利のアプリでの利用 | 確かさ | 出典 |
|---|---|---|---|---|
| OpenPhish | 学術・個人の研究だけ。製品の開発・利用者の保護への利用を含め、営利の利用を禁止。書面の同意なしに第三者へ配ったり、派生物を作ったりすることも禁止 | 使えない | ［確認済］ | https://openphish.com/terms.html |
| URLhaus（abuse.ch） | API は公正な利用の範囲で無料。営利の用途は有料の契約（Spamhaus 経由）が必要な場合がある。一括のダウンロードには認証キーが必要。規約で、許可なしの営利の利用、テキスト・データマイニング、スクレイピングを禁止 | 有料の契約がなければ使えない（それを元にしたリストも同じ） | ［確認済］ | https://urlhaus.abuse.ch/api/ 、 https://abuse.ch/terms-and-conditions/ |
| urlhaus-filter（malware-filter） | README は「URLhaus: CC0」としているが、今の abuse.ch の規約と食い違う | 上に同じ | ［確認済］ | https://gitlab.com/malware-filter/urlhaus-filter |
| PhishTank | FAQ で「営利・非営利の両方の利用に API を使ってよい」。キーがないと 1 日数回しか取得できず、新規の登録は止まっている。運営は Cisco Talos。Cisco の利用規約は読んでいない | FAQ 上は可。キーが取れない。規約の確認が必要 | ［確認済］（規約は［未確認］） | https://phishtank.org/faq.php 、 https://phishtank.org/developer_info.php 、 https://phishtank.org/register.php |
| phishing-filter（malware-filter） | リストは CC BY-SA 4.0。ただし元のデータに OpenPhish（営利の利用を禁止）が入っている | 元のデータの点で使えない | ［二次情報］ | https://gitlab.com/malware-filter/phishing-filter |
| Phishing.Database | MIT。誤検知の手続きが PhishTank・OpenPhish の掲載を参照していて、それらを取り込んでいる可能性がある | 元のデータを確かめるまで不明 | ［二次情報］ | https://github.com/mitchellkrogza/Phishing.Database |
| HaGeZi（dns-blocklists） | GPLv3。ただし「GPL-3.0 は公開しているリストにかかるもので、元のデータの権利は与えない」と明記。Fake は約 17,383 件、TIF は約 235 万件（mini は約 20 万件） | 元のデータの権利が不明。TIF は件数の点でも入らない | ［二次情報］ | https://github.com/hagezi/dns-blocklists |
| uB-filter（Kdroidwin） | GPLv3。日本の利用者向けに、詐欺・偽サイトを対象にしている。Dandelion Sprout の内容（Dandelicence、営利の利用を許す）を含む | GPLv3 として扱う必要がある。元のデータの確認が必要 | ［二次情報］ | https://github.com/Kdroidwin/uB-filter-by-kdroidwin |
| JPCERT/CC phishurl-list | JPCERT/CC が確認したフィッシングの URL（CSV）。ライセンスの記載がない（GitHub の API でも license は null） | 許可を得なければ使えない（既定の著作権） | ［確認済］ | https://github.com/JPCERTCC/phishurl-list 、 https://blogs.jpcert.or.jp/ja/2022/08/phishurl-list.html |
| フィッシング対策協議会の URL の提供 | 機械で読める一般向けのリストはない。URL の提供（OpenTAXII/STIX）は、ブラウザやウイルス対策でブロックを提供する法人の正会員だけ（個人は対象外）。表・グラフ・数値は、出典を示せば転載できる | 法人の正会員にならなければ使えない | ［確認済］ | https://www.antiphishing.jp/enterprise/url.html 、 https://www.antiphishing.jp/contact_faq.html |
| JC3（日本サイバー犯罪対策センター） | 偽ショップの URL は公開していない。フィルタリング事業者・セキュリティ事業者などに提供 | 使えない | ［確認済］ | https://www.jc3.or.jp/threats/topics/article-608.html |

### 現実的な始め方（案）

- 公的な注意喚起（フィッシング対策協議会の緊急情報など）を根拠にして、`custom/scam.txt` に手で書く。1 件ごとに `! 根拠: <注意喚起の URL> (<日付>)` を書く。
- 共有のホスティングや無料のサブドメインの上にある詐欺サイトも多いので、登録ドメイン全体ではなく、ホスト名で狭くブロックする。
- scam のカテゴリには例外ルール（`@@…`）を書けません（README の「例外ルールが効く範囲」）。誤ブロックは、ルールを消すか狭くして直します。
- JPCERT/CC の phishurl-list を使いたい場合は、営利のアプリで再配布してよいかを、JPCERT/CC に問い合わせる。

### 決めること

- アプリは有料（営利）なので、上の表の「営利」の条件がそのまま当てはまる前提で考える。
- どのデータを使うか。使うなら、元のデータまでさかのぼって、営利の再配布ができることを確かめる（または書面の許可・有料の契約を得る）。

---

## 9. ツールのライセンス

- **2026-10-05 に決定（運営者が作業者の案を採用）**：ツールのコード（`Sources/`・`Tests/`・`scripts/`・`tools/`・`.github/`、`Package.swift`、`wrangler.jsonc`・`config/`・`deploy/` の設定ファイル）は MIT License。`LICENSE` に全文を置いた（Copyright (c) 2026 Hikaru Iwasaki）
- サイトのページ（文章・スタイル・スクリプト・アイコンの画像）と `docs/` の文書には、ライセンスを与えない（権利は運営者。特定商取引法の表記や規約の文章、アプリのアイコンを含むため）
- ツールは変換器（GPLv3）にリンクしていないので、変換器のライセンスはツールのライセンスの選び方を縛りません。

---

## 決めることの一覧

| 決めること | 選択肢 | 関係するところ |
|---|---|---|
| 変換後のリストのライセンス | CC BY-SA 3.0（今）／ CC BY-SA 4.0 ／ GPLv3 | [3.](#3-cc-by-sa-30-と-40)、[4.](#4-配る場所ごとの義務のまとめ) |
| アプリに同梱するリストの扱い | 3.0 の §4(b)（4.0 は §3(b)(3)）の、技術的な手段・追加の条件の禁止との関係を確かめる | [3.](#確かめていないこと) |
| manifest にライセンスの表記を足すか | 足す（形式の変更）／ 足さない | [3.](#確かめていないこと) |
| AdGuard Japanese filter を使うか | 使わない（今）／ GPLv3 で使う | [6.](#adguard-japanese-filter今は無効) |
| annoyance に上流のリストを使うか | Fanboy's Social Blocking List と Fanboy's Notifications List を使う（2026-10-01 に決定）。ほかの候補を足すかは未決定 | [2.](#2-easylist)、[7.](#7-ほかの候補広告不快な要素日本向け) |
| privacy に上流のリストを使うか | EasyPrivacy を使う（2026-10-02 に決定）。CNAME の節は `.jp` を含む行を除いて外す | [2.](#2-easylist) の「EasyPrivacy」 |
| Fanboy のリストの 2 つのライセンス表示の扱い | CC BY-SA 3.0 で配り、著作者は「The EasyList authors」と表示する（今）。両方の条件を満たすと言えるかは専門家に確認 | [2.](#2-easylist) |
| 詐欺サイトのデータ | 手で書く（案）／ 許可や契約を得て使う | [8.](#8-詐欺サイトのデータの候補scam第-2-段階) |
| ツールのライセンス | MIT（2026-10-05 に決定） | [9.](#9-ツールのライセンス) |
