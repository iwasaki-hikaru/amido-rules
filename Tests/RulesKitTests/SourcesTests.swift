import Foundation
import Testing
@testable import RulesKit

@Suite("sources.yml のパーサー（YAML の一部）")
struct SourcesYAMLTests {
    @Test("リポジトリの sources.yml を読める")
    func parsesRepositoryFile() throws {
        let entries = try SourcesFile.load(
            from: TestEnvironment.rulesRoot.appending(path: "sources.yml"),
            denylist: TestEnvironment.repositoryDenylist
        )
        #expect(entries.count == 5)
        let easyList = try #require(entries.first)
        #expect(easyList.name == "EasyList")
        #expect(easyList.slug == "easylist")
        #expect(easyList.origin == .url(URL(string: "https://easylist.to/easylist/easylist.txt")!))
        #expect(easyList.category == .basic)
        #expect(easyList.enabled)
        #expect(easyList.license == "CC-BY-SA-3.0")
        #expect(easyList.attribution == "The EasyList authors (https://easylist.to/)")
        #expect(entries.filter(\.isCustom).map(\.category) == [.basic, .annoyance, .scam])
        #expect(entries.last?.enabled == false)
    }

    @Test("値の書き方：引用符、コメント、true / false、URL の #")
    func scalarsAndComments() throws {
        let text = """
        # 先頭のコメント
        sources:   # 行末のコメント
          - name: "A # これはコメントではない"   # これはコメント
            url: https://example.com/list.txt#frag
            license: 'It''s MIT'
            attribution: "quote \\" and backslash \\\\ and \\/"
            category: basic
            enabled: false

          # 項目の間のコメント
          - name: B
            path: custom/basic.txt
            license: "true"
            attribution: y
            category: annoyance
            enabled: true
        """
        let items = try SourcesYAML.parse(text)
        #expect(items.count == 2)
        #expect(items[0].line == 3)
        #expect(items[0].fields["name"]?.value == .string("A # これはコメントではない"))
        #expect(items[0].fields["url"]?.value == .string("https://example.com/list.txt#frag"))
        #expect(items[0].fields["license"]?.value == .string("It's MIT"))
        #expect(items[0].fields["attribution"]?.value == .string("quote \" and backslash \\ and /"))
        #expect(items[0].fields["enabled"]?.value == .bool(false))
        #expect(items[1].line == 11)
        #expect(items[1].fields["license"]?.value == .string("true"))
        #expect(items[1].fields["enabled"]?.value == .bool(true))
        #expect(items[1].fields["category"]?.line == 15)
    }

    @Test("CRLF の改行と、字下げ 0 のリストも読める")
    func crlfAndZeroIndent() throws {
        let text = "sources:\r\n- name: A\r\n  path: custom/a.txt\r\n"
        let items = try SourcesYAML.parse(text)
        #expect(items.count == 1)
        #expect(items[0].fields["path"]?.value == .string("custom/a.txt"))
    }

    @Test("sources: だけなら項目は 0 個")
    func emptyList() throws {
        #expect(try SourcesYAML.parse("sources:\n").isEmpty)
    }

