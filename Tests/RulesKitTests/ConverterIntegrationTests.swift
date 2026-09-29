import CryptoKit
import Foundation
import Testing
@testable import RulesKit

/// 実際の ConverterTool を使うテスト。変換器がなければ飛ばす
/// （CONVERTER_PATH を指定するか、scripts/fetch-converter.sh でビルドする）。
@Suite(
    "変換器との結合（実際の ConverterTool）",
    .enabled(if: TestEnvironment.hasConverter, "ConverterTool がないので飛ばします（CONVERTER_PATH を指定するか、scripts/fetch-converter.sh でビルドしてください）")
)
struct ConverterIntegrationTests {
    func convert(_ text: String) async throws -> ConverterResult {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let input = directory.appending(path: "input.txt")
        try write(text, to: input)
        let runner = ConverterRunner(executable: try #require(TestEnvironment.converterURL))
        return try await runner.convert(inputFile: input)
    }

    func rules(_ result: ConverterResult) throws -> [NSDictionary] {
        try #require(try JSONSerialization.jsonObject(with: Data(result.safariRulesJSON.utf8)) as? [NSDictionary])
    }

    @Test("$document の例外は、許可サイトのルールと同じ形になる（アプリはこの形を末尾に足す）")
    func documentExceptionShape() async throws {
        let result = try await convert("@@||example.com^$document\n")
        #expect(result.safariRulesCount == 1)
        #expect(result.discardedSafariRules == 0)
        #expect(result.errorsCount == 0)
        #expect(result.safariRulesJSON == "[\(RuleConstants.sampleAllowlistRuleJSON)]")
        let expected = try JSONSerialization.jsonObject(with: Data(RuleConstants.sampleAllowlistRuleJSON.utf8)) as? NSDictionary
        #expect(try rules(result).first == expected)
    }

    @Test("ルールが 0 件のとき、変換器は独自のルールを出すが、safariRulesCount は 0")
    func zeroRules() async throws {
        let result = try await convert("! コメントだけ\n")
        #expect(result.safariRulesCount == 0)
        let first = try #require(try rules(result).first)
        let trigger = first["trigger"] as? NSDictionary
        #expect(trigger?["if-domain"] as? [String] == ["domain.com"])
    }

    @Test("[Adblock Plus 2.0] の行は、取り除かないとルールになってしまう")
    func headerBecomesRuleUnlessStripped() async throws {
        let raw = "[Adblock Plus 2.0]\n! Title: test\n"
        let unstripped = try await convert(raw)
        #expect(unstripped.safariRulesCount >= 1)
        let stripped = try await convert(SourceText.stripAdblockHeaders(raw).text)
        #expect(stripped.safariRulesCount == 0)
    }

    @Test("空行があっても最後まで読む（--input-path を使うため）")
    func readsPastBlankLines() async throws {
        let result = try await convert("||ads.example.com^\n\n\n||tracker.example.org^\n")
        #expect(result.safariRulesCount == 2)
    }

    @Test("同じ入力からは、毎回同じバイト列になる（SWIFT_DETERMINISTIC_HASHING）")
    func deterministicOutput() async throws {
        // ドメインごとの要素隠しがたくさんあると、ハッシュの種しだいで並びが変わる（テスト用のドメインだけ）
        var lines: [String] = []
        for index in 0..<200 {
            lines.append("s\(index).example.com##.ad\(index)")
        }
        for index in 0..<50 {
            lines.append("s\(index).example.org,s\(index).example.net##.box\(index % 7)")
        }
        let input = lines.joined(separator: "\n") + "\n"
        let first = try await convert(input)
        #expect(first.safariRulesCount == 250)
        for _ in 0..<3 {
            let again = try await convert(input)
            #expect(again.safariRulesJSON == first.safariRulesJSON)
        }
        #expect(ConverterRunner.environment(["PATH": "/usr/bin"]) == ["PATH": "/usr/bin", "SWIFT_DETERMINISTIC_HASHING": "1"])
    }

    @Test("変換器がなければ、わかるエラーにする")
    func missingConverter() async {
        let runner = ConverterRunner(executable: URL(fileURLWithPath: "/nonexistent/ConverterTool"))
        do {
            _ = try await runner.convert(inputFile: URL(fileURLWithPath: "/nonexistent/input.txt"))
            Issue.record("エラーにならなかった")
        } catch {
            #expect(error.localizedDescription.contains("変換器が見つからない"))
        }
    }
}

/// build の流れ全体を、小さな入力で確かめる（実際の ConverterTool と WebKit を使う）。
@Suite(
    "build の流れ（小さな入力）",
    .serialized,
    .enabled(if: TestEnvironment.hasConverter, "ConverterTool がないので飛ばします")
)
@MainActor
struct BuildPipelineTests {
    static let host = "check.example.com"

