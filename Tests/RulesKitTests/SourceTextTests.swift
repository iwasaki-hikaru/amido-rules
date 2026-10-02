import Foundation
import Testing
@testable import RulesKit

@Suite("フィルタリストのテキスト")
struct SourceTextTests {
    @Test("[Adblock …] の行を取り除く（先頭でも途中でも）")
    func stripsHeaders() {
        let text = "[Adblock Plus 2.0]\n! Title: X\nrule1\n[Adblock Plus 3.1]\nrule2"
        let result = SourceText.stripAdblockHeaders(text)
        #expect(result.text == "! Title: X\nrule1\nrule2\n")
        #expect(result.removedLines == 2)
    }

    @Test("見出しの判定は ^\\[Adblock.*\\]$ と同じ", arguments: [
        ("[Adblock Plus 2.0]", true),
        ("[Adblock]", true),
        ("[AdBlock Plus 2.0]", false),
        ("[Adblock Plus 2.0] extra", false),
        (" [Adblock Plus 2.0]", false),
        ("||example.com^", false),
    ])
    func headerPattern(line: String, expected: Bool) {
        #expect(SourceText.isAdblockHeader(line) == expected)
    }

    @Test("CRLF と CR の改行を LF にそろえる")
    func normalizesLineEndings() {
        let result = SourceText.stripAdblockHeaders("[Adblock Plus 2.0]\r\nrule1\r\nrule2\rrule3\r\n\r\n")
        #expect(result.text == "rule1\nrule2\nrule3\n")
        #expect(result.removedLines == 1)
    }

    static let sectioned = """
    ! Title: Example
    ! *** easylist:example/general.txt ***
    ||general.example^
    ! *** easylist:example/specific_cname_a.txt ***
    ! a のコメント（.jp を含んでも残さない）
    ||a1.example.com^
    ||a2.example.jp^

    ||a3.example.co.jp^$third-party
    ! *** easylist:example/specific_cname_b.txt ***
    ||b1.example.net^
    ! *** easylist:example/specific.txt ***
    ||specific.example^
    @@||allow.example.jp^
    ! *** easylist:example/specific_cname_c.txt ***
    ||c1.example.org^
    """

