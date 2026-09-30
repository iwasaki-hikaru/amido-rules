import CryptoKit
import Foundation
import Testing
@testable import RulesKit

@Suite("配信一式の検証（verify）")
struct DistributionVerifierTests {
    let key = Curve25519.Signing.PrivateKey()

    var trusted: TrustedKeys { trustedKeys(key, ids: ["primary"]) }

    @discardableResult
    func makeSample(in directory: URL, ruleCountOverride: Int? = nil) throws -> Manifest {
        try makeDistribution(
            in: directory,
            lists: [(.basic, SampleLists.basic, ruleCountOverride), (.annoyance, SampleLists.annoyance, nil)],
            key: key,
            trusted: trusted
        )
    }

    func verify(_ directory: URL, trusted: TrustedKeys? = nil) async throws -> DistributionVerifier.Result {
        try await DistributionVerifier.verify(
            manifestAt: DistributionVerifier.manifestLocation(directory: directory),
            trusted: trusted ?? self.trusted
        )
    }

    @Test("正しい一式は検証できる（--dir は出力のルートでも v1 でもよい）")
    func verifiesDirectory() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try makeSample(in: directory)

        let result = try await verify(directory)
        #expect(result.keyID == "primary")
        #expect(result.manifest == manifest)
        #expect(result.lists.map(\.category) == ["basic", "annoyance"])
        #expect(result.lists.map(\.ruleCount) == [1, 2])

