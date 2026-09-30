# セキュリティ

## 報告のしかた

このリポジトリ（ルール・変換と署名のツール・配信の設定）や、配信している `manifest.json`・署名に問題を見つけたときは、**公開の issue ではなく**、GitHub の「Security」タブ →「Report a vulnerability」（Private vulnerability reporting）から知らせてください。

- 例：署名の検証をすり抜けられる、CI から秘密情報を読み出せる、配信サイトに不正なページを置ける
- 広告が消えない・サイトの表示が崩れる、といったルールの誤りは、アプリの「報告」か、通常の issue でかまいません

## しくみ（概要）

- アプリは、`manifest.json` の Ed25519 の署名を、アプリに埋め込んだ公開鍵で検証してから、ルールを使います。署名の秘密鍵は GitHub の `production` environment の Secret だけにあり、このリポジトリには入っていません。
- ルールは Safari のコンテンツブロッカーの JSON（読み込みを止める・要素を隠す）です。ページの中身を読んだり、外に送ったりする働きはありません。
- 詳しくは [docs/signing.md](docs/signing.md) を見てください。
