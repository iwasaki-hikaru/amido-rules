import Foundation
import Testing
@testable import RulesKit

@Suite("変換後のリストの検査（iOS 17 の WebKit に合わせる）")
struct RuleListLintTests {
    func lint(_ json: String, forbidExceptions: Bool = false, maxIssues: Int = 200) -> LintReport {
        RuleListLint.lint(Data(json.utf8), forbidExceptions: forbidExceptions, maxIssues: maxIssues)
    }

    func rule(trigger: String = #""url-filter":".*""#, action: String = #""type":"block""#) -> String {
        "[{\"trigger\":{\(trigger)},\"action\":{\(action)}}]"
    }

    func issues(trigger: String = #""url-filter":".*""#, action: String = #""type":"block""#, forbidExceptions: Bool = false) -> [String] {
        lint(rule(trigger: trigger, action: action), forbidExceptions: forbidExceptions).issues
    }

    @Test("変換器が出す形のルールは通る")
    func validRules() {
        let json = """
        [
          {"trigger":{"url-filter":"^https?://ads\\\\.example\\\\.com/"},"action":{"type":"block"}},
          {"trigger":{"url-filter":".*","if-domain":["*example.org","example.net"]},"action":{"type":"css-display-none","selector":".ad, #banner"}},
          {"trigger":{"url-filter":".*","if-domain":["*example.com"]},"action":{"type":"ignore-previous-rules"}},
          {"trigger":{"url-filter":"\\\\/addyn\\\\|.*;adtech;","resource-type":["script","image","raw","fetch","websocket","ping","other","popup","media","font","style-sheet","document","svg-document"],"load-type":["third-party"],"unless-domain":["*example.jp"]},"action":{"type":"block"}},
          {"trigger":{"url-filter":"tracker","load-context":["child-frame"],"url-filter-is-case-sensitive":true},"action":{"type":"block-cookies"}},
          {"trigger":{"url-filter":"^http://","if-top-url":["^https?://example\\\\.com/"]},"action":{"type":"make-https"}},
          {"trigger":{"url-filter":"a[|{]b"},"action":{"type":"block"}}
        ]
        """
        let report = lint(json)
        #expect(report.isValid, "\(report.issues)")
        #expect(report.ruleCount == 7)
    }

