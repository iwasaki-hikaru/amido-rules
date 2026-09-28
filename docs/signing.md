# 署名の鍵

manifest の署名に使う鍵の形式、作り方、保管、入れ替え、漏れたときの対応です。配信の形式そのものは [format.md](format.md) にあります。

## しくみ

- CI が `manifest.json` のバイト列に Ed25519 で署名し、`manifest.json.sig` として一緒に配信します。
- アプリは公開鍵を 2 本（本番用 primary と予備 standby）埋め込み、**どちらかで検証できれば**受け入れます。検証できてから、manifest を JSON として読みます。
- manifest には各リストの SHA-256 と大きさが入っているので、署名が正しければ、リストも改ざんされていないと確かめられます。
- `keys/trusted-public-keys.json` が、このリポジトリで信頼する公開鍵の一覧です。**アプリに埋め込む公開鍵と同じにします。**
  - `rulestool sign` は、秘密鍵から求めた公開鍵がこのファイルにないとき、署名しません（違う鍵を登録してしまったことに、公開の前に気づくため）。
  - CI は署名のあと、rulestool（CryptoKit）と Node の crypto（OpenSSL）の両方で、このファイルの鍵を使って検証します。
- 秘密鍵は、GitHub の `production` environment の Secret `RULES_SIGNING_KEY` にだけ置きます。使うのは `publish.yml` の deploy ジョブの「署名する」ステップだけです。上流のリストや変換器を扱う build ジョブには渡しません。

## 鍵の形式

| もの | 形式 | 長さ |
|---|---|---|
| 秘密鍵 | 32 バイトの seed（CryptoKit の `Curve25519.Signing.PrivateKey.rawRepresentation`）を Base64 にしたもの | 44 文字 |
| 公開鍵 | 32 バイトの生の値を Base64 にしたもの | 44 文字 |
| 署名（`.sig`） | 64 バイトの署名を Base64 にしたものと、改行 | 88 文字 ＋ 改行 |

Base64 は標準のもの（`+` と `/`、パディングあり）です。

`keys/trusted-public-keys.json` の形：

```json
{"keys":[{"id":"primary","publicKey":"<Base64>"},{"id":"standby","publicKey":"<Base64>"}]}
```

- `id` は、検証の結果に「どの鍵で検証できたか」を表示するための名前です。
- 最初は `{"keys":[]}` です。鍵を登録するまで、公開（署名）はできません。

### 署名は毎回違う値になる

CryptoKit の Ed25519 の署名は、同じ鍵・同じ manifest でも、署名するたびに違う値になります（Apple の仕様。どれも正しく検証できます）。そのため：

- テストでは、署名の値を比べず、「検証できるか」で確かめます。
- CI は、配信するリストと `min_app_build` が本番と同じなら、署名し直しません（`rulestool compare`）。週 1 回の実行では何もせず、push や手動の実行では、本番の manifest と署名をそのまま使います。

## 鍵を作る

本番用と予備を、最初に 2 本とも作ります。予備を最初からアプリに入れておくと、本番用の鍵に問題があったとき、アプリを更新しなくても予備に切り替えられます。

```bash
scripts/keygen.sh ~/rules-signing-keys
```

- 保存先は、**このリポジトリ（と ios リポジトリ）の外**にします。中を指定すると止めます。
- `rules-signing-primary.key` と `rules-signing-standby.key` を、権限 0600 で書きます。すでにあれば上書きしません。
- 秘密鍵の中身は表示しません。公開鍵と、このあとの手順を表示します。

1 本だけ作るとき（入れ替えで新しい予備を作るときなど）は、rulestool を直接使います。

```bash
swift run -c release rulestool keygen --out ~/rules-signing-keys/rules-signing-<名前>.key
# 標準出力に公開鍵（Base64）が出る
```

### 作ったあとの手順

1. `keys/trusted-public-keys.json` を、2 本の公開鍵にする（PR で）。
2. 同じ 2 本の公開鍵を、iOS アプリ（`ios/App/Config/AppConfig.swift` の公開鍵の定数）に入れる。
3. 本番用の秘密鍵を、GitHub の Secret に登録する。
   - 画面から：「Settings」→「Environments」→ `production` →「Environment secrets」→「Add secret」。名前は `RULES_SIGNING_KEY`、値は `rules-signing-primary.key` の中身（1 行）。
   - `gh` を使うなら（中身を画面に出さずに登録できる）：
     ```bash
     gh secret set RULES_SIGNING_KEY --env production --repo <owner>/<rules リポジトリ> < ~/rules-signing-keys/rules-signing-primary.key
     ```
4. 2 本の秘密鍵を、パスワードマネージャーなど、GitHub の外の安全な場所に保管する（下の「保管」）。
5. 保管が済んだら、手元のファイルを消す。

## 保管

| 鍵 | 置く場所 | 置かない場所 |
|---|---|---|
| 本番用（primary） | GitHub の `production` environment の Secret、GitHub の外の保管場所（控え） | リポジトリ、コマンドの引数、チャット、issue、CI のログ |
| 予備（standby） | GitHub の外の保管場所だけ | GitHub（入れ替えるときまで登録しない）、ほかは同じ |

