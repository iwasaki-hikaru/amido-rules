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
4. 月に 1 回くらい、上流のリストの先頭の行を確かめます。`report.json`（実行の artifact「rules-out」）の各ソースの `headerLines` に、ライセンス・版・更新日の行が記録されています。
   - 対象：EasyList、Fanboy's Social Blocking List、Fanboy's Notifications List、EasyPrivacy。
   - `License`・`Licence` の行が変わっていたら、[licensing.md](licensing.md) を見直します。見直すまでは、そのソースを `sources.yml` で `enabled: false` にすることも考えます（件数が大きく変わるので、[件数の変化で CI が止まったとき](#件数の変化で-ci-が止まったとき)の手順で許可する）。
   - 2026-10-01 の時点：EasyList は `! Licence: https://easylist.to/pages/licence.html`、Fanboy の 2 つは `! License: http://creativecommons.org/licenses/by/3.0/`。EasyPrivacy は EasyList と同じ行（2026-10-02 に確認）。
5. EasyPrivacy の除いた節を確かめます。`summary.md` の「ソース」の下に「EasyPrivacy：節を N 個除きました」が出ます（2026-10-02 の時点で 20 個）。数が大きく変わったら、上流が節を足したか、名前を変えたかを確かめます（[EasyPrivacy の節を除けなかったとき](#easyprivacy-の節を除けなかったとき)）。
6. `summary.md` の「前のカテゴリにも効く例外ルール」で、privacy の例外の数と、そのうちホストだけを限ったものの数を見ます。急に増えていたら、どのホストかを `build/out/v1/lists/privacy.*.json`（実行の artifact）で確かめます。annoyance のルールが、そのホストで効かなくなっているかもしれません。

### 2. 定期実行が止まっていないかを確かめる

公開リポジトリでは、リポジトリに 60 日間動きがないと、GitHub が定期実行（`schedule`）を自動で止めます。止まっても通知は来ず、ルールの更新が黙って止まります。

- 「Actions」→「ルールの公開」を開き、「This scheduled workflow is disabled …」という表示が出ていないかを見る。
- 止まっていたら、同じ画面の「Enable workflow」を押す。`gh` を使うなら：
  ```bash
  gh workflow enable publish.yml --repo <owner>/<rules リポジトリ>
  ```
- 直近の `schedule` の実行が、毎週あるかも確かめる。
- 参考：本番の manifest の `published_at` は、ルールが変わったときだけ新しくなります。上流（EasyList はほぼ毎日、Fanboy の 2 つのリストは数日ごと）が更新されるので、ふつうは毎週変わりますが、止まっているかどうかは Actions の実行の履歴で確かめてください。
- 利用者に新しいルールが届くのは、この週 1 回の公開（と、main への push での公開）のときです。上流が数日ごとに更新されても、届くのは週 1 回です。
  ```bash
  curl -s https://<配信ホスト>/v1/manifest.json | jq '{version, published_at}'
  ```

### 3. 利用者からの報告を読む

- 報告は Google フォームで受け取ります。回答の場所：フォームの編集画面の「回答」タブ（スプレッドシートにつないだら、ここを直す）
- 報告を、次のどれかに分けます。
  - **広告が消えない**：ルールを足す候補（[4.](#4-自作ルールを足す)）
  - **表示が崩れる・ボタンが押せない**（ブロックしすぎ）：例外ルールを足す候補。影響が大きいので先に対応する
  - **その他**（設定のしかた、課金など）：サポートのページの FAQ に足すかを考える
- 報告の中の URL は、そのまま開かずに、ドメインを確かめてから開きます（詐欺サイトの報告の場合があるため）。
- 報告には、アプリの版と iOS の版が入っています。特定の iOS でだけ起きる問題かどうかの手がかりにします。
- 受け取ってから 1 年たった回答は消します（プライバシーポリシーの 6. の保存期間）。

### 4. 自作ルールを足す

#### どのファイルに書くか

| ファイル | カテゴリ | 入る拡張 | 書いてよいもの |
|---|---|---|---|
| `custom/basic.txt` | basic（無料） | 基本 | 広告のブロック、basic の中の誤ブロックの例外 |
| `custom/annoyance.txt` | annoyance（プレミアム） | プラス | 迷惑な表示（SNS の共有・いいね・フォローのボタン、通知の案内、アプリへの誘導）のうち、Fanboy のリストにないもの。Fanboy のリストから外すための例外（`#@#`）と、annoyance の中の例外 |
| `custom/scam.txt` | scam（プレミアム・第 2 段階） | プラス | 詐欺サイトのブロック。**すべての URL に効く例外ルール（`@@||example.jp^$document` など）は書けない**（CI が失敗する。理由は README の「例外ルールが効く範囲」）。URL を限った例外は書けるが、前のカテゴリ（annoyance・privacy）にも効くので、なるべく書かない |

privacy（トラッキング防止）の自作ルールのファイルは、まだありません。EasyPrivacy のせいでサイトが崩れ、例外を足すときは、`custom/privacy.txt` を作り、`sources.yml` に `category: privacy` の項目を足します（ほかの自作ルールと同じ書き方。テストの `SourcesTests` の件数も直す）。privacy は拡張の 2 番目なので、例外は URL やホストを限ったもの（例：`@@||googletagmanager.com^$domain=example.jp`）にします。すべての URL に効く例外（`@@||example.jp^$document` など）は CI が失敗します。そのサイトで全部を止めたいときは、利用者に許可サイトを案内します。

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
   - サイトそのものを止めるとき（`custom/scam.txt` など）は、オプションを付けない `||example.jp^` で書きます。`$document` だとトップのページしか止まらず（ツールがトップの文書に限るため。README の「変換器」）、`$document,subdocument` は変換器の都合で iframe しか止まりません。
   - 誤ブロックを直すときは、なるべく狭い例外にします。`@@||example.jp^$document` は、そのサイトで同じカテゴリ（と、同じ拡張の前にあるカテゴリ）のルールをすべて止めるので、最後の手段です。
   - 原因が EasyList のルールなら、EasyList にも報告すると、ほかの利用者のためにもなります（[EasyList の issue](https://github.com/easylist/easylist/issues)）。Fanboy の 2 つのリストも、元のファイルは EasyList のリポジトリ（`fanboy-addon/`）にあります。
   - 原因が Fanboy のリスト（annoyance）のルールなら、`custom/annoyance.txt` に要素の例外（`example.com#@#.selector`。元のルールと同じドメインと同じセレクタ）を書きます。プレミアムで約束していないもの（同意のダイアログ・ログイン・有料記事の案内・コメント欄・年齢確認・アフィリエイトの表示）を隠すルールも、同じように外します。根拠の行には、確かめたページの URL（リストを読んで外すときは、リストの URL）と (日付) だけを書き、説明は次の行の `! 理由:` に書きます。例外の 1 行ごとに、根拠の行が要ります。
     ```
     ! 根拠: https://example.com/article/123 (2026-10-05)
     ! 理由: Fanboy's Social Blocking List の「example.com##.comments」で、コメント欄が隠れていた
     example.com#@#.comments
     ```
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
- プレミアム（annoyance。Fanboy の 2 つのリスト）の確認用のサイトは、SNS の共有ボタンや「通知を受け取りますか」の案内が出るページを選ぶ。日本の主なサイトでは、見た目が変わらないことも多い（2026-10-01 の確認では、主要 10 サイトのうち見た目が変わったのは Game8 の共有ボタンだけ。本文が隠れたページは 14 ページで 0）
- プレミアムで、同意のダイアログ・ログイン・有料記事の案内・コメント欄・年齢確認が消えていないかも見る（消えていたら、[4.](#4-自作ルールを足す) の手順で例外を書く）
- トラッキング防止（privacy。EasyPrivacy）もオンにして見る。EasyPrivacy は Google タグマネージャー（googletagmanager.com）を丸ごと止めるので、それで読み込むチャットや同意の画面が出なくなるサイトがある（上流は、そのための例外を約 510 のドメインに持っている。2026-10-02 に確認）。楽天市場では `/akam/13/` の読み込みが止まるので、ボットの確認の画面が出ないかも見る（2026-10-02 の時点で未確認）。崩れていたら、アプリのホームで「トラッキング防止」だけをオフにして見比べ、原因が privacy かを確かめる

| 区分 | サイト | 確かめること | 根拠 | 最後に確かめた日 | 結果 |
|---|---|---|---|---|---|
| ニュース・ポータル | [Yahoo! JAPAN](https://www.yahoo.co.jp/) | トップのニュース・検索窓・天気の欄が崩れない。広告が消えた所に大きな空白や重なりが出ない | SW 総合 2 位・ニュース 1 位、SR 3 位、AH 1 位 | | |
| ニュース・ポータル | [Yahoo!ニュース](https://news.yahoo.co.jp/) | トップ → 記事 → 続きのページ → コメント欄まで開いてスクロールできる。記事中の広告が消える | SW 総合 4 位・ニュース 2 位 | | |
| ニュース・ポータル | [日本経済新聞](https://www.nikkei.com/) | トップと無料記事が読める。有料記事の案内とログインボタンが出る（ログインしない） | SW ニュース 5 位、AH 30 位 | | |
| 天気 | [tenki.jp](https://tenki.jp/) | 地域の予報と雨雲レーダーが動く。記事下のおすすめ広告が消えても崩れない | SW 総合 28 位、SR 10 位、AH 9 位 | | |
| 地図 | [Google マップ](https://www.google.com/maps) | 地図の表示・移動・拡大、場所の検索、電車の経路検索ができる | SW 地図 1 位 | | |
| 乗換案内 | [駅探](https://ekitan.com/) | 出発駅と到着駅を入れて乗換の結果が出る。時刻表のページが開く | SW 地図 3 位、AH 97 位 | | |
| 広告の多い情報サイト | [デリッシュキッチン](https://delishkitchen.tv/) | レシピを検索 → レシピのページ → 動画の再生。材料と手順が隠れない | SW レシピ 1 位、AH 8 位 | | |
| 広告の多い情報サイト | [クラシル](https://www.kurashiru.com/) | 同上。記事中の広告枠が消えて、本文が読める | SW レシピ 2 位、AH 28 位、[JJ] | | |
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
| 自治体 | 【要記入：人口の多い自治体（例：横浜市・大阪市）】 | トップ・お知らせ・検索が開く | アクセスの多い自治体の公開の順位は見つからなかった。**このリポジトリは公開なので、住んでいる市区町村は書かない** | | |
| 攻略サイト | [GameWith](https://gamewith.jp/) | 攻略記事のページで、目次・表・コメント欄が崩れない。記事中と下の広告が消える | SW 総合 38 位、AH 23 位、[JJ]（攻略サイト） | | |
| 攻略サイト・プレミアム | [Game8](https://game8.jp/) | 同上。プレミアムでは、記事の共有ボタンが消え、本文と目次は隠れない | AH 50 位、[JJ]。2026-10-01 に、Fanboy のルール（`.c-share` など）で共有ボタンが隠れることを WebKit で確認 | | |
| プレミアム | [毎日新聞](https://mainichi.jp/) | 記事のページ（`/articles/…`）で、共有ボタンと、フッターの SNS へのリンクが消える。本文は隠れない | 2026-10-01 に、Fanboy のルールで共有ボタン 3 つと `.footer-sns` だけが隠れることを WebKit で確認 | | |

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
   - 上流の変化：`report.json`（実行の artifact「rules-out」）の各ソースの行数を、前の実行と比べる。上流のリスト（EasyList、Fanboy's Social Blocking List、Fanboy's Notifications List、EasyPrivacy）を直接開いて、壊れていないかを見る。
   - こちらの変更：直前にマージした PR（リストを足した・外した、変換器を上げた、など）。
3. **意図した変化・問題のない変化なら**：
   - main の公開：「Actions」→「ルールの公開」→「Run workflow」→ ブランチ `main`、「件数の大きな変化を許す」（`allow_count_change`）にチェック →「Run workflow」。
   - PR の検査：中身を確かめてから、PR にラベル `allow-count-change` を付ける（付けると検査し直す）。マージしたあとの自動の公開は同じ理由で止まるので、上の手動の実行をします。
4. **上流の事故なら**：何もしません。本番には前の版が残っています。上流が直ったあとの定期実行（または手動の実行）で、元に戻ります。長く直らないときは、`sources.yml` でそのソースを `enabled: false` にすることも考えます（その場合も件数が大きく変わるので、上の 3. で許可する）。

本番の manifest を取得できないとき（ネットワークの失敗、5xx）も、比べられないので失敗にします。しばらくしてから流し直してください。

### EasyPrivacy を初めて公開するとき（privacy が新しく入る）

- 2026-10-02 に、privacy（トラッキング防止）を新しいカテゴリとして足しました（`sources.yml` の EasyPrivacy）。
- 件数の変化の検査は、前の版になかったカテゴリを比べません（「新しい」と出るだけ）。そのため、privacy が初めて入る公開では、この検査では止まりません。annoyance と basic の件数は変わりません。
- 公開したあと、`/check` で「トラッキング防止」が「有効」になることを、プレミアムの状態で確かめます。

### Fanboy のリストを初めて公開するとき（annoyance の件数が大きく増える）

- 2026-10-01 に、annoyance に Fanboy's Social Blocking List と Fanboy's Notifications List を足しました（`sources.yml`）。
- 本番に、annoyance が 1 件（`/check` 用のルールだけ）の版がすでにあると、次の公開で annoyance が 1 件から約 4,243 件になります（2026-10-01 の手元のビルド）。件数の変化の検査（30% 超かつ 100 件超）を超えるので、PR の検査も公開も止まります。
- これは意図した変化です。[上の 3.](#対応) のとおり、PR にはラベル `allow-count-change` を付け、マージしたあとは「Run workflow」で `allow_count_change` にチェックを付けて実行します。
- 本番に manifest がまだない、最初の公開（[初回の公開](#初回の公開)）では、件数を比べないので、この手順は要りません。
- 公開したあと、`/check` で「迷惑な表示」が「有効」になること、見本のページ（`site/demo/social.html`。本番では `/demo/social`）で、見本の共有ボタンと通知の案内が消えることを確かめます（プレミアムの状態で）。

---

## 例外ルールの検査で CI が止まったとき（privacy・scam）

### 何が起きたか

拡張の中で 2 番目以降のカテゴリ（プラスの privacy と scam）の例外ルールは、同じ拡張の前のカテゴリ（annoyance など）にも効きます。そのうち、**すべての URL に効く例外**（`url-filter` が `.*` など。上流の `@@||example.com^$document`・`@@||example.com^$generichide`・`@@*$domain=example.com` などを変換したもの）があると、前のカテゴリのルールをそのサイトでまるごと止めてしまうので、rulestool は失敗します（[format.md](format.md) の「例外ルールが効く範囲」）。

エラーは「privacy：rules[番号]: 拡張の中で 2 番目以降のカテゴリに、すべての URL に効く例外ルール……」の形で、実行の「Summary」のエラーに出ます。止まっているあいだも、本番には前の版がそのまま残っています。利用者への影響は「ルールの更新が止まる」だけです（basic の更新も止まります）。

2026-10-02 の時点では、EasyPrivacy にこの形の例外は 0 件です。上流が足したときに起きます。

### 対応

1. どのルールかを確かめる。`build/work/privacy.txt`（実行の artifact、または手元の `scripts/build-local.sh --online`）で、`$document`・`$generichide`・`$elemhide`・`$genericblock` の付いた `@@` の行や、`@@*$domain=…` の形の行を探します。上流の EasyPrivacy（https://easylist.to/easylist/easyprivacy.txt ）でも同じ行を探し、どの節にあるか、何のための例外か（GitHub の EasyList の履歴）を確かめます。
2. 決める。どれも、決めてから PR にします（根拠と理由を残す）。
   - **その例外を除く**：今の仕組みには、上流の 1 行だけを除く設定はありません。除くなら、その行を含む節を `exclude_sections` で除くか、rulestool に行を除く設定を足す（ツールの変更。テストを付ける）ことになります。除くと、上流がそのサイトの崩れを直した分が戻らないことに注意します。
   - **privacy を拡張の 1 番目に移す**：`config/budgets.json` とアプリの `RuleCategory`（BlockerCore）を同時に変える必要があり、アプリの更新が要ります。今のアプリには効かないので、急ぎの対応には使えません。
   - **EasyPrivacy をいったん外す**：`sources.yml` で `enabled: false` にします。privacy が manifest からなくなるので、件数の変化の検査で止まります。[件数の変化で CI が止まったとき](#件数の変化で-ci-が止まったとき)の手順で許可します。アプリでは、トラッキング防止のスイッチが出なくなります。
3. 急がないなら、何もしなくても本番は前の版のままです。上流が例外を狭めることもあるので、次の週の実行を待つこともできます。ただし、basic（EasyList）の更新も一緒に止まるので、長く止めないようにします。

## EasyPrivacy の節を除けなかったとき

`sources.yml` の EasyPrivacy は、見出しが `! *** easylist:easyprivacy/easyprivacy_specific_cname_` で始まる節（CNAME の節）を除きます（`exclude_sections`）。当たる節が 1 つもないと、「EasyPrivacy：sources.yml の exclude_sections（…）に当たる節が 1 つもありません」で失敗します。除かずに公開すると、privacy が約 2.3 万件から約 5.6 万件に増えるためです（プラスが約 6 万件になる。iOS 18 では 4.5 万件を超えると読み込みに失敗するという報告がある。アプリの docs/device-verification.md）。

1. 上流の EasyPrivacy（https://easylist.to/easylist/easyprivacy.txt ）を開き、`! *** ` で始まる見出しの行を確かめます（`curl -s https://easylist.to/easylist/easyprivacy.txt | grep -n '^! \*\*\* '`）。
2. CNAME の節の名前が変わっていたら、`sources.yml` の `exclude_sections` を新しい名前の始まりに直します。節が 2 つの名前に分かれたなど、1 つの始まりで書けないときは、rulestool に複数の値を書けるようにする変更が要ります（ツールの変更。テストを付ける）。
3. 手元で `scripts/build-local.sh --online` を実行し、`build/out/summary.md` の「EasyPrivacy：節を N 個除きました」と、privacy の件数（2026-10-02 の時点で約 2.3 万件）を確かめてから PR にします。

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

1. 「Actions」→「iOS 17 の WebKit でコンパイル（手動）」→「Run workflow」。`run_id` は空でよい（main で「変換と検査」と「iOS 18.6 の WebKit でコンパイル」のジョブが成功した、最後の公開の実行のものを使う。「署名と公開」が失敗したり、承認を待っていたりしても使える）
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
4. API トークンを作る：**アカウントの API トークン**（ユーザーに結びつかず、CI に向く。Cloudflare の資料「Account API tokens」）にする。「Manage account」→「Account API tokens」→「Create Token」→ 権限は **Account → Workers Scripts → Edit** だけ。アカウント ID も控える（「Workers & Pages」の右側の「Account details」）。
   - 「User Details」「Memberships」などの読み取り権限は付けない（付けると、認証に失敗したときの wrangler の出力に、アカウントのメールが出ることがある。このリポジトリの Actions のログは誰でも読める）。
   - 有効期限（TTL）を付け、期限の前に作り直す。手元で使うトークンは別に作り、使い終わったら無効にする。
   - できれば、このアプリ専用の Cloudflare アカウントにする（Workers Scripts の権限は、アカウントの中のすべての Worker に効くため）。アカウントの 2 段階認証は、セキュリティキーかパスキーにする。アカウント名にメールアドレスが入っていたら、入らない名前に変える。
5. この Worker で、アクセスの記録（Workers Logs・Logpush・Tail など）が無効になっていることを確かめる（プライバシーポリシーの記載と合わせる。`wrangler.jsonc` でも `observability` を無効にしている）。新しく作った Worker は、既定で記録が有効になる（Cloudflare のドキュメント、2026-08-11 更新）。プライバシーポリシーの 4. と、App Privacy の答え（ルールの取得の IP アドレスなどは、集めるデータに含めない。2026-10-04 に決めた答えは ios リポジトリの `docs/appstore/app-privacy.md`）の前提なので、公開のあとも設定を変えない。`check-config.mjs` が、記録を有効にする設定を失敗にする。

### このリポジトリの値

ios リポジトリの `scripts/configure.swift` を使うと、アプリ名・配信ホスト（`config/distribution.json` と `wrangler.jsonc` の `name`）・rules リポジトリの URL・フォームの URL を、両方のリポジトリにまとめて書き込めます（`--apply` を付けるまでは表示だけ）。手で書き換える場合は次のとおり。

6. 配信ホストを 3 か所で同じにする（英小文字で）：
   - `config/distribution.json` の `host`（`<Worker 名>.<サブドメイン>.workers.dev`）
   - `wrangler.jsonc` の `name`（`<Worker 名>`）
   - アプリの `ios/App/Config/AppConfig.swift` の `distributionHost`
7. 署名の鍵を作って登録する：`scripts/keygen.sh <リポジトリの外のディレクトリ>`（[signing.md](signing.md)）。`keys/trusted-public-keys.json` とアプリの公開鍵を同じにする。
8. `site/` の「【要記入：…】」をすべて埋め、「【要確認：…】」を確かめて消す。特定商取引法に基づく表記は `site/tokushoho.html`（2026-10-05 に載せた。価格を変えたら直す）。残りの数は `node .github/scripts/check-config.mjs` が表示します
9. ライセンスの判断（[licensing.md](licensing.md)）を済ませ、決めたものに合わせて `LICENSE-rules`・`NOTICE`・`site/licenses.html` を直す。

### GitHub

10. 公開リポジトリを作って push する。Issues を有効にしておく（失敗の報告に使う）。
11. **アカウントを守る**（いちばん大事）：main に push できる人は、正しく署名されたルールを公開できます（署名は CI の中で自動で行うため）。
    - GitHub の 2 段階認証を、パスキーかセキュリティキーにする（「Settings」→「Password and authentication」）。
    - 使っていない Personal access token・SSH の鍵・連携アプリを消す（「Settings」→「Developer settings」「SSH and GPG keys」「Applications」）。`gh` を使っているなら、そのトークンも見直す。
    - 「Settings」→「Emails」で「Keep my email addresses private」と「Block command line pushes that expose my email」をオンにする。
12. 「Settings」→「Environments」→ `production` を、**Secret を登録する前に**作る（存在しない environment をワークフローが使うと、保護なしで自動で作られるため）。
    - 「Deployment branches and tags」を「Selected branches and tags」にして、`main` だけにする。
    - 「Environment secrets」に `RULES_SIGNING_KEY`・`CLOUDFLARE_API_TOKEN`・`CLOUDFLARE_ACCOUNT_ID` を登録する。
    - 「Required reviewers」に自分を入れ、「Allow administrators to bypass configured protection rules」をオフにすることをすすめます（公開リポジトリなら無料のプランでも使える）。main に書き込めるトークンが盗まれても、`Sources/`・`deploy/package-lock.json`・`.github/scripts/` を書き換えれば、秘密鍵やトークンを持ち出せてしまいます。承認があれば、その前に止められます。代わりに、公開のたび（週 1 回の定期実行も）承認が要ります。1 人で運用するので「Prevent self-review」はオンにしない。
13. 「Settings」→「Actions」→「General」：
    - 「Actions permissions」を「Allow <owner>, and select non-<owner>, actions and reusable workflows」にして、「Allow actions created by GitHub」だけをオンにする。「Require actions to be pinned to a full-length commit SHA」をオンにする。
    - 「Approval for running fork pull request workflows from contributors」を「Require approval for all external contributors」にする（既定は「初めての人だけ」。承認がないと、ほかの人の PR が macOS のランナーで動く）。
    - 「Workflow permissions」を「Read repository contents and packages permissions」にする（各ワークフローで必要な権限だけを付けている）。
14. 「Settings」→「Rules」→「Rulesets」で、main の force push と削除を禁止する。PR の検査（`pr.yml`）を必須にするかは任意。
15. 「Settings」→「Advanced Security」（または「Code security」）で、Secret Protection と Push protection、Dependabot alerts、Private vulnerability reporting をオンにする（公開リポジトリは無料）。脆弱性の報告の受け付け方は `SECURITY.md` に書いてある。

### 初回の公開

16. 上の変更を main にマージすると、`publish.yml` が動きます（本番に manifest がないので、件数は比べません）。
17. 成功したら、次を確かめる：
    ```bash
    swift run -c release rulestool verify --base-url https://<配信ホスト>/
    for page in / /privacy /terms /support /licenses /check /tokushoho /demo/news /demo/recipe /demo/social; do
      curl -s -o /dev/null -w "%{http_code} $page\n" "https://<配信ホスト>$page"
    done
    curl -sI https://<配信ホスト>/v1/manifest.json.sig | grep -i 'content-type\|cache-control'
    ```
18. App Store Connect に、プライバシーポリシーの URL（`https://<配信ホスト>/privacy`）とサポートの URL（`https://<配信ホスト>/support`）を登録する。

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
