import Foundation
import Testing
@testable import RulesKit

@Suite("manifest の形式")
struct ManifestTests {
    static let sha = "1a2b3c4d" + String(repeating: "0", count: 56)

    static var sample: Manifest {
        Manifest(
            version: "2026.10.05.1",
            publishedAt: "2026-10-05T03:00:00Z",
            minAppBuild: 1,
            lists: [Manifest.Entry(category: "basic", url: "lists/basic.1a2b3c4d.json", sha256: sha, size: 1_234_567, ruleCount: 12345)]
        )
    }

    @Test("キーを並べ替え、字下げし、/ をエスケープしない（docs/format.md の例と同じ形）")
    func encoding() throws {
        let text = String(decoding: try Self.sample.encoded(), as: UTF8.self)
        let expected = """
        {
          "lists" : [
            {
              "category" : "basic",
              "rule_count" : 12345,
              "sha256" : "\(Self.sha)",
              "size" : 1234567,
              "url" : "lists/basic.1a2b3c4d.json"
            }
          ],
          "min_app_build" : 1,
          "published_at" : "2026-10-05T03:00:00Z",
          "schema" : 1,
          "version" : "2026.10.05.1"
        }
        """
        #expect(text == expected)
        #expect(!text.contains(#"\/"#))
    }

    @Test("読み戻すと同じ")
    func roundTrip() throws {
        #expect(try Manifest.decode(try Self.sample.encoded()) == Self.sample)
    }

    @Test("正しい manifest に問題はない")
    func validHasNoProblems() {
        #expect(Self.sample.problems().isEmpty)
    }

    @Test(
        "リストの URL の形（^lists/[a-z]+\\.[0-9a-f]{8}\\.json$）",
        arguments: [
            ("lists/basic.1a2b3c4d.json", true),
            ("lists/annoyance.00000000.json", true),
            ("lists/Basic.1a2b3c4d.json", false),
            ("lists/basic.1A2B3C4D.json", false),
            ("lists/basic.1a2b3c4.json", false),
            ("lists/basic.1a2b3c4d0.json", false),
            ("../lists/basic.1a2b3c4d.json", false),
            ("lists/../basic.1a2b3c4d.json", false),
            ("/lists/basic.1a2b3c4d.json", false),
            ("https://example.com/lists/basic.1a2b3c4d.json", false),
            ("lists/basic.1a2b3c4d.json?x=1", false),
            ("lists/ba-sic.1a2b3c4d.json", false),
            ("lists/basic.1a2b3c4d.jsonx", false),
            ("lists/.1a2b3c4d.json", false),
            ("lists/basic.v2.1a2b3c4d.json", false),
        ]
    )
    func listURLPattern(url: String, valid: Bool) {
        #expect(ManifestFormat.isValidListURL(url) == valid)
    }

    @Test("ファイル名は <category>.<sha256 の先頭 8 文字>.json")
    func hash8Naming() {
        let data = Data("[]".utf8)
        let sha = Hashing.sha256Hex(data)
        #expect(sha == "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945")
        #expect(ManifestFormat.hash8(sha) == "4f53cda1")
        #expect(ManifestFormat.listFileName(category: .scam, sha256: sha) == "scam.4f53cda1.json")
        #expect(ManifestFormat.listPath(category: .scam, sha256: sha) == "lists/scam.4f53cda1.json")
    }

    @Test(
        "版の形（YYYY.MM.DD.N）",
        arguments: [
            ("2026.10.05.1", true),
            ("2026.10.05.12", true),
            ("2026.10.05.0", false),
            ("2026.10.05.01", false),
            ("2026.13.01.1", false),
            ("2026.02.30.1", false),
            ("2026.1.05.1", false),
            ("2026.10.05", false),
            ("2026-10-05.1", false),
            ("2026.10.05.1a", false),
        ]
    )
    func versions(version: String, valid: Bool) {
        #expect(ManifestFormat.isValidVersion(version) == valid)
    }

    @Test("既定の版は、その日（UTC）の 1 番目")
    func defaultVersion() {
        // 2026-09-29 00:30（日本時間）は、UTC では 2026-09-28 15:30
        let date = Date(timeIntervalSince1970: 1_790_609_400)
        #expect(ManifestFormat.formatPublishedAt(date) == "2026-09-28T15:30:00Z")
        #expect(ManifestFormat.defaultVersion(for: date) == "2026.09.28.1")
    }

