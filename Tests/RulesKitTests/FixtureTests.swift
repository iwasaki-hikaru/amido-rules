import Foundation
import Testing
@testable import RulesKit

/// iOS アプリのテストで使う、署名済みの配信一式（Tests/Fixtures/signed-sample）。
/// 作り直すとき：swift run rulestool fixture --out Tests/Fixtures/signed-sample
@Suite("テスト用の配信一式（signed-sample）")
struct FixtureTests {
    static let directory = TestEnvironment.fixtures.appending(path: "signed-sample")

    @Test("RFC 8032 TEST 1 の公開鍵で検証できる")
    func verifies() async throws {
        let result = try await DistributionVerifier.verify(
            manifestAt: DistributionVerifier.manifestLocation(directory: Self.directory),
            trusted: SampleFixture.trustedKeys
        )
        #expect(result.keyID == "rfc8032-test1")
        #expect(result.manifest.schema == 1)
        #expect(result.manifest.version == "2026.01.01.1")
        #expect(result.manifest.publishedAt == "2026-01-01T00:00:00Z")
        #expect(result.manifest.minAppBuild == 1)
        #expect(result.manifest.lists.map(\.category) == ["basic", "annoyance"])
        #expect(result.manifest.lists.map(\.ruleCount) == [2, 1])
    }

    @Test("同梱の test-public-keys.json は TEST 1 の公開鍵")
    func keysFile() throws {
        let keys = try TrustedKeys.load(from: Self.directory.appending(path: "test-public-keys.json"))
        #expect(keys == SampleFixture.trustedKeys)
        #expect(SampleFixture.publicKeyBase64 == "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=")
    }

    @Test("作り直すと、manifest とリストは同じバイト列になる")
    func deterministic() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let written = try SampleFixture.write(to: directory)
        #expect(written.signatureRewritten)
        let committed = try Data(contentsOf: Self.directory.appending(path: "v1/manifest.json"))
        let regenerated = try Data(contentsOf: directory.appending(path: "v1/manifest.json"))
        #expect(committed == regenerated)
        let manifest = try Manifest.decode(committed)
        for entry in manifest.lists {
            let a = try Data(contentsOf: Self.directory.appending(path: "v1").appending(path: entry.url))
            let b = try Data(contentsOf: directory.appending(path: "v1").appending(path: entry.url))
            #expect(a == b)
        }
        // もう一度書いても、署名は検証できるのでそのまま
        #expect(try SampleFixture.write(to: directory).signatureRewritten == false)
    }

    @Test("リストは検査を通り、テスト用のドメインだけを使う")
    func listsAreValidAndUseTestDomains() {
        for json in [SampleFixture.basicRulesJSON, SampleFixture.annoyanceRulesJSON] {
            #expect(RuleListLint.lint(Data(json.utf8), forbidExceptions: false).isValid)
            let domains = json.components(separatedBy: "example.").count - 1
            #expect(domains >= 1)
            for word in ["google", "doubleclick", ".jp", ".net"] {
                #expect(!json.contains(word))
            }
        }
    }
}