    @Test(
        "対応しない書き方はエラーにする（行番号つき）",
        arguments: [
            ("sources:\n\t- name: x", "sources.yml:2:", "タブ"),
            ("- name: x", "sources.yml:1:", "先に「sources:」"),
            ("other:\n", "sources.yml:1:", "最上位に書けるのは"),
            ("sources: foo", "sources.yml:1:", "改行し"),
            ("sources: []", "sources.yml:1:", "対応していません"),
            ("sources:\nsources:\n", "sources.yml:2:", "2 回あります"),
            ("sources:\n  - name: a\n   url: b", "sources.yml:3:", "字下げが正しくありません"),
            ("sources:\n  - name: a\n - name: b", "sources.yml:3:", "字下げがそろっていません"),
            ("sources:\n  - name: a\n    name: b", "sources.yml:3:", "2 回あります"),
            ("sources:\n  - name:\n", "sources.yml:2:", "値がありません"),
            ("sources:\n  - name: a\n    nested:\n      x: y", "sources.yml:3:", "値がありません"),
            ("sources:\n  - name: [a, b]", "sources.yml:2:", "対応していません"),
            ("sources:\n  - name: {a: b}", "sources.yml:2:", "対応していません"),
            ("sources:\n  - name: |\n      text", "sources.yml:2:", "対応していません"),
            ("sources:\n  - name: \"abc", "sources.yml:2:", "閉じていません"),
            ("sources:\n  - name: \"a\" b", "sources.yml:2:", "余分な文字"),
            ("sources:\n  - name: \"\\x\"", "sources.yml:2:", "エスケープ"),
            ("sources:\n  - name: a: b", "sources.yml:2:", "「: 」"),
            ("sources:\n  - name:a", "sources.yml:2:", "空白を入れて"),
            ("sources:\n  -\n", "sources.yml:2:", "最初の「キー: 値」"),
            ("sources:\n  - - a", "sources.yml:2:", "入れ子"),
            ("sources:\n  key: value", "sources.yml:2:", "「- 」で始まる項目の中"),
            ("---\nsources:", "sources.yml:1:", "区切り"),
        ]
    )
    func rejectsUnsupportedSyntax(text: String, location: String, fragment: String) {
        do {
            _ = try SourcesYAML.parse(text)
            Issue.record("エラーにならなかった：\(text)")
        } catch let error as RulesError {
            #expect(error.message.contains(location), "\(error.message)")
            #expect(error.message.contains(fragment), "\(error.message)")
        } catch {
            Issue.record("想定外のエラー：\(error)")
        }
    }

    @Test("sources: がなければエラー")
    func missingRoot() {
        #expect(throws: RulesError.self) { try SourcesYAML.parse("# コメントだけ\n") }
    }
}

@Suite("sources.yml の項目の検査")
struct SourcesValidationTests {
    static func item(_ lines: [String]) -> String {
        "sources:\n" + lines.enumerated().map { index, line in (index == 0 ? "  - " : "    ") + line }.joined(separator: "\n") + "\n"
    }

    static let validLines = [
        "name: Test",
        "url: https://example.com/list.txt",
        "license: CC0-1.0",
        "attribution: Example",
        "category: basic",
        "enabled: true",
    ]

