#!/bin/bash
# AdGuard SafariConverterLib の ConverterTool を、固定したタグとコミットからビルドする。
#
# - 変換器（GPLv3）は別のプログラムとして呼び出すだけで、このリポジトリのコードにはリンクしない。
# - ビルドのとき SwiftPM が依存パッケージを 3 つ取得する（PunycodeSwift・swift-argument-parser・swift-psl）。
#   --force-resolved-versions で、変換器の Package.resolved に書かれた版に固定する。
# - 出力：.tools/SafariConverterLib/.build/release/ConverterTool
set -euo pipefail
cd "$(dirname "$0")/.."

TAG=v4.3.0
COMMIT=7a2e93f0afa70479cc59985f332025236c3f0c39
DIR=.tools/SafariConverterLib
BIN="$DIR/.build/release/ConverterTool"

if [ ! -d "$DIR/.git" ]; then
  git clone --quiet --depth 1 --branch "$TAG" https://github.com/AdguardTeam/SafariConverterLib.git "$DIR"
fi
actual=$(git -C "$DIR" rev-parse HEAD)
if [ "$actual" != "$COMMIT" ]; then
  echo "✘ $TAG のコミットが想定と違います（想定：${COMMIT}、実際：${actual}）。タグが動かされた可能性があります。" >&2
  exit 1
fi

if [ ! -x "$BIN" ]; then
  (cd "$DIR" && swift build -c release --product ConverterTool --force-resolved-versions >&2)
fi
echo "$BIN"
