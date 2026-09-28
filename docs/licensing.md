# ライセンスの判断材料

ルールのライセンスと、使えるリスト・使えないリストについて、調べてわかった事実をまとめています。**決めるのは運営者です。** この文書は法的な助言ではありません。判断に迷うものは、専門家に確認してください。

- 調べた日：2026-09-28。ライセンスのページ、README、GitHub の API のメタデータ、変換器のソースを読みました。EasyList 以外のリストの本体は取得していません。
- 確かさの印：
  - ［確認済］：一次資料（ライセンスのページ、規約、リポジトリの LICENSE など）を読んで確かめた
  - ［二次情報］：FilterLists.com の記録、検索結果の要約、README の要約など、一次資料を直接は確かめていない
  - ［未確認］：読めなかった・確かめられなかった
- 採用する前には、リストの先頭の `! License:` などの行と、リポジトリの LICENSE を、その時点のもので確かめ直してください。rulestool は、上流のリストの先頭のライセンス・ホームページ・版の行を `report.json`（各ソースの `headerLines`）に記録しています。

---

## 1. 今の状態

| 対象 | ライセンス | 表記の場所 | 状態 |
|---|---|---|---|
| 配信する変換後のリスト（`/v1/lists/*.json`、GitHub Release の一式） | CC BY-SA 3.0 | `LICENSE-rules`、`NOTICE`、`site/licenses.html`、Release の説明と添付 | 仮に決めたもの。3.0 か 4.0 かは未決定（[3.](#3-cc-by-sa-30-と-40)） |
| 自作ルール（`custom/*.txt`） | CC BY-SA 3.0 | 各ファイルの先頭、`LICENSE-rules` | 同上 |
| アプリに同梱するリスト | 配信するものと同じ | アプリのライセンスの画面（フェーズ 3） | 未実装 |
| ツール（`Sources/`・`Tests/`・`scripts/`・`.github/` など） | 未定 | なし | 決まるまで LICENSE を置かない（[9.](#9-ツールのライセンス)） |
| サイトのページ（`site/`） | 未定（権利は運営者） | `site/licenses.html` | 【要記入】 |
| 変換器（SafariConverterLib） | GPLv3 | `site/licenses.html`、`NOTICE` | CI で実行するだけで、配布しない（[5.](#5-変換器safariconverterlib)） |

使っている上流のリストは、EasyList だけです（`sources.yml`）。

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

このリポジトリでは、CC BY-SA の道を選んでいます（3.0 か 4.0 かは未決定）。

---

## 3. CC BY-SA 3.0 と 4.0

### 3.0 で使うときの義務

［確認済］ https://creativecommons.org/licenses/by-sa/3.0/legalcode

| 条項 | 内容 | このリポジトリでの対応 |
|---|---|---|
| 3 | 営利目的の利用も許される | ― |
| 4(a) | 配るすべての複製に、ライセンスの本文か URI を付ける。受け取った人の権利を狭める条件を足したり、技術的な手段で制限したりしない | `LICENSE-rules`・`NOTICE`・`site/licenses.html` に URI を書いている。Release には `NOTICE` と `LICENSE-rules` を添付し、説明にも URI を書く |
| 4(b) | 翻案（Adaptation）は、BY-SA 3.0、同じ要素を持つ後の版、または互換の CC ライセンスで配る | 変換後のリストを CC BY-SA 3.0 で配っている |
| 4(c) | 著作者名、題名、URI を表示し、翻案では元の作品をどう使ったか（例：「EasyList を変換したもの」）を示す | `NOTICE`・`site/licenses.html` に、著作者・元の URL・変換と除外と組み合わせの説明を書いている |

- 変換後の JSON は、EasyList の翻案（Adaptation）にあたります。
- 3.0 について、Creative Commons は「BY-SA 3.0 と互換と指定された CC 以外のライセンスはない」としています。［確認済］ https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/

### 確かめていないこと

- **アプリに同梱するリストと 4(a) の「技術的な手段」**：アプリに同梱するリストは、App Store の配布の仕組みを通ります。同じリストを、このリポジトリと配信サイトで制限なく配っていることが、この条項との関係でどう評価されるかは、確かめていません。［未確認］【要確認】
- **配信する JSON そのものへの表記**：JSON の配列にはコメントを書けないので、リストのファイル自体にはライセンスの表記がありません。同じサイトの `/licenses` と、公開リポジトリの `LICENSE-rules`・`NOTICE` で表記しています。これで足りるかは確かめていません。【要確認】
  - 案：manifest にライセンスの URI と著作者の表記を足す（形式の変更になるので、足すなら `docs/format.md` とアプリを同時に直す。アプリが知らないキーを無視するかどうかも確かめる）。

### 4.0 にする案（提案。既定では採用していない）

- EasyList は「3.0 またはそれ以降」を許しているので、変換後のリストを CC BY-SA 4.0 で配ることもできます。
- CC BY-SA 4.0 は、GPLv3 と一方向の互換があります（BY-SA 4.0 の作品を GPLv3 の作品に組み込める）。［確認済］ https://creativecommons.org/share-your-work/licensing-considerations/compatible-licenses/
  - 将来、GPLv3 のリスト（AdGuard など）と組み合わせる可能性があるなら、4.0 のほうが選択肢が広がります。
- 4.0 にするなら、次を同時に直します：`LICENSE-rules`、`NOTICE`、`site/licenses.html`、`sources.yml` の自作ルールの `license`、`custom/*.txt` の先頭、publish.yml の Release の説明、アプリのライセンスの画面、README。
- 自作ルールは運営者の著作物なので、どのライセンスにするかは自由に決められます（EasyList と同じ JSON に入れるので、合わせておくのが簡単です）。

---

## 4. 配る場所ごとの義務のまとめ

| 配る場所 | 配るもの | 必要なこと（CC BY-SA の場合） | 状態 |
|---|---|---|---|
| 公開リポジトリ（rules） | 自作ルール、ツール、（変換後の JSON は置かない） | ライセンスの URI、著作者、変更の説明 | `LICENSE-rules`・`NOTICE` あり |
| 配信サイト（`/v1/lists/*.json`） | 変換後のリスト | 同上 | `/licenses` に表記。JSON 自体には書けない（[3.](#確かめていないこと)） |
| GitHub Release | 公開した一式（`dist/` の tar.gz） | 同上 | 説明に URI と著作者、`NOTICE`・`LICENSE-rules` を添付 |
| アプリ | 同梱のリスト、ダウンロードしたリスト | 同上。アプリのライセンスの画面に同じ表記を出す | フェーズ 3 で実装する |

---

## 5. 変換器（SafariConverterLib）

- ライセンス：GPLv3。［確認済］ https://github.com/AdguardTeam/SafariConverterLib （リポジトリの LICENSE）
- 使い方：CI の中で、別のプログラムとして実行するだけです。rulestool にもアプリにもリンクせず、配布もしません。ソースからビルドするときに取得する依存 3 つ（PunycodeSwift・swift-argument-parser・swift-psl）も同じです。
- 変換の出力（JSON）に、変換器の GPL の義務がかかるかどうかは、FSF の GPL の FAQ（「GPLOutput」の項）で扱われていますが、調べたときに読めませんでした（HTTP 429）。［未確認］【要確認】 https://www.gnu.org/licenses/gpl-faq.html#GPLOutput
  - 出力のライセンスは、入力のリスト（EasyList なら CC BY-SA または GPLv3）で決まる、という前提で今は扱っています。

---

## 6. 使わないと決めたもの・使えないもの

### AdGuard Japanese filter（今は無効）

`sources.yml` に `enabled: false` で入れてあります。使うかどうかは未決定です。

- AdGuard の資料では、ID 7、日本語向けの推奨リスト、「Fanboy's Japanese filter を元にした」とされています。［確認済］ https://adguard.com/kb/general/ad-filtering/adguard-filters/
- ソースは AdguardTeam/AdguardFilters リポジトリにあり、その LICENSE は GPLv3 です。［確認済］ https://github.com/AdguardTeam/AdguardFilters
  - 配布用の FiltersRegistry リポジトリは LGPL-3.0 です。［確認済］ https://github.com/AdguardTeam/FiltersRegistry
  - FilterLists.com は、このリストを CC BY-SA 3.0 と記録していて、リポジトリの LICENSE と食い違っています。［二次情報］ https://filterlists.com/
  - リストの先頭の行は AdguardFilters の LICENSE を指している、という検索結果の要約がありますが、直接は読んでいません。［二次情報］
- 使う場合の影響：
  - GPLv3 のリストとして扱うと、変換後の JSON も GPLv3 で配ることになります。
  - basic に入れると、EasyList と同じ JSON になるので、1 つのライセンスにそろえる必要があります（EasyList は GPLv3 も選べるので、GPLv3 にそろえることになる）。
  - GPLv3 のデータを App Store のアプリに同梱して配ることについては、専門家の意見を聞くことをすすめます。【要確認】
- 件数：公開されている件数は見つかりませんでした。使うなら CI で測ります（予算に収まるかも確かめる）。

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

---

## 7. ほかの候補（広告・不快な要素・日本向け）

採用するかどうかは未決定です。どれも、採用する前に、ライセンスと Safari での効果（変換できる割合、件数）を確かめます。

| リスト | URL | ライセンス | 確かさ | メモ |
|---|---|---|---|---|
| EasyPrivacy | https://easylist.to/easylist/easyprivacy.txt | EasyList のリポジトリのデュアルライセンス（リポジトリ全体にかかる） | ［二次情報］ | 追跡の防止。広告のリストとは別 |
| Fanboy's Annoyance List | https://secure.fanboy.co.nz/fanboy-annoyance.txt | EasyList のリポジトリのデュアルライセンス。FilterLists と先頭の行の要約では CC BY 3.0 | ［二次情報］ | どちらでも、表示すれば営利の利用ができる |
| EasyList Cookie List | https://secure.fanboy.co.nz/fanboy-cookiemonster.txt | 同上 | ［二次情報］ | Cookie の同意の表示 |
| AdGuard Cookie Notices（ID 18） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_18_Annoyances_Cookies/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Popups（ID 19） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_19_Annoyances_Popups/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Mobile App Banners（ID 20） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_20_Annoyances_MobileApp/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Other Annoyances（ID 21） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_21_Annoyances_Other/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Widgets（ID 22） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_22_Annoyances_Widgets/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Mobile Ads（ID 11） | https://raw.githubusercontent.com/AdguardTeam/FiltersRegistry/master/filters/filter_11_Mobile/filter.txt | GPLv3（AdguardFilters） | ［二次情報］ | |
| AdGuard Annoyances（ID 14） | ― | ― | ［二次情報］ | メタデータで非推奨（deprecated） |
| uBlock filters – Annoyances | https://ublockorigin.github.io/uAssets/filters/annoyances.txt | GPLv3（uAssets の LICENSE） | ［二次情報］ | URL は assets.json の要約から |
| もちフィルタ | https://raw.githubusercontent.com/eEIi0A5L/adblock_filter/master/mochi_filter.txt ほか | README では「CC0 (Public Domain)」。LICENSE のファイルはない | ［二次情報］ | 最後の更新 2025-11-15 |
| AdGuard Japanese filter Plus | https://yuki2718.github.io/adblock2/japanese/jpf-plus.txt | GPLv3（リポジトリ） | ［二次情報］ | Safari・iOS は正式には対象外（多くのルールが動かない、とされている） |
| Yuki's uBlock Japanese filters | ― | CC BY-SA 4.0 | ［二次情報］ | 2022-12-01 にアーカイブ。2022 年 10 月で更新が止まっている |
| nanj-filter | ― | CC0 | ［二次情報］ | 最後の更新 2018-03-27。280blocker と一緒に使う前提のもの |

出典：https://adguard.com/kb/general/ad-filtering/adguard-filters/ 、 https://easylist.to/ 、 https://github.com/uBlockOrigin/uAssets 、 https://github.com/eEIi0A5L/adblock_filter 、 https://github.com/Yuki2718/adblock2 、 https://github.com/nanj-adguard/nanj-filter 、 https://filterlists.com/

- GPLv3 のリストを使うと、そのカテゴリの JSON は GPLv3 で配ることになります（[AdGuard Japanese filter](#adguard-japanese-filter今は無効) と同じ注意）。
- annoyance（プレミアム）のカテゴリに入れるなら、今の annoyance は自作ルールだけなので、ライセンスをそろえる相手は自作ルールだけです。

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

- ツール（`Sources/`・`Tests/`・`scripts/`・`.github/`、サイトのページ）のライセンスは未定です。決まるまで LICENSE を置いていません。
- LICENSE がないあいだは、公開リポジトリで読めても、既定の著作権のもとにあり、他の人が再利用する許可は与えていない状態です。
- ツールは変換器（GPLv3）にリンクしていないので、変換器のライセンスはツールのライセンスの選び方を縛りません。
- 決めたら、`LICENSE`（ツール用）を置き、README・`NOTICE`・`site/licenses.html` の「未定」を直します。

---

## 決めることの一覧

| 決めること | 選択肢 | 関係するところ |
|---|---|---|
| 変換後のリストのライセンス | CC BY-SA 3.0（今）／ CC BY-SA 4.0 ／ GPLv3 | [3.](#3-cc-by-sa-30-と-40)、[4.](#4-配る場所ごとの義務のまとめ) |
| アプリに同梱するリストの扱い | 4(a) の条項との関係を確かめる | [3.](#確かめていないこと) |
| manifest にライセンスの表記を足すか | 足す（形式の変更）／ 足さない | [3.](#確かめていないこと) |
| AdGuard Japanese filter を使うか | 使わない（今）／ GPLv3 で使う | [6.](#adguard-japanese-filter今は無効) |
| annoyance に上流のリストを使うか | 自作ルールだけ（今）／ 表の候補から選ぶ | [7.](#7-ほかの候補広告不快な要素日本向け) |
| 詐欺サイトのデータ | 手で書く（案）／ 許可や契約を得て使う | [8.](#8-詐欺サイトのデータの候補scam第-2-段階) |
| ツールのライセンス | 未定 | [9.](#9-ツールのライセンス) |