    @Test("節を除く：見出しの行から、次の見出しの行の前まで。.jp を含むルールの行は残す")
    func excludesSections() {
        let result = SourceText.excludeSections(
            Self.sectioned, headingPrefix: "! *** easylist:example/specific_cname_", keepLinesContaining: ".jp"
        )
        #expect(result.text == """
        ! Title: Example
        ! *** easylist:example/general.txt ***
        ||general.example^
        ||a2.example.jp^
        ||a3.example.co.jp^$third-party
        ! *** easylist:example/specific.txt ***
        ||specific.example^
        @@||allow.example.jp^

        """)
        #expect(result.excludedSections == [
            "! *** easylist:example/specific_cname_a.txt ***",
            "! *** easylist:example/specific_cname_b.txt ***",
            "! *** easylist:example/specific_cname_c.txt ***",
        ])
        #expect(result.removedRuleLines == 3)
        #expect(result.keptRuleLines == 2)
    }

    @Test("節を除く：残す文字列がなければ、節の行はすべて除く")
    func excludesSectionsWithoutKeep() {
        let result = SourceText.excludeSections(Self.sectioned, headingPrefix: "! *** easylist:example/specific_cname_")
        #expect(SourceText.countRuleLines(result.text) == 3)
        #expect(result.removedRuleLines == 5)
        #expect(result.keptRuleLines == 0)
    }

    @Test("節を除く：当たる見出しがなければ、何も変えない（改行はそろえる）")
    func excludesNothingWhenNoHeading() {
        let result = SourceText.excludeSections("rule1\r\n! *** easylist:x.txt ***\r\nrule2\r\n", headingPrefix: "! *** easylist:y")
        #expect(result.text == "rule1\n! *** easylist:x.txt ***\nrule2\n")
        #expect(result.excludedSections.isEmpty)
        #expect(result.removedRuleLines == 0)
    }

    @Test("中身がなければ空文字列")
    func emptyText() {
        #expect(SourceText.stripAdblockHeaders("[Adblock Plus 2.0]\n").text == "")
    }

    @Test("先頭の BOM を取り除いて読む")
    func stripsBOM() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("[Adblock Plus 2.0]\nrule\n".utf8)
        let text = try FileIO.decodeText(data, displayName: "test")
        #expect(SourceText.stripAdblockHeaders(text).text == "rule\n")
    }

    @Test("UTF-8 でなければエラー")
    func rejectsNonUTF8() {
        #expect(throws: RulesError.self) { try FileIO.decodeText(Data([0xFF, 0xFE, 0x00, 0xD8]), displayName: "test") }
    }

    @Test("ルールの行だけを数える")
    func countsRuleLines() {
        let text = "! comment\n\nrule1\n   \n[Adblock Plus 2.0]\n##.ad\n  example.com##.x  \n"
        #expect(SourceText.countRuleLines(text) == 3)
    }

    @Test("先頭のコメントから、ライセンスとホームページの行を拾う（Licence の綴りも）")
    func headerLines() {
        let text = """
        [Adblock Plus 2.0]
        ! Version: 202609281516
        ! Title: EasyList
        ! Homepage: https://easylist.to/
        ! Licence: https://easylist.to/pages/licence.html
        ! Something else: x
        ! License: CC BY-SA
        ||ads.example^
        ! Homepage: https://late.example/
        """
        #expect(SourceText.headerLines(text) == [
            "! Version: 202609281516",
            "! Title: EasyList",
            "! Homepage: https://easylist.to/",
            "! Licence: https://easylist.to/pages/licence.html",
            "! License: CC BY-SA",
        ])
    }
}

@Suite("自作ルールの根拠の検査")
struct CustomRuleLintTests {
    let file = "custom/basic.txt"

    func lint(_ text: String) -> [String] {
        SourceText.lintCustomRules(text, fileName: file)
    }

    @Test("根拠のすぐ下のルールは通る")
    func passesWithEvidence() {
        #expect(lint("! 根拠: https://example.com/a (2026-01-02)\nexample.com##.ad\n").isEmpty)
    }

    @Test("根拠とルールの間に、ほかのコメントがあってもよい")
    func passesWithOtherComments() {
        let text = "! 補足：広告の枠\n! 根拠: https://example.com/a (2026-01-02)\n! 確認した環境：iOS 17\nexample.com##.ad"
        #expect(lint(text).isEmpty)
    }

    @Test("ルールごとに根拠があれば、いくつでも通る。http:// も可")
    func passesMultipleRules() {
        let text = """
        ! 根拠: https://example.com/a (2026-01-02)
        example.com##.ad

        ! 根拠: http://example.org/b?x=1#y (2024-02-29)
        ||ads.example.org^
        """
        #expect(lint(text).isEmpty)
    }

    @Test("リポジトリの custom/*.txt は通る", arguments: ["basic", "annoyance", "scam"])
    func repositoryFilesPass(name: String) throws {
        let url = TestEnvironment.rulesRoot.appending(path: "custom/\(name).txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(SourceText.lintCustomRules(text, fileName: "custom/\(name).txt").isEmpty)
    }

    @Test("根拠のないルールは、ファイルと行を示して失敗する")
    func failsWithoutEvidence() {
        let problems = lint("! ただのコメント\nexample.com##.ad\n")
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("custom/basic.txt:2:") == true)
        #expect(problems.first?.contains("根拠") == true)
    }

    @Test("空行をはさむと、根拠はつながらない")
    func blankLineBreaksEvidence() {
        let problems = lint("! 根拠: https://example.com/a (2026-01-02)\n\nexample.com##.ad\n")
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("custom/basic.txt:3:") == true)
    }

    @Test("空白だけの行も空行として扱う")
    func whitespaceLineBreaksEvidence() {
        #expect(lint("! 根拠: https://example.com/a (2026-01-02)\n   \nexample.com##.ad\n").count == 1)
    }

    @Test("1 つの根拠で 2 つのルールは通らない（間にルールがある）")
    func ruleBetweenBreaksEvidence() {
        let problems = lint("! 根拠: https://example.com/a (2026-01-02)\nexample.com##.ad\nexample.com##.banner\n")
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("custom/basic.txt:3:") == true)
    }

    @Test("「!#」「!+」で始まる行は使えない", arguments: ["!#if (adguard_app_ios)", "!#include other.txt", "!+ NOT_OPTIMIZED", "  !#endif"])
    func rejectsDirectivesAndHints(line: String) {
        let problems = lint("\(line)\n")
        #expect(problems.count == 1)
        #expect(problems.first?.hasPrefix("custom/basic.txt:1:") == true)
        #expect(problems.first?.contains("「!#」「!+」") == true)
    }

    @Test(
        "根拠の書き間違いは報告する",
        arguments: [
            "! 根拠： https://example.com/a (2026-01-02)",
            "! 根拠: https://example.com/a (2026-13-01)",
            "! 根拠: https://example.com/a (2026-02-30)",
            "! 根拠: https://example.com/a (2026-1-02)",
            "! 根拠: https://example.com/a 2026-01-02",
            "! 根拠: ftp://example.com/a (2026-01-02)",
            "! 根拠: https://example.com/a",
            "! 根拠: (2026-01-02)",
            "! 根拠: https://example.com/a (2026-01-02) 追記",
        ]
    )
    func malformedEvidence(line: String) {
        let problems = lint("\(line)\nexample.com##.ad\n")
        // 書き間違いの報告と、根拠のないルールの報告の 2 つ
        #expect(problems.count == 2, "\(problems)")
        #expect(problems.first?.hasPrefix("custom/basic.txt:1:") == true)
        #expect(problems.first?.contains("根拠の書き方が違います") == true)
    }

    @Test("「根拠」という言葉を含むだけの説明のコメントは、根拠の行として扱わない")
    func explanatoryCommentsAreIgnored() {
        let text = "! 決まり：各ルールのすぐ上に、根拠を書く\n!   根拠のないルールがあると失敗する\n! ! 根拠: https://example.jp/ (2026-10-01)\n"
        #expect(lint(text).isEmpty)
    }
}