    @Test("公開日時は UTC の秒まで")
    func publishedAt() {
        #expect(ManifestFormat.formatPublishedAt(Date(timeIntervalSince1970: 1_790_609_400.987)) == "2026-09-28T15:30:00Z")
        #expect(ManifestFormat.normalizePublishedAt("2026-10-05T12:00:00+09:00") == "2026-10-05T03:00:00Z")
        #expect(ManifestFormat.normalizePublishedAt("2026-10-05T03:00:00.999Z") == "2026-10-05T03:00:00Z")
        #expect(ManifestFormat.normalizePublishedAt("2026-10-05") == nil)
        #expect(ManifestFormat.normalizePublishedAt("garbage") == nil)
        #expect(ManifestFormat.isValidPublishedAt("2026-10-05T03:00:00Z"))
        #expect(!ManifestFormat.isValidPublishedAt("2026-10-05T03:00:00.000Z"))
        #expect(!ManifestFormat.isValidPublishedAt("2026-10-05T12:00:00+09:00"))
    }

    @Test("取り決めに合わない manifest の問題")
    func problems() {
        func check(_ fragment: String, _ change: (inout Manifest) -> Void) {
            var manifest = Self.sample
            change(&manifest)
            let problems = manifest.problems()
            #expect(problems.contains { $0.contains(fragment) }, "\(fragment): \(problems)")
        }
        check("schema") { $0.schema = 2 }
        check("version") { $0.version = "2026.10.05" }
        check("published_at") { $0.publishedAt = "2026-10-05T12:00:00+09:00" }
        check("min_app_build") { $0.minAppBuild = 0 }
        check("知らないカテゴリ") { $0.lists[0].category = "ads" }
        check("sha256") { $0.lists[0].sha256 = String(repeating: "A", count: 64) }
        check("合っていません") { $0.lists[0].url = "lists/basic.ffffffff.json" }
        check("合っていません") { $0.lists[0].url = "lists/scam.1a2b3c4d.json" }
        check("lists/<category>") { $0.lists[0].url = "../x.json" }
        check("size") { $0.lists[0].size = 0 }
        check("size") { $0.lists[0].size = 25 * 1024 * 1024 }
        check("rule_count") { $0.lists[0].ruleCount = 0 }
        check("2 回") { $0.lists.append($0.lists[0]) }
        check("順に並んでいません") {
            $0.lists.insert(Manifest.Entry(category: "scam", url: "lists/scam.1a2b3c4d.json", sha256: Self.sha, size: 1, ruleCount: 1), at: 0)
        }
    }
}

@Suite("compare（配信するものが変わったか）")
struct CompareTests {
    static func manifest(_ lists: [(String, String)], minAppBuild: Int = 1, version: String = "2026.10.05.1") -> Manifest {
        Manifest(
            version: version, publishedAt: "2026-10-05T03:00:00Z", minAppBuild: minAppBuild,
            lists: lists.map { Manifest.Entry(category: $0.0, url: "lists/\($0.0).\($0.1.prefix(8)).json", sha256: $0.1, size: 1, ruleCount: 1) }
        )
    }

    static let a = String(repeating: "a", count: 64)
    static let b = String(repeating: "b", count: 64)

    @Test("版と公開日時だけ違うなら unchanged")
    func sameContent() {
        let previous = Self.manifest([("basic", Self.a), ("annoyance", Self.b)], version: "2026.10.04.1")
        let current = Self.manifest([("annoyance", Self.b), ("basic", Self.a)])
        #expect(ManifestComparison.isUnchanged(current: current, previous: previous))
    }

    @Test("ハッシュ・カテゴリ・min_app_build が違えば changed")
    func changed() {
        let base = Self.manifest([("basic", Self.a)])
        #expect(!ManifestComparison.isUnchanged(current: Self.manifest([("basic", Self.b)]), previous: base))
        #expect(!ManifestComparison.isUnchanged(current: Self.manifest([("basic", Self.a), ("scam", Self.b)]), previous: base))
        #expect(!ManifestComparison.isUnchanged(current: Self.manifest([("annoyance", Self.a)]), previous: base))
        #expect(!ManifestComparison.isUnchanged(current: Self.manifest([("basic", Self.a)], minAppBuild: 2), previous: base))
    }
}
