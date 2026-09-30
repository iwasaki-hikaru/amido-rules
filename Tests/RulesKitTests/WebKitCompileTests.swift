#if canImport(WebKit)
import Foundation
import Testing
import WebKit
@testable import RulesKit

/// macOS の WebKit で、実際にコンパイルして確かめる。
@Suite("WebKit での実コンパイル（macOS）", .serialized)
@MainActor
struct WebKitCompileTests {
    @Test("ダミールールはコンパイルできる")
    func dummyCompiles() async throws {
        let seconds = try await CompileChecker.compile(Data("[\(RuleConstants.dummyRuleJSON)]".utf8))
        #expect(seconds >= 0)
    }

    @Test("カテゴリをつなぎ、許可サイトのルールを足したリストはコンパイルできる")
    func generatedListCompiles() async throws {
        let joined = try RuleListJoin.join(
            [Data(SampleFixture.basicRulesJSON.utf8), Data(SampleLists.annoyance.utf8)],
            appending: [RuleConstants.sampleAllowlistRuleJSON]
        )
        #expect(RuleListLint.lint(joined, forbidExceptions: false).isValid)
        _ = try await CompileChecker.compile(joined)
    }

    @Test("トップの文書に限ったルール（DocumentRuleScope の出力）はコンパイルできる")
    func topFrameDocumentRuleCompiles() async throws {
        let converted = #"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?html-load\\.com[/:]","resource-type":["document"]},"action":{"type":"block"}},{"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*example.com"]},"action":{"type":"block"}}]"#
        let scoped = try DocumentRuleScope.restrictToTopFrame(Data(converted.utf8))
        #expect(scoped.changed == 2)
        #expect(RuleListLint.lint(scoped.data, forbidExceptions: false).isValid)
        _ = try await CompileChecker.compile(scoped.data)
    }

    @Test("空配列はコンパイルに失敗する（WKErrorDomain 6）")
    func emptyArrayFails() async {
        do {
            _ = try await CompileChecker.compile(Data("[]".utf8))
            Issue.record("空配列がコンパイルできてしまった")
        } catch {
            #expect(error.localizedDescription.contains("\(WKErrorDomain) 6"))
        }
    }

    /// 検査（RuleListLint）の判定と、WebKit が実際に受け付けるかが一致していることを確かめる。
    @Test(
        "url-filter の検査は、WebKit の判定と一致する",
        arguments: [
            ("a|b", false),
            (#"a\|b"#, true),
            ("a[|]b", true),
            ("a{2}", false),
            (#"a\{2"#, true),
            ("a[{]", true),
            (#"a\db"#, false),
            (#"a\\db"#, true),
            (#"a\bb"#, false),
            (#"a\sb"#, false),
            ("aé", false),
        ]
    )
    func lintAgreesWithWebKit(pattern: String, accepted: Bool) async throws {
        #expect((RuleListLint.urlFilterProblem(pattern) == nil) == accepted)
        let rule: [String: Any] = ["trigger": ["url-filter": pattern], "action": ["type": "block"]]
        let data = try JSONSerialization.data(withJSONObject: [rule])
        var compiled = true
        do {
            _ = try await CompileChecker.compile(data)
        } catch {
            compiled = false
        }
        #expect(compiled == accepted, "\(pattern)")
    }
}
#endif
