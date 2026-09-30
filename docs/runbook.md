# 運用の手順（runbook）

ルールの配信を続けるための手順です。週 1 回の作業、困ったときの対応、最初の公開の準備をまとめています。

- 配信の形式：[format.md](format.md)
- 署名の鍵：[signing.md](signing.md)
- ライセンス：[licensing.md](licensing.md)

「【要記入：…】」は、運営者が決めて埋める箇所です。

---

## 週 1 回の作業

自動の公開（`publish.yml`）は、毎週月曜 03:37（日本時間）に動きます。その日のうちに、次の順で確かめます。

- [ ] 1. 自動の公開が動いて、成功したか
- [ ] 2. 定期実行が止まっていないか
- [ ] 3. 利用者からの報告を読む
- [ ] 4. 必要なら自作ルールを足す（PR → CI → マージ）
- [ ] 5. 主なサイトで、表示が崩れていないかを確かめる

### 1. 自動の公開の結果を確かめる

1. GitHub の「Actions」→「ルールの公開」を開き、月曜の実行（`schedule`）を見る。
2. 実行の「Summary」に、ルールのビルドのまとめ（カテゴリごとの件数、予算、WebKit でのコンパイル、前の版との比較、警告）と、「公開」の表が出ます。
   - 「本番との比較：unchanged」「公開する：false」なら、ルールが変わっていないので公開していません。正常です。
   - 警告は、内容を読んで、放っておいてよいかを判断します（例：「拡張 basic の件数が警告の値を超えています」が続くなら、[予算を超えそうなとき](#予算を超えそうなとき)）。
3. 失敗していたら、「週 1 回のルールの公開が失敗しました」という issue ができています。[公開が失敗したとき](#公開が失敗したとき)の手順で対応します。
   - 失敗しても、本番には前の版がそのまま残っています。利用者への影響は「ルールの更新が止まる」だけです。

### 2. 定期実行が止まっていないかを確かめる

公開リポジトリでは、リポジトリに 60 日間動きがないと、GitHub が定期実行（`schedule`）を自動で止めます。止まっても通知は来ず、ルールの更新が黙って止まります。

- 「Actions」→「ルールの公開」を開き、「This scheduled workflow is disabled …」という表示が出ていないかを見る。
- 止まっていたら、同じ画面の「Enable workflow」を押す。`gh` を使うなら：
  ```bash
  gh workflow enable publish.yml --repo <owner>/<rules リポジトリ>
  ```
- 直近の `schedule` の実行が、毎週あるかも確かめる。
- 参考：本番の manifest の `published_at` は、ルールが変わったときだけ新しくなります。上流（EasyList）はほぼ毎日更新されるので、ふつうは毎週変わりますが、止まっているかどうかは Actions の実行の履歴で確かめてください。
  ```bash
  curl -s https://<配信ホスト>/v1/manifest.json | jq '{version, published_at}'
  ```

### 3. 利用者からの報告を読む

- 報告は Google フォームで受け取ります。回答の場所：【要記入：フォームの回答の確認場所（回答のタブ、またはつないだスプレッドシート）】
- 報告を、次のどれかに分けます。
  - **広告が消えない**：ルールを足す候補（[4.](#4-自作ルールを足す)）
  - **表示が崩れる・ボタンが押せない**（ブロックしすぎ）：例外ルールを足す候補。影響が大きいので先に対応する
  - **その他**（設定のしかた、課金など）：サポートのページの FAQ に足すかを考える
- 報告の中の URL は、そのまま開かずに、ドメインを確かめてから開きます（詐欺サイトの報告の場合があるため）。
- 報告には、アプリの版と iOS の版が入っています。特定の iOS でだけ起きる問題かどうかの手がかりにします。

### 4. 自作ルールを足す

#### どのファイルに書くか

| ファイル | カテゴリ | 入る拡張 | 書いてよいもの |
|---|---|---|---|
| `custom/basic.txt` | basic（無料） | 基本 | 広告のブロック、basic の中の誤ブロックの例外 |
| `custom/annoyance.txt` | annoyance（プレミアム） | プラス | 不快な広告など、プレミアムで隠すもの。annoyance の中の例外 |
| `custom/scam.txt` | scam（プレミアム・第 2 段階） | プラス | 詐欺サイトのブロック。**例外ルール（`@@…`）は書けない**（CI が失敗する。理由は README の「例外ルールが効く範囲」） |

#### 手順

1. **再現する**：報告のページを、iPhone の Safari で開きます。2 つの拡張がオンで、`https://<配信ホスト>/check` が「有効」になる状態で確かめます。
   - 表示が崩れる報告は、Safari のページメニューの「コンテンツブロッカーをオフにする」で直るかを確かめます。直らなければ、ルールの問題ではありません。
2. **原因を調べる**：iPhone を Mac につなぎ、Mac の Safari の「開発」メニューから Web インスペクタを開いて、要素のクラス名や、読み込んでいるファイルを確かめます。
3. **ルールを書く**：AdGuard / Adblock Plus の書式で書き、**すぐ上に根拠の行を書きます**。根拠がないルールがあると、CI が失敗します。
   ```
   ! 根拠: https://example.jp/article/123 (2026-10-05)
   example.jp##.ad-banner
   ```
   - 根拠の形は `! 根拠: <確かめたページの URL> (<確かめた日 YYYY-MM-DD>)` です。コロンは半角の `:`、URL と日付のあいだは半角の空白です。
   - ルール 1 件ごとに根拠が要ります。根拠の行とルールのあいだに、空行やほかのルールをはさまないでください。
   - `!#` と `!+` で始まる行（AdGuard の前処理の指示とヒント）は使えません。
   - ほかのリストからルールを写すときは、ライセンスを確かめてから。**280blocker、豆腐フィルタなど、ライセンス上使えないリストからは写しません**（[licensing.md](licensing.md)）。
   - 誤ブロックを直すときは、なるべく狭い例外にします。`@@||example.jp^$document` は、そのサイトで同じカテゴリ（と、同じ拡張の前にあるカテゴリ）のルールをすべて止めるので、最後の手段です。
   - 原因が EasyList のルールなら、EasyList にも報告すると、ほかの利用者のためにもなります（[EasyList の issue](https://github.com/easylist/easylist/issues)）。
4. **手元で確かめる**（任意）：
   ```bash
   scripts/build-local.sh
   ```
   `build/out/summary.md` で、件数が意図どおり増えたか、変換エラーが増えていないかを確かめます。
5. **PR を作る**：ブランチを切ってコミットし、PR を作ります。CI（`pr.yml`）が、根拠の検査、変換、WebKit でのコンパイル、本番との件数の比較をします。PR の「Checks」→ 実行の「Summary」で結果を見ます。
6. **マージする**：CI が通ったら main にマージします。`custom/` が変わったので、`publish.yml` が自動で動いて公開します。
7. **公開のあとに確かめる**：実行が成功したら、iPhone のアプリで手動で更新し（アプリは前回の確認から 24 時間たつまで自動では取りに行かないため）、報告のページで直ったかを確かめます。

### 5. 主なサイトで確かめる

ルールの更新で、よく使われるサイトの表示や操作が壊れていないかを、iPhone の Safari（2 つの拡張をオン、プレミアムの状態）で確かめます。崩れていたら、拡張をオフにして同じページと見比べ、ルールのせいかを確かめます。

- **ログインしない・購入しない**。銀行・証券はログインの画面が表示されるところまで、通販はカートの画面まで
- 動画の広告は消せないので、消えなくてよい（再生と表示が崩れないかだけを見る）
- 毎週すべてでなくてよい。ルールを大きく変えた週は全部、それ以外は各区分から 1 つずつ

選んだ根拠（2026-09-29 に調べたもの。順位は第三者による推計）：

- [SW] Similarweb「Top Websites Ranking – Japan」（2026 年 8 月）と区分別の順位 https://www.similarweb.com/top-websites/japan/
- [SR] Semrush（2026 年 8 月）https://www.semrush.com/trending-websites/jp/all
- [AH] Ahrefs Top（自然検索の流入の推計、2026 年 8 月）https://ahrefstop.com/websites/japan
- [JJ] 時事ドットコム（2025-07-05）：性的な広告が、ゲームの攻略サイトやレシピサイトに出ていたという記事 https://www.jiji.com/jc/v8?id=202507seitekiad-team
- 「広告あり」は、2026-09-29 に取った HTML に広告配信の読み込み（doubleclick・prebid・taboola など）があったことによる。どんな広告が出るかは確かめていない
- 2025 年 4 月以降、業界の自主規制で、不快な広告の出方が変わっている（ITmedia NEWS 2025-06-05）。プレミアムの確認用のサイトは、実際に不快な広告が出ているかを見て入れ替える

| 区分 | サイト | 確かめること | 根拠 | 最後に確かめた日 | 結果 |
|---|---|---|---|---|---|
| ニュース・ポータル | [Yahoo! JAPAN](https://www.yahoo.co.jp/) | トップのニュース・検索窓・天気の欄が崩れない。広告が消えた所に大きな空白や重なりが出ない | SW 総合 2 位・ニュース 1 位、SR 3 位、AH 1 位 | | |
| ニュース・ポータル | [Yahoo!ニュース](https://news.yahoo.co.jp/) | トップ → 記事 → 続きのページ → コメント欄まで開いてスクロールできる。記事中の広告が消える | SW 総合 4 位・ニュース 2 位 | | |
| ニュース・ポータル | [日本経済新聞](https://www.nikkei.com/) | トップと無料記事が読める。有料記事の案内とログインボタンが出る（ログインしない） | SW ニュース 5 位、AH 30 位 | | |
| 天気 | [tenki.jp](https://tenki.jp/) | 地域の予報と雨雲レーダーが動く。記事下のおすすめ広告が消えても崩れない | SW 総合 28 位、SR 10 位、AH 9 位 | | |
| 地図 | [Google マップ](https://www.google.com/maps) | 地図の表示・移動・拡大、場所の検索、電車の経路検索ができる | SW 地図 1 位 | | |
| 乗換案内 | [駅探](https://ekitan.com/) | 出発駅と到着駅を入れて乗換の結果が出る。時刻表のページが開く | SW 地図 3 位、AH 97 位 | | |
| 広告の多い情報サイト | [デリッシュキッチン](https://delishkitchen.tv/) | レシピを検索 → レシピのページ → 動画の再生。材料と手順が隠れない | SW レシピ 1 位、AH 8 位 | | |
| 広告の多い情報サイト | [クラシル](https://www.kurashiru.com/) | 同上。記事中の広告枠が消えて、本文が読める（不快な広告の確認も兼ねる） | SW レシピ 2 位、AH 28 位、[JJ] | | |
| 広告の多い情報サイト | [クックパッド](https://cookpad.com/jp) | 検索 → レシピ → つくれぽが表示される。ボット対策の画面で止まらない | SW レシピ 3 位、AH 19 位 | | |
| 通販 | [Amazon.co.jp](https://www.amazon.co.jp/) | 検索 → 商品ページ → カートに入れる → カートの画面まで（レジに進まない） | SW 総合 7 位、SR 6 位 | | |
| 通販 | [楽天市場](https://www.rakuten.co.jp/) | 検索 → 商品ページ → 買い物かごに入れる → かごの画面まで（購入手続きに進まない） | SW 総合 8 位、SR 7 位 | | |
| 銀行 | [楽天銀行（ログイン画面）](https://fes.rakuten-bank.co.jp/MS/main/RbS?CurrentPageID=START&&COMMAND=LOGIN) | 入力欄とボタンが表示される（何も入力せず、ログインしない） | SW 銀行・与信 1 位 | | |
| 証券 | [楽天証券（ログイン画面）](https://www.rakuten-sec.co.jp/ITS/V_ACT_Login.html) | 同上 | SW 総合 33 位・投資 1 位 | | |
| 銀行 | [三菱UFJ銀行](https://www.bk.mufg.jp/) | トップのログインからログインの画面が開ける（ログインしない） | SW 家計・資産管理 1 位（mufg.jp）、AH 80 位 | | |
| 動画・配信 | [YouTube](https://www.youtube.com/) | 検索 → 再生 → 全画面 → コメント。動画の広告は消えなくてよい | SW 総合 3 位、SR 2 位 | | |
| 動画・配信 | [ニコニコ動画](https://www.nicovideo.jp/) | 動画のページで再生とコメントが出る | SW 総合 49 位・配信 5 位 | | |
| SNS | [X](https://x.com/) | ログインせずに、公開の投稿やプロフィールの URL を開く。ログインの案内が出る（ログインしない） | SW 総合 5 位、SR 4 位 | | |
| SNS | [Instagram](https://www.instagram.com/) | 同上 | SW 総合 12 位 | | |
| SNS | [アメブロ](https://ameblo.jp/) | 公開ブログの記事と記事一覧が開ける。広告が消えても本文が読める | SW 総合 19 位・SNS 3 位、AH 18 位 | | |
| 自作ルールの対象 | [ライブドアニュース](https://news.livedoor.com/) | トップ → 記事。記事中の広告の枠（300px の空白）が消え、本文とパンくずが崩れない | SW 総合 34 位。`custom/basic.txt` に要素のルールあり | | |
| 広告ブロック対策のあるサイト | [日刊スポーツ](https://www.nikkansports.com/) | 記事が読める。「広告の表示を許可して」という全面の警告が出ない（Ad Shield。README の「変換器」） | 2026-09-29 に WebKit で警告が出たサイト。`custom/basic.txt` に配信のルールあり | | |
| 広告ブロック対策のあるサイト | [東洋経済オンライン](https://toyokeizai.net/) | 記事が読める。全面の警告が出ない | 同上（EasyList に、このサイト向けの例外あり） | | |
| 公的機関 | [日本郵便](https://www.post.japanpost.jp/)（[郵便追跡](https://trackings.post.japanpost.jp/services/srv/search/)） | トップと追跡番号の入力画面が表示される | SW 行政 1 位、AH 40 位 | | |
| 公的機関 | [国税庁](https://www.nta.go.jp/) | トップ・サイト内検索・PDF が開く | SW 行政 4 位、AH 75 位 | | |
| 自治体 | 【要記入：お住まいの市区町村など】 | トップ・お知らせ・検索が開く | アクセスの多い自治体の公開の順位は見つからなかった | | |
| 不快な広告（プレミアム） | [GameWith](https://gamewith.jp/) | 攻略記事のページで、目次・表・コメント欄が崩れない。記事中と下の広告が消える | SW 総合 38 位、AH 23 位、[JJ]（攻略サイト） | | |
| 不快な広告（プレミアム） | [Game8](https://game8.jp/) | 同上 | AH 50 位、[JJ] | | |

入れ替えの候補（どれも 2026-09-29 に開けることを確かめた）：Yahoo!天気・災害（SW 天気 1 位）、Yahoo!ショッピング（SW 総合 42 位）、メルカリ（SW 総合 41 位）、ABEMA（AH 70 位）、TVer（AH 90 位）、厚生労働省（SW 行政 2 位）、気象庁（AH 45 位）。NAVITIME（SW 旅行 1 位）は自動のアクセスを断るため確かめていないが、ブラウザでは開けるはず。

問題があれば、[4.](#4-自作ルールを足す) の手順で例外ルールを足すか、急ぐなら[前の版に戻します](#前の版に戻す)。

---

## 件数の変化で CI が止まったとき

### 何が起きたか

rulestool は、カテゴリごとの件数を本番の manifest と比べ、**変化が 30% を超え、かつ 100 件を超えた**ときに失敗します（しきい値は `config/budgets.json` の `countChange`）。本番にあったカテゴリがなくなったときも失敗します。上流のリストの事故（空になった、壊れた）をそのまま配信しないためです。

失敗の内容は、実行の「Summary」の「前の版との件数の比較」に出ます。

### 対応

1. まとめの表で、どのカテゴリが、何件から何件になったかを見る。
2. 原因を確かめる。
   - 上流の変化：`report.json`（実行の artifact「rules-out」）の各ソースの行数を、前の実行と比べる。上流のリストを直接開いて、壊れていないかを見る。
   - こちらの変更：直前にマージした PR（リストを足した・外した、変換器を上げた、など）。
3. **意図した変化・問題のない変化なら**：
   - main の公開：「Actions」→「ルールの公開」→「Run workflow」→ ブランチ `main`、「件数の大きな変化を許す」（`allow_count_change`）にチェック →「Run workflow」。
   - PR の検査：中身を確かめてから、PR にラベル `allow-count-change` を付ける（付けると検査し直す）。マージしたあとの自動の公開は同じ理由で止まるので、上の手動の実行をします。
4. **上流の事故なら**：何もしません。本番には前の版が残っています。上流が直ったあとの定期実行（または手動の実行）で、元に戻ります。長く直らないときは、`sources.yml` でそのソースを `enabled: false` にすることも考えます（その場合も件数が大きく変わるので、上の 3. で許可する）。

本番の manifest を取得できないとき（ネットワークの失敗、5xx）も、比べられないので失敗にします。しばらくしてから流し直してください。

---

## 予算を超えそうなとき

1 つの拡張に入れる件数とバイト数には、予算があります（`config/budgets.json`。値はアプリの `Budgets` と合わせる）。

| 拡張 | 警告 | 失敗 |
|---|---|---|
| 基本・プラス（それぞれ） | 55,000 件、または 8 MiB | 65,000 件、または 10 MiB |

- 件数は、その拡張に入るカテゴリの合計に、アプリが足す許可サイトの 1 件を加えたものです。バイト数には、許可サイトのルールが最大（500 件）になったときの分（128 KiB）を加えます。
- Safari の仕様上の上限は 1 拡張 15 万件ですが、実機ではずっと少ない件数で読み込みに失敗する報告があるため、低めにしています。
- 警告が出たら、次のどれかを考えます（どれも、判断してから行う）。
  - 上流のリストの中で、Safari で効果の薄いものを除く（除き方は、根拠とともに記録する）
  - 拡張を増やす（アプリの変更と、形式の変更が必要）
  - 実機で確かめたうえで、予算を上げる（`config/budgets.json` とアプリの `Budgets` を同時に直す）

---

## 公開が失敗したとき

実行の「Summary」と、失敗したステップのログを見ます。

| 失敗したところ | よくある原因 | 対応 |
|---|---|---|
| 環境を記録する（Xcode 26.6 がありません） | ランナーのイメージが変わって、Xcode 26.6 がなくなった | [actions/runner-images](https://github.com/actions/runner-images) の macOS 26 の README で、入っている Xcode を確かめ、3 つのワークフローの `DEVELOPER_DIR` を直す。変換結果が変わることがあるので、PR で CI を通してから |
| 変換器を用意する | GitHub から取得できない、タグが動かされた | 一時的なものなら流し直す。「タグのコミットが想定と違います」なら、何が起きたかを確かめるまで止める（[変換器を上げる](#道具の版を上げる)） |
| ルールを作って検査する | 上流を取得できない、件数の変化、予算の超過、根拠のないルール、WebKit でのコンパイルの失敗 | エラーの内容のとおりに直す。件数の変化は[上の手順](#件数の変化で-ci-が止まったとき) |
| 本番が build のときから変わっていないか確かめる | build と deploy の間に、巻き戻し（「前の版に戻す」）や別の公開で本番が変わった | 巻き戻したばかりなら、main を直してから公開する（そのまま流し直すと、巻き戻す前と同じ内容を公開し直してしまう）。意図しない変化なら、本番の版を確かめてから「Re-run all jobs」 |
| iOS 18.6 の WebKit でコンパイル | macOS では通るが、iOS 18 の WebKit では読めない書き方のルールがある（`WKErrorDomain 6`） | ログの「Error while parsing …」のルールを探し、自作のルールなら直す。上流のリストのルールなら、そのルールを除く方法を決める（除き方は根拠とともに記録する）。ランナーに iOS 18.6 やXcode 16.4 がなくなったときは、`DEVELOPER_DIR` と版を、`actions/runner-images` の macOS 15 の README に合わせて直す |
| 本番と比べる | 本番に届かない | 流し直す |
| 署名する | `RULES_SIGNING_KEY` が未登録、または鍵が `keys/trusted-public-keys.json` にない | [signing.md](signing.md) |
| 検証する（Node の crypto） | 署名や manifest の形がおかしい | rulestool と Node で結果が違うなら、原因がわかるまで公開しない |
| 版の名前を確保する | 同じ版のタグがすでにある | 「Re-run all jobs」で build ジョブからやり直す（版を決め直す） |
| Cloudflare に公開する | API トークンの期限切れ・権限不足、workers.dev のサブドメインがない | トークンを作り直して `CLOUDFLARE_API_TOKEN` を更新する（Account → Workers Scripts → Edit だけ） |
| 本番を検証する | 反映の遅れ、公開したものが壊れていた | 自動で前の版に戻しています（「検証に失敗したら、前の版に戻す」のステップ）。本番が前の版で正しく検証できるかを確かめ、原因を調べる |
| GitHub Release に保管する | 権限、一時的な失敗 | 公開は済んでいる。手で Release を作るか、次の公開を待つ |

「Re-run failed jobs」で deploy ジョブだけをやり直すと、build ジョブの結果（同じ版）をそのまま使います。

---

## 前の版に戻す

公開したルールでサイトが壊れたときなど、急いで戻したいときの手順です。

### 知っておくこと

- アプリは「manifest の版が今と違えば適用する」ので、古い版に戻すと、利用者の端末も古い版に戻ります。
- 利用者の端末に届くのは、アプリが次に確かめたとき（前回から 24 時間たったあと、アプリを開いたときや背景更新のとき。手動の更新ならすぐ）です。
- 戻した版の署名は、その版を公開したときの鍵のものです。鍵を入れ替えたあとに古い版へ戻すときは、[signing.md の「巻き戻しと鍵」](signing.md#巻き戻しと鍵)を先に読んでください。
- **戻したあと、main を直さないと、次の公開（push・週 1 回）でまた同じ内容が公開されます。** 原因の変更を revert する PR をマージするまで、必要なら定期実行を止めておきます（`gh workflow disable publish.yml`。直したら必ず `enable` に戻す）。

### 方法 1：直前の版に戻す（ふつうはこれ）

1. 「Actions」→「前の版に戻す」→「Run workflow」→ ブランチ `main`。
2. `version_id` と `release_tag` は空のまま、`reason` に理由を書いて実行。
3. `wrangler rollback` で、1 つ前にアップロードした Worker の版に戻し、本番の署名とリストを検証します。
4. 実行の「Summary」の「本番の版」を確かめる。

### 方法 2：特定の版に戻す

1. 戻す先の Worker の版の ID を調べる：Cloudflare の管理画面 →「Workers & Pages」→ この Worker →「Deployments」。公開のメッセージに `rules <版>` と書いてあるので、ルールの版と対応がわかります。
2. 「前の版に戻す」を、`version_id` にその ID を入れて実行する。

Cloudflare で戻せるのは、直近の 100 版までです。

### 方法 3：GitHub Release から公開し直す（100 版より前、または Cloudflare の記録で戻せないとき）

1. GitHub の「Releases」で、戻したい版のタグ（`rules-2026.10.05.1` など）を確かめる。
2. 「前の版に戻す」を、`release_tag` にそのタグを入れて実行する。
3. Release の一式（`rules-<版>.tar.gz`）を取得し、署名とリストを検証してから、その一式を公開し直します。

### 手元から戻す（GitHub Actions が使えないとき）

Cloudflare の管理画面の「Deployments」→ 戻したい版の「⋯」→「Rollback」でも戻せます。wrangler を使うなら：

```bash
cd deploy
npm ci
export CLOUDFLARE_API_TOKEN=…  # 手元用のトークン（Workers Scripts → Edit）。使い終わったら無効にする
export CLOUDFLARE_ACCOUNT_ID=…
npx wrangler rollback [<版の ID>] --config ../wrangler.jsonc --message "理由"
cd ..
swift run -c release rulestool verify --base-url https://<配信ホスト>/
```

---

## iOS 17 の WebKit で確かめる（リリースの前と、ルールを大きく変えたとき）

公開のワークフローは、iOS 18.6 のシミュレーターでだけコンパイルを確かめます。iOS 17 は手動です。

1. 「Actions」→「iOS 17 の WebKit でコンパイル（手動）」→「Run workflow」。`run_id` は空でよい（main での最後の成功した公開のものを使う）
2. iOS 17.0 と 17.5 の両方が成功すればよい。失敗したら、上の表の「iOS 18.6 の WebKit でコンパイル」と同じように直す
3. **2026-11-02 以降は使えません**（iOS 17 のシミュレーターがある macos-14 のイメージがなくなる。https://github.com/actions/runner-images/issues/13518 ）。それ以降は、このワークフローを消し、iOS 17 の実機か、手元に iOS 17 のランタイムを入れたシミュレーターで、`.github/scripts/ios-webkit-check.sh 17.5 <合成した JSON>` を実行する（合成した JSON は、公開の実行の成果物 `rules-compose`）

## 道具の版を上げる

どれも PR で行い、CI が通ることを確かめてからマージします。

- **GitHub のアクション**：各アクションのリリースのページで新しいタグを確かめ、そのタグのコミットの SHA を調べて、`uses:` の SHA とコメント（`# v7.0.1` など）を直す。SHA は、タグから調べたものを使う（例：`curl -s https://api.github.com/repos/actions/checkout/git/ref/tags/<タグ>`。`"type": "tag"` なら、指している先のコミットの SHA）。
- **wrangler**：`deploy/package.json` の版を直し、`cd deploy && npm install --package-lock-only --ignore-scripts` で `package-lock.json` を作り直す。
- **変換器（SafariConverterLib）**：`scripts/fetch-converter.sh` の `TAG` と `COMMIT` を直す（COMMIT はタグのコミットを自分で確かめる）。変換結果が変わるので、件数の変化で止まることがある。CI のまとめで、変換エラーや件数の変わり方を確かめる。
- **Xcode・ランナー**：`macos-26` と Xcode 26.6 に固定しています。上げるときは、3 つのワークフローの `runs-on` と `DEVELOPER_DIR` を同時に直す。

---

## 最初の公開の準備

上から順に行います。

### Cloudflare

1. アカウントを作る。
2. 管理画面の「Workers & Pages」で、workers.dev のサブドメインを一度作る（作らないと、CI からデプロイできない）。
3. Worker の名前を決める（英小文字・数字・ハイフン、63 文字まで、先頭と末尾はハイフン以外）。**サブドメインと名前は、アプリの公開後に変えられません**（README の「workers.dev を使うことのリスク」）。
4. API トークンを作る：「My Profile」→「API Tokens」→「Create Custom Token」→ 権限は **Account → Workers Scripts → Edit** だけ、対象はこのアカウントだけ。アカウント ID も控える。
5. この Worker で、アクセスの記録（Workers Logs・Logpush・Tail など）が無効になっていることを確かめる（プライバシーポリシーの記載と合わせる。`wrangler.jsonc` でも `observability` を無効にしている）。新しく作った Worker は、既定で記録が有効になる（Cloudflare のドキュメント、2026-08-11 更新）。App Store の App Privacy で「データの収集なし」と答える場合は、その前提になるので、公開のあとも設定を変えない（どう答えるかは ios リポジトリの判断材料で決める）。

### このリポジトリの値

ios リポジトリの `scripts/configure.swift` を使うと、アプリ名・配信ホスト（`config/distribution.json` と `wrangler.jsonc` の `name`）・rules リポジトリの URL・フォームの URL を、両方のリポジトリにまとめて書き込めます（`--apply` を付けるまでは表示だけ）。手で書き換える場合は次のとおり。

6. 配信ホストを 3 か所で同じにする（英小文字で）：
   - `config/distribution.json` の `host`（`<Worker 名>.<サブドメイン>.workers.dev`）
   - `wrangler.jsonc` の `name`（`<Worker 名>`）
   - アプリの `ios/App/Config/AppConfig.swift` の `distributionHost`
7. 署名の鍵を作って登録する：`scripts/keygen.sh <リポジトリの外のディレクトリ>`（[signing.md](signing.md)）。`keys/trusted-public-keys.json` とアプリの公開鍵を同じにする。
8. `site/` の「【要記入：…】」をすべて埋め、「【要確認：…】」を確かめて消す。特定商取引法に基づく表記を載せると決めたら、`docs/drafts/tokushoho.html` を `site/` に移して埋める。残りの数は `node .github/scripts/check-config.mjs` が表示します。`LICENSE-rules`・`NOTICE`・README の「【要記入】」も埋める。
9. ライセンスの判断（[licensing.md](licensing.md)）を済ませ、決めたものに合わせて `LICENSE-rules`・`NOTICE`・`site/licenses.html` を直す。

### GitHub

10. 公開リポジトリを作って push する。Issues を有効にしておく（失敗の報告に使う）。
11. 「Settings」→「Environments」→ `production` を作る。
    - 「Deployment branches and tags」を `main` だけにする。
    - 「Environment secrets」に `RULES_SIGNING_KEY`・`CLOUDFLARE_API_TOKEN`・`CLOUDFLARE_ACCOUNT_ID` を登録する。
    - 「Required reviewers」を付けると、公開のたびに承認が要ります（週 1 回の定期実行も承認待ちで止まる）。付けるかどうかは運営者が決める。
12. 「Settings」→「Actions」→「General」：
    - アクションをコミットの SHA で固定することを必須にする設定をオンにする。
    - 「Workflow permissions」を読み取りだけにする（各ワークフローで必要な権限だけを付けている）。
13. 必要なら、main を保護して、PR の検査（`pr.yml`）が通ることを必須にする。

### 初回の公開

14. 上の変更を main にマージすると、`publish.yml` が動きます（本番に manifest がないので、件数は比べません）。
15. 成功したら、次を確かめる：
    ```bash
    swift run -c release rulestool verify --base-url https://<配信ホスト>/
    for page in / /privacy /terms /support /licenses /check; do
      curl -s -o /dev/null -w "%{http_code} $page\n" "https://<配信ホスト>$page"
    done
    curl -sI https://<配信ホスト>/v1/manifest.json.sig | grep -i 'content-type\|cache-control'
    ```
16. App Store Connect に、プライバシーポリシーの URL（`https://<配信ホスト>/privacy`）とサポートの URL（`https://<配信ホスト>/support`）を登録する。

---

## 確かめるときのコマンド

```bash
# 本番の署名とリストを検証する（アプリと同じ順番）
swift run -c release rulestool verify --base-url https://<配信ホスト>/

# 手元の一式を、CryptoKit とは別の実装（Node の crypto）で検証する
node .github/scripts/verify-manifest.mjs --dir dist --keys keys/trusted-public-keys.json

# 本番の版と公開日時
curl -s https://<配信ホスト>/v1/manifest.json | jq '{version, published_at, lists: [.lists[] | {category, rule_count}]}'

# 手元で作った manifest が、本番と比べて変わったか
swift run -c release rulestool compare --manifest build/out/v1/manifest.json --previous https://<配信ホスト>/v1/manifest.json
```