    /// 一時ディレクトリに、リポジトリと同じ形の sources.yml・custom・config を作る。
    func makeRepository(basic: String, annoyance: String = "", scam: String = "", extraSources: String = "") throws -> URL {
        let root = try makeTemporaryDirectory()
        let evidence = "! 根拠: https://example.com/evidence (2026-01-02)\n"
        try write(basic.isEmpty ? "" : evidence + basic + "\n", to: root.appending(path: "custom/basic.txt"))
        try write(annoyance.isEmpty ? "" : evidence + annoyance + "\n", to: root.appending(path: "custom/annoyance.txt"))
        try write(scam.isEmpty ? "" : evidence + scam + "\n", to: root.appending(path: "custom/scam.txt"))
        var sources = "sources:\n"
        for category in ["basic", "annoyance", "scam"] {
            sources += """
              - name: 自作ルール（\(category)）
                path: custom/\(category).txt
                license: CC-BY-SA-3.0
                attribution: tests
                category: \(category)
                enabled: true

            """
        }
        sources += extraSources
        try write(sources, to: root.appending(path: "sources.yml"))
        let config = root.appending(path: "config")
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        for name in ["budgets.json", "denylist.json"] {
            try FileManager.default.copyItem(
                at: TestEnvironment.rulesRoot.appending(path: "config/\(name)"),
                to: config.appending(path: name)
            )
        }
        try write(#"{"host":"\#(Self.host)","minAppBuild":3}"#, to: config.appending(path: "distribution.json"))
        return root
    }

    func options(_ root: URL, _ change: (inout BuildOptions) -> Void = { _ in }) throws -> BuildOptions {
        var options = BuildOptions(
            converter: try #require(TestEnvironment.converterURL),
            outDirectory: root.appending(path: "build/out"),
            sourcesFile: root.appending(path: "sources.yml"),
            configDirectory: root.appending(path: "config"),
            version: "2026.10.05.2",
            publishedAt: "2026-10-05T12:00:00+09:00",
            offline: true
        )
        change(&options)
        return options
    }

    @Test("成功：manifest とリストを書き、署名して検証できる")
    func succeeds() async throws {
        let root = try makeRepository(basic: "||ads.example.com^", annoyance: "example.org##.popup")
        defer { try? FileManager.default.removeItem(at: root) }
        let options = try options(root)
        let report = await BuildPipeline.run(options)
        #expect(report.ok, "\(report.errors)")
        #expect(report.publishedAt == "2026-10-05T03:00:00Z")
        #expect(report.host == Self.host)

        let out = options.outDirectory
        let manifestData = try Data(contentsOf: out.appending(path: "v1/manifest.json"))
        let manifest = try Manifest.decode(manifestData)
        #expect(manifest.version == "2026.10.05.2")
        #expect(manifest.minAppBuild == 3)
        // scam は 0 件なので載せない。basic と annoyance には /check 用のルールが 1 件ずつ足される
        #expect(manifest.lists.map(\.category) == ["basic", "annoyance"])
        #expect(manifest.lists.map(\.ruleCount) == [2, 2])
        #expect(manifest.problems().isEmpty)
        #expect(FileManager.default.fileExists(atPath: out.appending(path: "report.json").path(percentEncoded: false)))
        let summary = try String(contentsOf: out.appending(path: "summary.md"), encoding: .utf8)
        #expect(summary.contains("成功"))
        #expect(report.compile?.entries.map(\.target) == ["extension:basic", "extension:plus", "category:basic", "category:annoyance"])
        #expect(report.compile?.entries.allSatisfy(\.ok) == true)

        let basicList = try Data(contentsOf: out.appending(path: "v1").appending(path: manifest.lists[0].url))
        #expect(BuildPipeline.containsCheckRule(basicList, host: Self.host, className: "cb-check-basic"))

        let key = Curve25519.Signing.PrivateKey()
        let trusted = trustedKeys(key)
        let signed = try Signing.sign(manifest: manifestData, privateKey: key, trusted: trusted)
        try Data(signed.signatureFile.utf8).write(to: out.appending(path: "v1/manifest.json.sig"))
        let verified = try await DistributionVerifier.verify(manifestAt: DistributionVerifier.manifestLocation(directory: out), trusted: trusted)
        #expect(verified.lists.count == 2)
    }

    @Test("--compose-out：拡張ごとに合成した JSON（アプリが Safari に渡す形）を書く。配信するディレクトリには入れない")
    func writesCompositions() async throws {
        let root = try makeRepository(basic: "||ads.example.com^", annoyance: "example.org##.popup")
        defer { try? FileManager.default.removeItem(at: root) }
        let composeDirectory = root.appending(path: "build/compose")
        let options = try options(root) {
            $0.composeDirectory = composeDirectory
            $0.skipCompileCheck = true
        }
        let report = await BuildPipeline.run(options)
        #expect(report.ok, "\(report.errors)")

        let names = try FileManager.default.contentsOfDirectory(atPath: composeDirectory.path(percentEncoded: false)).sorted()
        #expect(names == ["extension-basic.json", "extension-plus.json"])
        for name in names {
            let data = try Data(contentsOf: composeDirectory.appending(path: name))
            let rules = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
            // 末尾は許可サイトのルールの見本（アプリが足すものと同じ形）
            let last = try #require(rules.last)
            let action = last["action"] as? [String: Any]
            #expect(action?["type"] as? String == "ignore-previous-rules")
        }
        // basic は、basic のルール（/check 用を含む 2 件）と許可サイトの 1 件
        let basic = try JSONSerialization.jsonObject(with: Data(contentsOf: composeDirectory.appending(path: "extension-basic.json"))) as? [Any]
        #expect(basic?.count == 3)
        #expect(!FileManager.default.fileExists(atPath: options.outDirectory.appending(path: "extension-basic.json").path(percentEncoded: false)))
    }

    @Test("scam（plus の 2 番目）に例外ルールがあれば失敗し、manifest を書かない")
    func exceptionInScamFails() async throws {
        let root = try makeRepository(basic: "||ads.example.com^", scam: "@@||example.org^$document")
        defer { try? FileManager.default.removeItem(at: root) }
        let options = try options(root) { $0.skipCompileCheck = true }
        let report = await BuildPipeline.run(options)
        #expect(!report.ok)
        #expect(report.errors.contains { $0.hasPrefix("scam：rules[0]:") && $0.contains("2 番目以降") })
        #expect(!FileManager.default.fileExists(atPath: options.outDirectory.appending(path: "v1/manifest.json").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: options.outDirectory.appending(path: "report.json").path(percentEncoded: false)))
        #expect(report.compile?.skipped == true)
    }

    @Test("根拠のない自作ルールがあれば失敗する")
    func missingEvidenceFails() async throws {
        let root = try makeRepository(basic: "||ads.example.com^")
        defer { try? FileManager.default.removeItem(at: root) }
        try write("||no-evidence.example.com^\n", to: root.appending(path: "custom/annoyance.txt"))
        let report = await BuildPipeline.run(try options(root) { $0.skipCompileCheck = true })
        #expect(!report.ok)
        #expect(report.errors.contains { $0.hasPrefix("custom/annoyance.txt:1:") })
    }

    @Test("前の manifest と比べて、件数が急に変わったら失敗（許可すれば通る）")
    func countChange() async throws {
        let root = try makeRepository(basic: "||ads.example.com^")
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = Manifest(
            version: "2026.10.04.1", publishedAt: "2026-10-04T00:00:00Z", minAppBuild: 1,
            lists: [Manifest.Entry(category: "basic", url: "lists/basic.00000000.json", sha256: String(repeating: "0", count: 64), size: 10, ruleCount: 5000)]
        )
        let previousURL = root.appending(path: "previous/manifest.json")
        try FileManager.default.createDirectory(at: previousURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try previous.encoded().write(to: previousURL)

        let failing = await BuildPipeline.run(try options(root) {
            $0.previousManifest = previousURL.path(percentEncoded: false)
            $0.skipCompileCheck = true
        })
        #expect(!failing.ok)
        #expect(failing.countChange?.entries.first?.status == .exceeded)
        #expect(failing.errors.contains { $0.contains("--allow-count-change") })

        let allowed = await BuildPipeline.run(try options(root) {
            $0.previousManifest = previousURL.path(percentEncoded: false)
            $0.allowCountChange = true
            $0.skipCompileCheck = true
        })
        #expect(allowed.ok, "\(allowed.errors)")
        #expect(allowed.warnings.contains { $0.contains("--allow-count-change") })

        let firstRun = await BuildPipeline.run(try options(root) {
            $0.previousManifest = root.appending(path: "nowhere/manifest.json").path(percentEncoded: false)
            $0.skipCompileCheck = true
        })
        #expect(firstRun.ok)
        #expect(firstRun.countChange?.checked == false)
    }

    @Test("オフラインで、上流のリストのキャッシュがなければ失敗する。あれば使う")
    func offlineCache() async throws {
        let extra = """
          - name: Upstream Test
            url: https://lists.example.com/upstream.txt
            license: CC0-1.0
            attribution: tests
            category: basic
            enabled: true

        """
        let root = try makeRepository(basic: "||ads.example.com^", extraSources: extra)
        defer { try? FileManager.default.removeItem(at: root) }

        let missing = await BuildPipeline.run(try options(root) { $0.skipCompileCheck = true })
        #expect(!missing.ok)
        #expect(missing.errors.contains { $0.contains("build/sources/upstream-test.txt") })

        try write("[Adblock Plus 2.0]\n! Licence: https://example.com/licence\n||upstream.example.net^\n", to: root.appending(path: "build/sources/upstream-test.txt"))
        let cached = await BuildPipeline.run(try options(root) { $0.skipCompileCheck = true })
        #expect(cached.ok, "\(cached.errors)")
        let upstream = try #require(cached.sources.first { $0.name == "Upstream Test" })
        #expect(upstream.fromCache == true)
        #expect(upstream.removedHeaderLines == 1)
        #expect(upstream.headerLines == ["! Licence: https://example.com/licence"])
        #expect(cached.categories.first?.ruleCount == 3)
    }

    @Test("配信ホストは小文字にする。正しくないホストは失敗")
    func hostNormalization() throws {
        #expect(try BuildPipeline.normalizeHost("PLACEHOLDER-worker.Example.workers.dev") == "placeholder-worker.example.workers.dev")
        #expect(throws: RulesError.self) { try BuildPipeline.normalizeHost("localhost:8787") }
        #expect(throws: RulesError.self) { try BuildPipeline.normalizeHost("bad..host") }
        #expect(throws: RulesError.self) { try BuildPipeline.normalizeHost("-bad.example") }
    }
}
