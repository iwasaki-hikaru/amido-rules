// iOS のシミュレーターの WebKit で、コンテンツブロッカーの JSON をコンパイルできるかを確かめる。
//
// iOS シミュレーター向けにビルドし、`xcrun simctl spawn` で動かす（.github/scripts/ios-webkit-check.sh）。
// 使い方：ios-webkit-check <file.json>...   成功したら 0、1 つでも失敗があれば 1 で終わる。
//
// macOS の WebKit（rulestool compile-check）で通っても、古い iOS の WebKit で読めない書き方がありうるので、
// 対応する最も古い iOS（17）と、その次（18）のシミュレーターで確かめる。
// 古い Xcode（Swift 5）でもビルドできる書き方にしている。
import Foundation
import WebKit

@MainActor
func compile(_ path: String) async -> Bool {
    let name = (path as NSString).lastPathComponent
    guard let json = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("✘ \(name)：読めません")
        return false
    }
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ios-webkit-check-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    guard let store = WKContentRuleListStore(url: directory) else {
        print("✘ \(name)：WKContentRuleListStore を作れません")
        return false
    }
    let started = Date()
    do {
        _ = try await store.compileContentRuleList(forIdentifier: "check", encodedContentRuleList: json)
        print(String(format: "✔ %@（%.1f 秒）", name, Date().timeIntervalSince(started)))
        return true
    } catch {
        let nsError = error as NSError
        print("✘ \(name)：\(nsError.domain) \(nsError.code) \(nsError.localizedDescription)")
        return false
    }
}

let paths = Array(CommandLine.arguments.dropFirst())
if paths.isEmpty {
    print("使い方：ios-webkit-check <file.json>...")
    exit(2)
}
Task { @MainActor in
    print("iOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    var allOK = true
    for path in paths {
        let ok = await compile(path)
        if !ok {
            allOK = false
        }
    }
    exit(allOK ? 0 : 1)
}
RunLoop.main.run()