        let fromV1 = try await verify(directory.appending(path: "v1"))
        #expect(fromV1.keyID == "primary")
    }

    @Test("manifest を書き換えると、署名の検証で止まる")
    func tamperedManifest() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeSample(in: directory)
        let url = directory.appending(path: "v1/manifest.json")
        let text = try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "\"min_app_build\" : 1", with: "\"min_app_build\" : 2")
        try write(text, to: url)
        await #expect(throws: RulesError.self) { try await verify(directory) }
    }

    @Test("別の鍵で署名されたものは検証できない")
    func wrongKey() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeSample(in: directory)
        await #expect(throws: RulesError.self) {
            try await verify(directory, trusted: trustedKeys(Curve25519.Signing.PrivateKey()))
        }
    }

    @Test("リストを書き換えると、ハッシュの検査で止まる")
    func tamperedList() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try makeSample(in: directory)
        let url = directory.appending(path: "v1").appending(path: manifest.lists[0].url)
        var data = try Data(contentsOf: url)
        data[data.index(before: data.endIndex) - 2] = UInt8(ascii: "x")
        try data.write(to: url)
        do {
            _ = try await verify(directory)
            Issue.record("検証できてしまった")
        } catch let error as RulesError {
            #expect(error.message.contains("SHA-256"))
            #expect(error.message.contains("basic"))
        }
    }

    @Test("rule_count が合わなければ止まる")
    func ruleCountMismatch() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try makeSample(in: directory, ruleCountOverride: 3)
        do {
            _ = try await verify(directory)
            Issue.record("検証できてしまった")
        } catch let error as RulesError {
            #expect(error.message.contains("ルールの数"))
        }
    }

    @Test("リストがなければ止まる。.sig がなければ止まる")
    func missingFiles() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = try makeSample(in: directory)
        try FileManager.default.removeItem(at: directory.appending(path: "v1").appending(path: manifest.lists[1].url))
        await #expect(throws: RulesError.self) { try await verify(directory) }
        try FileManager.default.removeItem(at: directory.appending(path: "v1/manifest.json.sig"))
        await #expect(throws: RulesError.self) { try await verify(directory) }
    }

    @Test("リスト 1 つの検査")
    func listProblem() {
        let data = Data(SampleLists.annoyance.utf8)
        let entry = Manifest.Entry(category: "annoyance", url: "", sha256: Hashing.sha256Hex(data), size: data.count, ruleCount: 2)
        #expect(DistributionVerifier.listProblem(data, entry: entry) == nil)
        var wrongSize = entry
        wrongSize.size += 1
        #expect(DistributionVerifier.listProblem(data, entry: wrongSize)?.contains("大きさ") == true)
        let object = Data("{}".utf8)
        #expect(DistributionVerifier.listProblem(object, entry: Manifest.Entry(category: "basic", url: "", sha256: Hashing.sha256Hex(object), size: 2, ruleCount: 1))?.contains("配列") == true)
    }

    @Test(
        "--base-url の解釈",
        arguments: [
            ("https://rules.example.com", "https://rules.example.com/v1/manifest.json"),
            ("https://rules.example.com/", "https://rules.example.com/v1/manifest.json"),
            ("https://rules.example.com/v1/", "https://rules.example.com/v1/manifest.json"),
            ("https://rules.example.com/v1", "https://rules.example.com/v1/manifest.json"),
            ("https://rules.example.com/v1/manifest.json", "https://rules.example.com/v1/manifest.json"),
            ("http://127.0.0.1:8787", "http://127.0.0.1:8787/v1/manifest.json"),
        ]
    )
    func baseURL(input: String, expected: String) throws {
        #expect(try DistributionVerifier.manifestLocation(baseURL: input) == .remote(URL(string: expected)!))
    }

    @Test("--base-url は https だけ（ループバックの http は例外）")
    func baseURLPolicy() {
        #expect(throws: RulesError.self) { try DistributionVerifier.manifestLocation(baseURL: "http://rules.example.com") }
        #expect(throws: RulesError.self) { try DistributionVerifier.manifestLocation(baseURL: "ftp://rules.example.com") }
    }

    @Test("リストの URL は manifest と同じ場所を基準にする")
    func resolving() throws {
        let remote = ResourceLocation.remote(URL(string: "https://rules.example.com/v1/manifest.json")!)
        #expect(try remote.resolving("lists/basic.1a2b3c4d.json") == .remote(URL(string: "https://rules.example.com/v1/lists/basic.1a2b3c4d.json")!))
        #expect(throws: RulesError.self) { try remote.resolving("https://other.example.com/x.json") }
        let local = ResourceLocation.local(URL(fileURLWithPath: "/tmp/out/v1/manifest.json"))
        #expect(try local.resolving("lists/a.json") == .local(URL(fileURLWithPath: "/tmp/out/v1/lists/a.json")))
    }

    @Test("ローカルのファイルがなければ missing")
    func missingLocal() async throws {
        let outcome = try await ResourceLoader.load(.local(URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/manifest.json")))
        #expect(outcome == .missing)
    }
}

@Suite("配信するディレクトリ（site）")
struct SiteAssemblerTests {
    let key = Curve25519.Signing.PrivateKey()

    var trusted: TrustedKeys { trustedKeys(key) }

    func makeSite(in root: URL) throws -> URL {
        let site = root.appending(path: "site")
        try write("<!doctype html><title>check</title>", to: site.appending(path: "check.html"))
        try write("/v1/*\n  Cache-Control: no-cache\n", to: site.appending(path: "_headers"))
        try write("_headers\n", to: site.appending(path: ".assetsignore"))
        try write("junk", to: site.appending(path: ".DS_Store"))
        try write("<p>nested</p>", to: site.appending(path: "docs/page.html"))
        return site
    }

    @Test("site/ の中身（_headers・.assetsignore を含む）と、v1 の一式を置く")
    func assembles() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = try makeSite(in: root)
        let rules = root.appending(path: "out")
        let manifest = try makeDistribution(in: rules, lists: [(.basic, SampleLists.basic, nil)], key: key, trusted: trusted)
        let dist = root.appending(path: "dist")

        let result = try await SiteAssembler.assemble(site: site, rules: rules, out: dist, keepPrevious: nil)
        #expect(result.warnings.isEmpty)
        #expect(result.lists == manifest.lists.map(\.url))
        for path in ["check.html", "_headers", ".assetsignore", "docs/page.html", "v1/manifest.json", "v1/manifest.json.sig", "v1/\(manifest.lists[0].url)"] {
            #expect(FileManager.default.fileExists(atPath: dist.appending(path: path).path(percentEncoded: false)), "\(path)")
        }
        #expect(!FileManager.default.fileExists(atPath: dist.appending(path: ".DS_Store").path(percentEncoded: false)))

        let verified = try await DistributionVerifier.verify(manifestAt: DistributionVerifier.manifestLocation(directory: dist), trusted: trusted)
        #expect(verified.lists.count == 1)

        // 前の出力の上には、作り直せる
        _ = try await SiteAssembler.assemble(site: site, rules: rules, out: dist, keepPrevious: nil)
    }

    @Test("運営者へのメモ（「運営者へ」で始まる HTML のコメント）は、配信するページから取り除く")
    func removesOperatorNotes() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = try makeSite(in: root)
        let page = """
        <!doctype html>
        <!--
          運営者へ：
          - ios リポジトリの docs/decisions.md を見てください。
        -->
        <html lang="ja">
        <!-- 運営者へ：1 行のメモ --><p>本文</p>
        <!-- ふつうのコメント -->
        </html>
        """
        try write(page, to: site.appending(path: "privacy.html"))
        let rules = root.appending(path: "out")
        _ = try makeDistribution(in: rules, lists: [(.basic, SampleLists.basic, nil)], key: key, trusted: trusted)
        let dist = root.appending(path: "dist")

        _ = try await SiteAssembler.assemble(site: site, rules: rules, out: dist, keepPrevious: nil)
        let served = try String(contentsOf: dist.appending(path: "privacy.html"), encoding: .utf8)
        #expect(!served.contains("運営者へ"))
        #expect(!served.contains("decisions.md"))
        #expect(served.contains("<p>本文</p>"))
        #expect(served.contains("<!-- ふつうのコメント -->"))
        #expect(served.hasPrefix("<!doctype html>\n<html lang=\"ja\">"))
        // site/ の元のファイルは変えない
        #expect(try String(contentsOf: site.appending(path: "privacy.html"), encoding: .utf8) == page)
    }

    @Test("site/ がなければ失敗する")
    func missingSite() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let rules = root.appending(path: "out")
        try makeDistribution(in: rules, lists: [(.basic, SampleLists.basic, nil)], key: key, trusted: trusted)
        await #expect(throws: RulesError.self) {
            try await SiteAssembler.assemble(site: root.appending(path: "site"), rules: rules, out: root.appending(path: "dist"), keepPrevious: nil)
        }
    }

    @Test("出力先が関係のないディレクトリなら、消さずに止まる")
    func refusesUnrelatedOutput() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = try makeSite(in: root)
        let rules = root.appending(path: "out")
        try makeDistribution(in: rules, lists: [(.basic, SampleLists.basic, nil)], key: key, trusted: trusted)
        let unrelated = root.appending(path: "important")
        try write("keep me", to: unrelated.appending(path: "notes.txt"))
        await #expect(throws: RulesError.self) {
            try await SiteAssembler.assemble(site: site, rules: rules, out: unrelated, keepPrevious: nil)
        }
        #expect(FileManager.default.fileExists(atPath: unrelated.appending(path: "notes.txt").path(percentEncoded: false)))
    }

    @Test("--keep-previous：本番の manifest のリストも置く。前がなければ警告だけ")
    func keepsPreviousLists() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = try makeSite(in: root)
        let live = root.appending(path: "live")
        let previous = try makeDistribution(
            in: live,
            lists: [(.basic, #"[{"trigger":{"url-filter":"old"},"action":{"type":"block"}}]"#, nil), (.annoyance, SampleLists.annoyance, nil)],
            key: key, trusted: trusted
        )
        let rules = root.appending(path: "out")
        let current = try makeDistribution(in: rules, lists: [(.basic, SampleLists.basic, nil), (.annoyance, SampleLists.annoyance, nil)], key: key, trusted: trusted)
        let dist = root.appending(path: "dist")

        let result = try await SiteAssembler.assemble(
            site: site, rules: rules, out: dist,
            keepPrevious: .local(live.appending(path: "v1/manifest.json"))
        )
        // annoyance は同じファイルなので、前の版として足すのは basic だけ
        #expect(result.keptPreviousLists == [previous.lists[0].url])
        #expect(previous.lists[1].url == current.lists[1].url)
        for url in previous.lists.map(\.url) + current.lists.map(\.url) {
            #expect(FileManager.default.fileExists(atPath: dist.appending(path: "v1/\(url)").path(percentEncoded: false)))
        }

        let missing = try await SiteAssembler.assemble(
            site: site, rules: rules, out: dist,
            keepPrevious: .local(root.appending(path: "nowhere/v1/manifest.json"))
        )
        #expect(missing.keptPreviousLists.isEmpty)
        #expect(missing.warnings.contains { $0.contains("ありません") })
    }

    @Test(".sig がなければ警告する")
    func warnsWithoutSignature() async throws {
        let root = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let site = try makeSite(in: root)
        let rules = root.appending(path: "out")
        try makeDistribution(in: rules, lists: [(.basic, SampleLists.basic, nil)], key: key, trusted: trusted)
        try FileManager.default.removeItem(at: rules.appending(path: "v1/manifest.json.sig"))
        let result = try await SiteAssembler.assemble(site: site, rules: rules, out: root.appending(path: "dist"), keepPrevious: nil)
        #expect(result.warnings.contains { $0.contains(".sig") })
    }
}