- GitHub の Secret は、登録したあとに中身を読み出せません。控えがないと、予備に切り替えるときや、別の環境で署名するときに困ります。
- `production` environment は、main ブランチだけが使えるようにします（[runbook.md の「最初の公開の準備」](runbook.md#最初の公開の準備)）。
- 秘密鍵をシェルで Base64 から戻したり、表示したりしないでください。rulestool は環境変数 `RULES_SIGNING_KEY` から読み、メモリの中だけで使います。
- 開発用の鍵（`scripts/build-local.sh --dev-sign` が作る `.local/dev-signing-key`）は、手元の確認用です。**`keys/trusted-public-keys.json` やアプリの Release ビルドに入れないでください。**
- `rulestool fixture` とテストで使う鍵は、RFC 8032 のテスト用の鍵（秘密鍵が公開されている）です。本番では絶対に信頼しません。

## 鍵を入れ替える（計画して行うとき）

例：本番用 A・予備 B から、本番用 B・予備 C に移る。

1. **アプリの準備**：[A, B] を埋め込んだアプリが公開されていて、利用者の多くがその版以降になっていることを確かめる。
2. **署名する鍵を B にする**：GitHub の Secret `RULES_SIGNING_KEY` を B の秘密鍵に替える。
3. **公開する**：「Actions」→「ルールの公開」を手動で実行する（またはルールの変更の公開を待つ）。以降の署名は B になります。
   - ルールが本番と同じなら、本番の（A の）署名をそのまま使うので、まだ B にはなりません。急がないならそれでかまいません。
4. **新しい予備 C を作る**：`rulestool keygen` で C を作り、保管する。
5. **アプリを更新する**：[B, C] を埋め込んだアプリを公開する。
6. **このリポジトリを更新する**：`keys/trusted-public-keys.json` を [B（primary）, C（standby）] にする。
   - A を外すと、本番に A の署名の manifest が残っていても、CI はそれを使わず、B で署名し直して新しい版として公開します。

注意：

- [A, B] だけを入れた古いアプリは、C の署名を検証できません。C で署名し始めると、その人たちはルールを更新できなくなります（今のルールのまま動き続けます）。C に切り替えるのは、古いアプリの利用者が十分に減ってからにします。
- `min_app_build` では、この問題を防げません（署名の検証が先なので、manifest を読む前に止まる）。

## 鍵が漏れたとき

例：本番用 A が漏れた（または漏れた疑いがある）。

### すぐに行うこと

1. **署名する鍵を予備 B に替える**：GitHub の Secret `RULES_SIGNING_KEY` を B の秘密鍵にする。
2. **A を信頼の一覧から外す**：`keys/trusted-public-keys.json` から A を消す PR を作り、マージする。
   - `keys/` の変更で `publish.yml` が動きます。本番の A の署名はもう検証に使わないので、CI は B で署名し直し、新しい版として公開します。
   - 動かなかったとき（配信するものに関係しない変更と判定されたときなど）は、「ルールの公開」を手動で実行します。
3. **公開できたかを確かめる**：
   ```bash
   swift run -c release rulestool verify --base-url https://<配信ホスト>/
   ```
   「署名：OK（鍵 standby）」のように、B で検証できることを確かめます（`id` は `keys/trusted-public-keys.json` の名前）。
4. **ほかに漏れたものがないかを調べる**：
   - GitHub の Actions の実行の履歴に、身に覚えのない実行がないか。
   - Cloudflare の管理画面の「Deployments」に、身に覚えのない公開がないか（あれば[前の版に戻す](runbook.md#前の版に戻す)）。
   - CI が漏れの原因かもしれないときは、`CLOUDFLARE_API_TOKEN` も作り直す。

### そのあとに行うこと

5. 新しい予備 C を作って保管し、[B, C] を埋め込んだアプリの更新を公開する。A を外したアプリが広まるまで、A は古いアプリで信頼されたままです。
6. `keys/trusted-public-keys.json` を [B, C] にする。

### 漏れたときの影響の範囲

- 署名だけでは、偽の manifest を利用者に届けられません。アプリは、埋め込んだ配信ホストから HTTPS でだけ取得するので、偽物を届けるには、配信（Cloudflare のアカウントや API トークン）も乗っ取る必要があります。
- 偽の manifest が届いた場合でも、コンテンツブロッカーのルールでできるのは、読み込みを止める、要素を隠す、ルールを打ち消すといったことで、ページの中身を読んだり送ったりはできません。起こりうるのは「サイトが表示されなくなる」「ブロックが効かなくなる」といった影響です。

### 2 本とも漏れた・失ったとき

新しい鍵を 2 本作り、それを埋め込んだアプリの更新を公開するしかありません。古いアプリは、新しい鍵の署名を検証できないので、ルールの更新が止まります（今のルールのまま動き続けます）。

## 巻き戻しと鍵

`wrangler rollback` や GitHub Release からの公開し直しで古い版に戻すと、manifest と署名も、その版を公開したときのものに戻ります。

- 戻す先の版を署名した鍵が、アプリにまだ埋め込まれていれば、問題ありません。
- 鍵を入れ替えて古い鍵をアプリから外したあとは、古い鍵で署名した版に戻すと、新しいアプリはそれを受け入れません（今のルールのまま）。その場合は、戻したい内容を main に戻し（revert）、今の鍵で署名し直して、新しい版として公開します。
- 漏れた鍵で署名した版には戻さないでください。
- どの鍵で署名されているかは、`rulestool verify` の「署名：OK（鍵 …）」で確かめられます。GitHub Release の一式なら、取得して展開してから `rulestool verify --dir <展開先>` を実行します。
