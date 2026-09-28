#if canImport(WebKit)
import Foundation
import WebKit

/// macOS の WebKit（WKContentRuleListStore）で、実際にルールをコンパイルして確かめる。
///
/// 注意：macOS の WebKit は iOS 17 の WebKit より新しい。ここで通っても iOS 17 で読めるとは限らないので、
/// 先に RuleListLint で iOS 17 で使えない書き方を止めておく。
/// WebKit の完了通知はメインスレッドに届くので、メインアクターで呼ぶ（コマンドラインでは、非同期の main が
/// メインの実行ループを回し続ける）。
@MainActor
public enum CompileChecker {
    /// コンパイルにかかった秒数を返す。失敗すれば WebKit のエラーを添えて投げる。
    public static func compile(_ json: Data, identifier: String = "rulestool-check") async throws -> Double {
        guard let text = String(data: json, encoding: .utf8) else {
            throw RulesError("UTF-8 のテキストではありません")
        }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "rulestool-wkstore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        guard let store = WKContentRuleListStore(url: directory) else {
            throw RulesError("WKContentRuleListStore を作れません")
        }
        let clock = ContinuousClock()
        let start = clock.now
        let list: WKContentRuleList?
        do {
            list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: text)
        } catch let error as NSError {
            throw RulesError("WebKit でコンパイルできません（\(error.domain) \(error.code)：\(error.localizedDescription)）")
        }
        let elapsed = clock.now - start
        guard list != nil else {
            throw RulesError("WebKit でコンパイルできません（結果が空）")
        }
        let components = elapsed.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
#endif