    func problems(_ lines: [String], denylist: Denylist = TestEnvironment.repositoryDenylist) -> String? {
        do {
            _ = try SourcesFile.parse(Self.item(lines), denylist: denylist)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @Test("正しい項目は通る")
    func valid() throws {
        let entries = try SourcesFile.parse(Self.item(Self.validLines), denylist: TestEnvironment.repositoryDenylist)
        #expect(entries.count == 1)
        #expect(entries[0].slug == "test")
        #expect(entries[0].isCustom == false)
    }

    @Test("url と path は、どちらか 1 つだけ")
    func urlXorPath() {
        let both = Self.validLines + ["path: custom/basic.txt"]
        #expect(problems(both)?.contains("どちらか 1 つだけ") == true)
        let neither = Self.validLines.filter { !$0.hasPrefix("url:") }
        #expect(problems(neither)?.contains("「url」か「path」のどちらか 1 つが必要") == true)
    }

    @Test("知らないカテゴリは使えない")
    func unknownCategory() {
        let lines = Self.validLines.map { $0.hasPrefix("category:") ? "category: ads" : $0 }
        #expect(problems(lines)?.contains("カテゴリ「ads」は使えません") == true)
    }

    @Test("license と attribution は必須", arguments: ["license", "attribution", "name", "category", "enabled"])
    func requiredFields(key: String) {
        let lines = Self.validLines.filter { !$0.hasPrefix("\(key):") }
        #expect(problems(lines)?.contains("「\(key)」がありません") == true)
    }

    @Test("空の license はエラー")
    func emptyLicense() {
        let lines = Self.validLines.map { $0.hasPrefix("license:") ? "license: \"  \"" : $0 }
        #expect(problems(lines)?.contains("「license」が空です") == true)
    }

    @Test(
        "denylist の文字列を含む URL は拒否する（大文字小文字は区別しない）",
        arguments: [
            "https://example.com/280blocker/list.txt",
            "https://280Blocker.example/list.txt",
            "https://raw.example.com/tofukko/filter.txt",
        ]
    )
    func denylistRejects(url: String) {
        let lines = Self.validLines.map { $0.hasPrefix("url:") ? "url: \(url)" : $0 }
        #expect(problems(lines)?.contains("config/denylist.json") == true)
    }

    @Test("denylist は path と、無効なソースにも効く")
    func denylistAppliesToPathAndDisabled() {
        var lines = Self.validLines.map { $0.hasPrefix("enabled:") ? "enabled: false" : $0 }
        lines = lines.map { $0.hasPrefix("url:") ? "url: https://example.com/280blocker.txt" : $0 }
        #expect(problems(lines)?.contains("config/denylist.json") == true)
        let pathLines = Self.validLines.map { $0.hasPrefix("url:") ? "path: custom/280blocker.txt" : $0 }
        #expect(problems(pathLines)?.contains("config/denylist.json") == true)
    }

    @Test("リポジトリの config/denylist.json を読める")
    func repositoryDenylist() throws {
        let config = try RulesConfig.load(from: TestEnvironment.rulesRoot.appending(path: "config"))
        #expect(config.denylist.match("https://example.com/280blocker_adblock.txt") == "280blocker")
        #expect(config.denylist.match("https://easylist.to/easylist/easylist.txt") == nil)
    }

    @Test("url は https だけ", arguments: ["http://example.com/list.txt", "ftp://example.com/list.txt", "example.com/list.txt"])
    func httpsOnly(url: String) {
        let lines = Self.validLines.map { $0.hasPrefix("url:") ? "url: \(url)" : $0 }
        #expect(problems(lines)?.contains("https://") == true)
    }

    @Test("path はリポジトリの中の相対パスだけ", arguments: ["/etc/hosts", "../outside.txt", "custom/../x.txt", "custom//x.txt"])
    func relativePathOnly(path: String) {
        let lines = Self.validLines.map { $0.hasPrefix("url:") ? "path: \(path)" : $0 }
        #expect(problems(lines)?.contains("相対パス") == true)
    }

    @Test("知らないキーはエラー（綴りの間違いを見つけるため）")
    func unknownKey() {
        #expect(problems(Self.validLines + ["licence: x"])?.contains("知らないキー「licence」") == true)
    }

    @Test("enabled は true / false だけ")
    func enabledMustBeBool() {
        let lines = Self.validLines.map { $0.hasPrefix("enabled:") ? "enabled: yes" : $0 }
        #expect(problems(lines)?.contains("true か false") == true)
    }

    @Test("文字列のキーに true を書くとエラー")
    func boolWhereStringExpected() {
        let lines = Self.validLines.map { $0.hasPrefix("license:") ? "license: true" : $0 }
        #expect(problems(lines)?.contains("文字列で書いて") == true)
    }

    @Test("名前が重なるとエラー。問題はまとめて報告する")
    func duplicateNamesAndAggregation() {
        let text = Self.item(Self.validLines) + Self.item(Self.validLines.map { $0.hasPrefix("category:") ? "category: nope" : $0 })
            .replacingOccurrences(of: "sources:\n", with: "")
        do {
            _ = try SourcesFile.parse(text, denylist: TestEnvironment.repositoryDenylist)
            Issue.record("エラーにならなかった")
        } catch {
            let message = error.localizedDescription
            #expect(message.contains("重なっています"))
            #expect(message.contains("カテゴリ「nope」"))
            #expect(message.contains("sources.yml:8:"))
        }
    }

    @Test(
        "キャッシュの名前（slug）",
        arguments: [
            ("EasyList", "easylist"),
            ("AdGuard Japanese filter", "adguard-japanese-filter"),
            ("自作ルール（basic）", "basic"),
            ("  Foo--Bar 2 ", "foo-bar-2"),
        ]
    )
    func slugs(name: String, expected: String) {
        #expect(SourcesFile.slug(for: name, fallbackSeed: .url(URL(string: "https://example.com/")!)) == expected)
    }

    @Test("英数字のない名前は、URL のハッシュから slug を作る")
    func slugFallback() {
        let slug = SourcesFile.slug(for: "日本語だけ", fallbackSeed: .url(URL(string: "https://example.com/a.txt")!))
        #expect(slug.hasPrefix("source-"))
        #expect(slug.count == "source-".count + 8)
    }
}
