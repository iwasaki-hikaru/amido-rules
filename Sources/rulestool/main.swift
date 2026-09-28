import Foundation

// rulestool の入口。コマンドは Commands.swift。
// 非同期の main はメインの実行ループを回し続けるので、WebKit の完了通知（メインスレッドに届く）も受け取れる。
let status = await CommandLineTool.main(Array(CommandLine.arguments.dropFirst()))
exit(status)