    @Test("リスト全体の形", arguments: [
        ("{}", "最上位が配列ではありません"),
        ("[]", "空の配列"),
        ("not json", "JSON として読めません"),
        ("[1]", "オブジェクトではありません"),
        (#"[{"action":{"type":"block"}}]"#, "trigger がない"),
        (#"[{"trigger":{"url-filter":".*"}}]"#, "action がない"),
        (#"[{"trigger":{"url-filter":".*"},"action":{"type":"block"},"extra":1}]"#, "知らないキー「extra」"),
    ])
    func listShape(json: String, fragment: String) {
        let report = lint(json)
        #expect(!report.isValid)
        #expect(report.issues.contains { $0.contains(fragment) }, "\(report.issues)")
    }

    @Test("url-filter は空でない文字列", arguments: [#""url-filter":"""#, #""url-filter":1"#, #""if-domain":["*a.com"]"#])
    func urlFilterRequired(trigger: String) {
        #expect(issues(trigger: trigger).contains { $0.contains("url-filter がないか、空です") })
    }

    @Test(
        "url-filter の正規表現（WebKit の URLFilterParser が受け付けるものだけ）",
        arguments: [
            ("a|b", "「|」"),
            ("(a|b)", "「|」"),
            ("a{2}", "「{」"),
            ("a{1,3}", "「{」"),
            (#"a\db"#, #"「\d」"#),
            (#"a\wb"#, #"「\w」"#),
            (#"a\sb"#, #"「\s」"#),
            (#"a\bb"#, #"「\b」"#),
            (#"a\Db"#, #"「\D」"#),
            (#"a\Wb"#, #"「\W」"#),
            (#"a\Sb"#, #"「\S」"#),
            (#"a\Bb"#, #"「\B」"#),
            (#"[\d]"#, #"「\d」"#),
            ("例え", "ASCII 以外"),
            ("abc\\", "末尾が「\\」"),
            ("[]|]x", "「|」"),
        ]
    )
    func urlFilterRejects(pattern: String, fragment: String) {
        let problem = RuleListLint.urlFilterProblem(pattern)
        #expect(problem?.contains(fragment) == true, "\(pattern): \(problem ?? "nil")")
    }

    @Test(
        "エスケープしたもの・[…] の中の | と { は通る",
        arguments: [#"a\|b"#, #"a\{2"#, "a[|]b", "a[{]", #"a\\db"#, #"a\\\\"#, #"^https?://[^/]+\.example\.com/"#, ".*"]
    )
    func urlFilterAccepts(pattern: String) {
        #expect(RuleListLint.urlFilterProblem(pattern) == nil, "\(pattern)")
    }

    @Test("if-top-url の値にも同じ検査をする")
    func topURLPatterns() {
        #expect(issues(trigger: #""url-filter":".*","if-top-url":["a|b"]"#).contains { $0.contains("if-top-url") && $0.contains("「|」") })
        #expect(issues(trigger: #""url-filter":".*","unless-top-url":[]"#).contains { $0.contains("空でない配列") })
    }

    @Test(
        "条件のキーは 1 つだけ",
        arguments: [
            #""url-filter":".*","if-domain":["*a.com"],"unless-domain":["*b.com"]"#,
            #""url-filter":".*","if-domain":["*a.com"],"if-top-url":["^https://a"]"#,
            #""url-filter":".*","unless-domain":["*a.com"],"unless-top-url":["^https://a"]"#,
        ]
    )
    func singleCondition(trigger: String) {
        #expect(issues(trigger: trigger).contains { $0.contains("条件のキーが 2 つ") })
    }

    @Test("Safari 26 からのキーは使えない", arguments: ["if-frame-url", "unless-frame-url", "request-method", "frame-url-filter-is-case-sensitive"])
    func safari26Keys(key: String) {
        let value = key == "request-method" ? #""post""# : (key.hasSuffix("sensitive") ? "true" : #"["^https://a"]"#)
        let found = issues(trigger: "\"url-filter\":\".*\",\"\(key)\":\(value)")
        #expect(found.contains { $0.contains("「\(key)」は Safari 26 から") }, "\(found)")
    }

    @Test("知らない trigger のキーは使えない（古い WebKit は黙って無視し、広く当たりすぎる）")
    func unknownTriggerKey() {
        #expect(issues(trigger: #""url-filter":".*","if-domains":["*a.com"]"#).contains { $0.contains("知らないキー「if-domains」") })
    }

    @Test("resource-type に top-document / child-document は使えない", arguments: ["top-document", "child-document"])
    func safari26ResourceTypes(type: String) {
        #expect(issues(trigger: "\"url-filter\":\".*\",\"resource-type\":[\"\(type)\"]").contains { $0.contains("「\(type)」は Safari 26 から") })
    }

    @Test("resource-type・load-type・load-context の値")
    func listValues() {
        #expect(issues(trigger: #""url-filter":".*","resource-type":["bogus"]"#).contains { $0.contains("「bogus」は使えません") })
        #expect(issues(trigger: #""url-filter":".*","resource-type":[]"#).contains { $0.contains("空でない配列") })
        #expect(issues(trigger: #""url-filter":".*","load-type":["first"]"#).contains { $0.contains("「first」は使えません") })
        #expect(issues(trigger: #""url-filter":".*","load-context":["frame"]"#).contains { $0.contains("「frame」は使えません") })
        #expect(issues(trigger: #""url-filter":".*","url-filter-is-case-sensitive":"yes""#).contains { $0.contains("true か false") })
    }

    @Test(
        "action.type は iOS 17 で使えるものだけ",
        arguments: ["ignore-following-rules", "redirect", "modify-headers", "notify", "Block"]
    )
    func actionTypes(type: String) {
        #expect(issues(action: "\"type\":\"\(type)\"").contains { $0.contains("action.type「\(type)」") })
    }

    @Test("action.type がない・知らない action のキー")
    func actionShape() {
        #expect(issues(action: #""selector":".a""#).contains { $0.contains("action.type がありません") })
        #expect(issues(action: #""type":"block","redirect":{}"#).contains { $0.contains("知らないキー「redirect」") })
    }

    @Test("css-display-none には空でない selector が要る", arguments: [#""type":"css-display-none""#, #""type":"css-display-none","selector":"""#, #""type":"css-display-none","selector":"  ""#])
    func selectorRequired(action: String) {
        #expect(issues(action: action).contains { $0.contains("selector がないか、空です") })
    }

    @Test(
        "if-domain / unless-domain の値",
        arguments: [
            (#"["*Example.com"]"#, "大文字"),
            (#"["例え.jp"]"#, "ASCII 以外"),
            (#"[""]"#, "空です"),
            (#"["*"]"#, "空です"),
            (#"[1]"#, "文字列ではありません"),
            ("[]", "空でない配列"),
            (#""a.com""#, "空でない配列"),
        ]
    )
    func domains(value: String, fragment: String) {
        for key in ["if-domain", "unless-domain"] {
            let found = issues(trigger: "\"url-filter\":\".*\",\"\(key)\":\(value)")
            #expect(found.contains { $0.contains(fragment) && $0.contains(key) }, "\(key): \(found)")
        }
    }

    @Test("拡張の中で 2 番目以降のカテゴリには、例外ルールを入れられない")
    func exceptionScope() {
        let json = rule(trigger: #""url-filter":".*","if-domain":["*example.com"]"#, action: #""type":"ignore-previous-rules""#)
        #expect(lint(json, forbidExceptions: false).isValid)
        let report = lint(json, forbidExceptions: true)
        #expect(!report.isValid)
        #expect(report.issues.first?.contains("2 番目以降のカテゴリ") == true)
        #expect(report.issues.first?.hasPrefix("rules[0]:") == true)
    }

    @Test("問題はルールの番号（0 始まり）で示す")
    func indexInMessages() {
        let json = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},{"trigger":{"url-filter":"a|b"},"action":{"type":"block"}}]"#
        let report = lint(json)
        #expect(report.issues.count == 1)
        #expect(report.issues.first?.hasPrefix("rules[1]:") == true)
    }

    @Test("問題が多いときは先頭だけを持ち、総数を数える")
    func truncatesIssues() {
        let bad = #"{"trigger":{"url-filter":"a|b"},"action":{"type":"block"}}"#
        let json = "[" + Array(repeating: bad, count: 5).joined(separator: ",") + "]"
        let report = lint(json, maxIssues: 2)
        #expect(report.issues.count == 2)
        #expect(report.issueCount == 5)
        #expect(report.ruleCount == 5)
    }

    @Test("ダミールールと許可サイトのルールの見本は通る")
    func constantsPass() {
        #expect(lint("[\(RuleConstants.dummyRuleJSON)]").isValid)
        #expect(lint("[\(RuleConstants.sampleAllowlistRuleJSON)]").isValid)
    }
}

@Suite("リストをつなぐ")
struct RuleListJoinTests {
    @Test("配列の中身をバイト単位でつなぎ、末尾にルールを足す")
    func joins() throws {
        let joined = try RuleListJoin.join(
            [Data(" [ {\"a\":1} , {\"b\":2} ]\n".utf8), Data("[{\"c\":3}]".utf8)],
            appending: [#"{"d":4}"#]
        )
        #expect(String(decoding: joined, as: UTF8.self) == #"[{"a":1} , {"b":2},{"c":3},{"d":4}]"#)
        let parsed = try JSONSerialization.jsonObject(with: joined) as? [[String: Int]]
        #expect(parsed?.count == 4)
    }

    @Test("空の配列は飛ばす")
    func skipsEmpty() throws {
        let joined = try RuleListJoin.join([Data("[]".utf8), Data("[ ]".utf8)], appending: [RuleConstants.dummyRuleJSON])
        #expect(String(decoding: joined, as: UTF8.self) == "[\(RuleConstants.dummyRuleJSON)]")
    }

    @Test("配列でなければエラー")
    func rejectsNonArray() {
        #expect(throws: RulesError.self) { try RuleListJoin.join([Data("{}".utf8)]) }
        #expect(throws: RulesError.self) { try RuleListJoin.join([Data("[".utf8)]) }
    }
}
