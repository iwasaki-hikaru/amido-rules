import Foundation
import Testing
@testable import RulesKit

@Suite("document の block ルールを、トップの文書に限る")
struct DocumentRuleScopeTests {
    func triggers(_ data: Data) throws -> [[String: Any]] {
        let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        return try rules.map { try #require($0["trigger"] as? [String: Any]) }
    }

    @Test("resource-type が document だけの block ルールに、load-context: top-frame を足す")
    func addsTopFrame() throws {
        // EasyList の ||html-load.com^$document,popup を変換器が変換した形
        let json = #"[{"trigger":{"url-filter":"^[^:]+://+([^:/]+\\.)?html-load\\.com[/:]","resource-type":["document"]},"action":{"type":"block"}}]"#
        let result = try DocumentRuleScope.restrictToTopFrame(Data(json.utf8))
        #expect(result.changed == 1)
        let trigger = try #require(try triggers(result.data).first)
        #expect(trigger["load-context"] as? [String] == ["top-frame"])
        #expect(trigger["resource-type"] as? [String] == ["document"])
        #expect(trigger["url-filter"] as? String == #"^[^:]+://+([^:/]+\.)?html-load\.com[/:]"#)
        #expect(RuleListLint.lint(result.data, forbidExceptions: false).isValid)
    }

    @Test("ほかのルールは変えない", arguments: [
        // iframe を止めるルール（$subdocument）：変換器が child-frame を付ける
        #"{"trigger":{"url-filter":"&subaffid=%","load-type":["third-party"],"load-context":["child-frame"]},"action":{"type":"block"}}"#,
        // $popup,subdocument：document に child-frame が付いた形
        #"{"trigger":{"url-filter":"\/earn\.php\?z=","resource-type":["document"],"load-context":["child-frame"]},"action":{"type":"block"}}"#,
        // $~subdocument：変換器がすでに top-frame を付けた形
        #"{"trigger":{"url-filter":"ads","resource-type":["document"],"load-context":["top-frame"]},"action":{"type":"block"}}"#,
        // document とほかの種類の組み合わせ
        #"{"trigger":{"url-filter":"ads","resource-type":["document","script"]},"action":{"type":"block"}}"#,
        // 種類の指定なし
        #"{"trigger":{"url-filter":"^https?://ads\\.example\\.com/"},"action":{"type":"block"}}"#,
        // 例外（ページ全体の許可）と要素を隠すルール
        #"{"trigger":{"url-filter":".*","if-domain":["*example.com"],"resource-type":["document"]},"action":{"type":"ignore-previous-rules"}}"#,
        #"{"trigger":{"url-filter":".*","if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".ad"}}"#,
    ])
    func leavesOthers(rule: String) throws {
        let data = Data("[\(rule)]".utf8)
        let result = try DocumentRuleScope.restrictToTopFrame(data)
        #expect(result.changed == 0)
        #expect(result.data == data)
    }

    @Test("変えたルールだけに足し、並び順と件数は変えない")
    func keepsOrderAndCount() throws {
        let json = """
        [
          {"trigger":{"url-filter":"a","resource-type":["document"]},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*","if-domain":["*a.com"]},"action":{"type":"css-display-none","selector":".x"}},
          {"trigger":{"url-filter":".*","resource-type":["document"],"if-domain":["*b.com"]},"action":{"type":"block"}},
          {"trigger":{"url-filter":"c","resource-type":["document"]},"action":{"type":"ignore-previous-rules"}}
        ]
        """
        let result = try DocumentRuleScope.restrictToTopFrame(Data(json.utf8))
        #expect(result.changed == 2)
        let triggers = try triggers(result.data)
        #expect(triggers.count == 4)
        #expect(triggers.map { $0["url-filter"] as? String } == ["a", ".*", ".*", "c"])
        #expect(triggers.map { $0["load-context"] as? [String] } == [["top-frame"], nil, ["top-frame"], nil])
    }

    @Test("同じ入力からは、同じバイト列になる")
    func deterministic() throws {
        let json = #"[{"trigger":{"url-filter":"a","resource-type":["document"],"unless-domain":["*x.com","*y.com"]},"action":{"type":"block"}}]"#
        let first = try DocumentRuleScope.restrictToTopFrame(Data(json.utf8))
        let second = try DocumentRuleScope.restrictToTopFrame(Data(json.utf8))
        #expect(first.data == second.data)
        #expect(!String(decoding: first.data, as: UTF8.self).contains(#"\/"#))
    }

    @Test("ルールの配列として読めないものは、そのまま返す（形の問題は RuleListLint が報告する）")
    func passesThroughInvalid() throws {
        for text in ["not json", #"{"a":1}"#] {
            let data = Data(text.utf8)
            let result = try DocumentRuleScope.restrictToTopFrame(data)
            #expect(result.changed == 0)
            #expect(result.data == data)
        }
    }
}
