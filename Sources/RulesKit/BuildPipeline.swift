import Foundation

/// build コマンドの指定。
public struct BuildOptions: Sendable {
    public var converter: URL
    public var outDirectory: URL
    public var sourcesFile: URL
    public var configDirectory: URL
    /// /check 用のルールに使う配信ホスト。nil なら config/distribution.json の値。
    public var host: String?
    /// nil なら、その日（UTC）の「YYYY.MM.DD.1」。
    public var version: String?
    /// nil なら今の時刻。
    public var publishedAt: String?
    /// 上流のリストを取得せず、build/sources のキャッシュを使う（なければ失敗）。
    public var offline: Bool
    /// 件数の比較に使う前の manifest（URL かパス）。
    public var previousManifest: String?
    public var allowCountChange: Bool
    public var skipCompileCheck: Bool
    public var now: Date
    /// 上流のリストのキャッシュ（build/sources）。
    public var cacheDirectory: URL
    /// 変換に渡す入力を置く場所（build/work）。確認しやすいように残す。
    public var workDirectory: URL

    public init(
        converter: URL,
        outDirectory: URL,
        sourcesFile: URL,
        configDirectory: URL,
        host: String? = nil,
        version: String? = nil,
        publishedAt: String? = nil,
        offline: Bool = false,
        previousManifest: String? = nil,
        allowCountChange: Bool = false,
        skipCompileCheck: Bool = false,
        now: Date = Date(),
        cacheDirectory: URL? = nil,
        workDirectory: URL? = nil
    ) {
        let root = sourcesFile.deletingLastPathComponent()
        self.converter = converter
        self.outDirectory = outDirectory
        self.sourcesFile = sourcesFile
        self.configDirectory = configDirectory
        self.host = host
        self.version = version
        self.publishedAt = publishedAt
        self.offline = offline
        self.previousManifest = previousManifest
        self.allowCountChange = allowCountChange
        self.skipCompileCheck = skipCompileCheck
        self.now = now
        self.cacheDirectory = cacheDirectory ?? root.appending(path: "build/sources")
        self.workDirectory = workDirectory ?? root.appending(path: "build/work")
    }

    /// sources.yml のあるディレクトリ（リポジトリのルート）。path のソースはここからの相対パス。
    public var rootDirectory: URL {
        sourcesFile.deletingLastPathComponent()
    }
}

/// ルールを取得・変換・検査して、manifest とリストを書く（docs/format.md）。
///
/// 検査の失敗はできるだけ最後まで集めて report.json と summary.md に書く。
/// エラーが 1 件でもあれば、manifest とリストは書かない。
@MainActor
public final class BuildPipeline {
    public static func run(_ options: BuildOptions, log: @escaping (String) -> Void = { _ in }) async -> BuildReport {
        let pipeline = BuildPipeline(options: options, log: log)
        await pipeline.execute()
        return pipeline.report
    }

    let options: BuildOptions
    let log: (String) -> Void
    var report: BuildReport
    var outputs: [RuleCategory: Data] = [:]
    var measures: [RuleCategory: ListMeasure] = [:]

    init(options: BuildOptions, log: @escaping (String) -> Void) {
        self.options = options
        self.log = log
        self.report = BuildReport(
            generatedAt: ManifestFormat.formatPublishedAt(options.now),
            offline: options.offline
        )
    }

    func execute() async {
        do {
            try await stages()
        } catch {
            report.errors.append(error.localizedDescription)
        }
        report.ok = report.errors.isEmpty
        do {
            try FileIO.write(try report.encoded(), to: options.outDirectory.appending(path: "report.json"))
            try FileIO.write(Data(report.summaryMarkdown().utf8), to: options.outDirectory.appending(path: "summary.md"))
        } catch {
            report.errors.append("report.json と summary.md を書けません：\(error.localizedDescription)")
            report.ok = false
        }
    }

    func stages() async throws {
        let config = try RulesConfig.load(from: options.configDirectory)
        let host = try Self.normalizeHost(options.host ?? config.distribution.host)
        report.host = host
        if host.contains("placeholder") {
            report.warnings.append("配信ホスト「\(host)」は仮の値です。/check 用のルールは、本番のホストに合いません（config/distribution.json）")
        }
        let version = options.version ?? ManifestFormat.defaultVersion(for: options.now)
        guard ManifestFormat.isValidVersion(version) else {
            throw RulesError("版「\(version)」が YYYY.MM.DD.N の形ではありません")
        }
        let publishedAt: String
        if let text = options.publishedAt {
            guard let normalized = ManifestFormat.normalizePublishedAt(text) else {
                throw RulesError("公開日時「\(text)」が RFC 3339 の形ではありません（例 2026-10-05T03:00:00Z）")
            }
            publishedAt = normalized
        } else {
            publishedAt = ManifestFormat.formatPublishedAt(options.now)
        }
        report.version = version
        report.publishedAt = publishedAt
        report.minAppBuild = config.distribution.minAppBuild
        report.converterPath = options.converter.path(percentEncoded: false)

        guard FileManager.default.isExecutableFile(atPath: options.converter.path(percentEncoded: false)) else {
            throw RulesError("変換器が見つからないか、実行できません：\(options.converter.path(percentEncoded: false))（scripts/fetch-converter.sh でビルドしてください）")
        }

        let sources = try SourcesFile.load(from: options.sourcesFile, denylist: config.denylist)
        let texts = try await loadSources(sources)
        try await convertCategories(texts, host: host, config: config)

        let budget = BudgetCheck.evaluate(config: config.budgets, lists: measures)
        report.extensions = budget.usages
        report.errors += budget.errors
        report.warnings += budget.warnings

        if options.skipCompileCheck {
            report.compile = BuildReport.Compile(skipped: true, reason: "--skip-compile-check を指定")
        } else {
            report.compile = await compileCheck(config: config)
        }

        await checkCountChange(config: config)

        guard report.errors.isEmpty else {
            log("エラーがあるので、manifest とリストは書きません")
            return
        }
        try writeDistribution(version: version, publishedAt: publishedAt, config: config)
    }

    // MARK: - ソース

    /// 有効なソースを読み、カテゴリごとに（名前, 見出しを除いたテキスト）を並べる。
    func loadSources(_ sources: [SourceEntry]) async throws -> [RuleCategory: [(name: String, text: String)]] {
        var texts: [RuleCategory: [(name: String, text: String)]] = [:]
        var loadFailures: [String] = []
        for source in sources {
            var entry = BuildReport.Source(
                name: source.name,
                category: source.category.rawValue,
                enabled: source.enabled,
                kind: { if case .url = source.origin { return "url" } else { return "path" } }(),
                location: source.locationDescription,
                license: source.license,
                attribution: source.attribution
            )
            guard source.enabled else {
                report.sources.append(entry)
                continue
            }
            do {
                let data = try await loadData(of: source, into: &entry)
                entry.bytes = data.count
                entry.sha256 = Hashing.sha256Hex(data)
                let text = try FileIO.decodeText(data, displayName: source.locationDescription)
                if source.isCustom {
                    report.errors += SourceText.lintCustomRules(text, fileName: source.locationDescription)
                }
                let stripped = SourceText.stripAdblockHeaders(text)
                entry.removedHeaderLines = stripped.removedLines
                entry.ruleLines = SourceText.countRuleLines(stripped.text)
                if case .url = source.origin {
                    entry.headerLines = SourceText.headerLines(text)
                }
                texts[source.category, default: []].append((source.name, stripped.text))
            } catch {
                loadFailures.append("\(source.name)：\(error.localizedDescription)")
            }
            report.sources.append(entry)
        }
        // 読めなかったソースがあると件数が大きく変わり、ほかの検査の結果も紛らわしくなるので、ここで止める
        guard loadFailures.isEmpty else {
            throw RulesError("ソースを読めません：\n" + loadFailures.map { "  - \($0)" }.joined(separator: "\n"))
        }
        return texts
    }

    func loadData(of source: SourceEntry, into entry: inout BuildReport.Source) async throws -> Data {
        switch source.origin {
        case .url(let url):
            let cacheFile = options.cacheDirectory.appending(path: "\(source.slug).txt")
            entry.cacheFile = display(cacheFile)
            if options.offline {
                guard FileIO.exists(cacheFile) else {
                    throw RulesError("オフラインで実行していますが、キャッシュ \(display(cacheFile)) がありません")
                }
                log("キャッシュを使います：\(source.name)（\(display(cacheFile))）")
                entry.fromCache = true
                return try Data(contentsOf: cacheFile)
            }
            log("取得しています：\(source.name)（\(url.absoluteString)）")
            entry.fromCache = false
            return try await ResourceLoader.fetchSource(url, cacheFile: cacheFile)
        case .path(let path):
            let file = options.rootDirectory.appending(path: path)
            guard FileIO.exists(file) else {
                throw RulesError("\(path) がありません")
            }
            return try Data(contentsOf: file)
        }
    }

    // MARK: - 変換と検査

    func convertCategories(
        _ texts: [RuleCategory: [(name: String, text: String)]],
        host: String,
        config: RulesConfig
    ) async throws {
        let runner = ConverterRunner(executable: options.converter)
        let clock = ContinuousClock()
        for category in RuleCategory.allCases {
            var item = BuildReport.Category(
                category: category.rawValue,
                extensionName: config.budgets.extensionName(containing: category)
            )
            let parts = texts[category] ?? []
            item.sources = parts.map(\.name)
            var input = parts.map(\.text).joined()
            if let checkRule = category.checkRule(host: host) {
                input += "! 動作確認ページ（/check）用のルール。ツールが自動で足す\n\(checkRule)\n"
                item.checkRule = checkRule
            }
            item.inputRuleLines = SourceText.countRuleLines(input)
            guard item.inputRuleLines > 0 else {
                log("\(category.rawValue)：ルールがないので manifest に載せません")
                report.categories.append(item)
                continue
            }

            let inputFile = options.workDirectory.appending(path: "\(category.rawValue).txt")
            try FileIO.write(Data(input.utf8), to: inputFile)
            log("変換しています：\(category.rawValue)（ルール \(Formatting.count(item.inputRuleLines)) 行）")
            let start = clock.now
            let result = try await runner.convert(inputFile: inputFile)
            let elapsed = clock.now - start
            item.converter = BuildReport.Converter(
                sourceRulesCount: result.sourceRulesCount,
                sourceSafariCompatibleRulesCount: result.sourceSafariCompatibleRulesCount,
                safariRulesCount: result.safariRulesCount,
                advancedRulesCount: result.advancedRulesCount,
                discardedSafariRules: result.discardedSafariRules,
                errorsCount: result.errorsCount,
                seconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            )
            if result.discardedSafariRules > 0 {
                report.errors.append("\(category.rawValue)：変換器が \(Formatting.count(result.discardedSafariRules)) 件のルールを捨てました（上限を超えた分。末尾の例外ルールから捨てられる）")
            }
            if result.errorsCount > 0 {
                report.warnings.append("\(category.rawValue)：変換できなかったルールが \(Formatting.count(result.errorsCount)) 件あります（変換器の errorsCount。そのルールは入らない）")
            }
            guard result.safariRulesCount > 0 else {
                // 0 件のとき、変換器は独自のルール（domain.com の ignore-previous-rules）を出すが、それは使わない
                report.warnings.append("\(category.rawValue)：変換後のルールが 0 件なので、manifest に載せません")
                report.categories.append(item)
                continue
            }

            let data = Data(result.safariRulesJSON.utf8)
            let lint = RuleListLint.lint(data, forbidExceptions: !config.budgets.isFirstInExtension(category))
            item.lintIssueCount = lint.issueCount
            report.errors += lint.issues.map { "\(category.rawValue)：\($0)" }
            if lint.issueCount > lint.issues.count {
                report.errors.append("\(category.rawValue)：ほかに \(Formatting.count(lint.issueCount - lint.issues.count)) 件の問題があります")
            }
            if lint.ruleCount > 0, lint.ruleCount != result.safariRulesCount {
                report.errors.append("\(category.rawValue)：配列の要素数 \(lint.ruleCount) が、変換器の safariRulesCount \(result.safariRulesCount) と合いません")
            }
            if let className = category.checkClassName, lint.ruleCount > 0,
               !Self.containsCheckRule(data, host: host, className: className) {
                report.errors.append("\(category.rawValue)：/check 用のルール（\(host)##.\(className)）が変換結果に見つかりません")
            }

            let sha256 = Hashing.sha256Hex(data)
            item.ruleCount = lint.ruleCount
            item.bytes = data.count
            item.sha256 = sha256
            item.file = ManifestFormat.listPath(category: category, sha256: sha256)
            item.included = lint.ruleCount > 0
            if lint.ruleCount > 0 {
                measures[category] = ListMeasure(rules: lint.ruleCount, bytes: data.count)
                outputs[category] = data
            }
            log("\(category.rawValue)：\(Formatting.count(lint.ruleCount)) 件、\(Formatting.bytes(data.count))")
            report.categories.append(item)
        }
    }

    /// 変換結果に、/check 用のルール（そのホストだけで要素を隠すルール）があるか。
    /// 変換器は同じドメインの要素隠しをまとめることがあるので、セレクタは「,」で分けて探す。
    static func containsCheckRule(_ data: Data, host: String, className: String) -> Bool {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return rules.contains { rule in
            guard let trigger = rule["trigger"] as? [String: Any],
                  let action = rule["action"] as? [String: Any],
                  action["type"] as? String == "css-display-none",
                  let selector = action["selector"] as? String,
                  let domains = trigger["if-domain"] as? [String]
            else {
                return false
            }
            let selectors = selector.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return selectors.contains(".\(className)") && (domains.contains("*\(host)") || domains.contains(host))
        }
    }

    // MARK: - コンパイル

    func compileCheck(config: RulesConfig) async -> BuildReport.Compile {
        #if canImport(WebKit)
        var entries: [BuildReport.CompileEntry] = []
        for (name, budget) in config.budgets.orderedExtensions {
            let lists = budget.categories.compactMap { outputs[$0] }
            let rules = budget.categories.compactMap { measures[$0]?.rules }.reduce(0, +)
            // 拡張に渡す形：カテゴリを順につなぎ、末尾に許可サイトのルールを足す（ルールがなければダミー）
            let extras = lists.isEmpty
                ? [RuleConstants.dummyRuleJSON, RuleConstants.sampleAllowlistRuleJSON]
                : [RuleConstants.sampleAllowlistRuleJSON]
            do {
                let joined = try RuleListJoin.join(lists, appending: extras)
                entries.append(await compileEntry(target: "extension:\(name)", data: joined, rules: rules + extras.count))
            } catch {
                report.errors.append("拡張 \(name) のリストをつなげません：\(error.localizedDescription)")
            }
        }
        for category in RuleCategory.allCases {
            guard let data = outputs[category], let measure = measures[category] else { continue }
            entries.append(await compileEntry(target: "category:\(category.rawValue)", data: data, rules: measure.rules))
        }
        return BuildReport.Compile(skipped: false, reason: nil, entries: entries)
        #else
        report.warnings.append("WebKit がない環境なので、コンパイルの確認をしていません")
        return BuildReport.Compile(skipped: true, reason: "WebKit がない環境")
        #endif
    }

    #if canImport(WebKit)
    func compileEntry(target: String, data: Data, rules: Int) async -> BuildReport.CompileEntry {
        log("コンパイルしています：\(target)（\(Formatting.count(rules)) 件）")
        do {
            let seconds = try await CompileChecker.compile(data, identifier: target.replacingOccurrences(of: ":", with: "-"))
            log("  \(Formatting.seconds(seconds))")
            return BuildReport.CompileEntry(target: target, rules: rules, bytes: data.count, seconds: seconds, ok: true, error: nil)
        } catch {
            report.errors.append("\(target) を WebKit でコンパイルできません：\(error.localizedDescription)")
            return BuildReport.CompileEntry(
                target: target, rules: rules, bytes: data.count, seconds: nil, ok: false,
                error: error.localizedDescription
            )
        }
    }
    #endif

    // MARK: - 件数の比較

    func checkCountChange(config: RulesConfig) async {
        let allowed = options.allowCountChange
        guard let previous = options.previousManifest else {
            report.countChange = BuildReport.CountChange(
                baseline: nil, checked: false, reason: "--previous-manifest の指定なし", allowed: allowed
            )
            return
        }
        do {
            let location = try ResourceLocation.parse(previous)
            switch try await ResourceLoader.load(location) {
            case .missing:
                log("前の manifest がないので、件数は比べません（初回の配信）")
                report.countChange = BuildReport.CountChange(
                    baseline: previous, checked: false, reason: "前の manifest がない（初回の配信）", allowed: allowed
                )
            case .data(let data):
                let manifest = try Manifest.decode(data)
                var counts: [String: Int] = [:]
                for entry in manifest.lists where counts[entry.category] == nil {
                    counts[entry.category] = entry.ruleCount
                }
                let evaluation = CountChangeCheck.evaluate(
                    previous: counts,
                    current: measures.mapValues(\.rules),
                    threshold: config.budgets.countChange,
                    allow: allowed
                )
                report.errors += evaluation.errors
                report.warnings += evaluation.warnings
                report.countChange = BuildReport.CountChange(
                    baseline: previous, checked: true, reason: nil, allowed: allowed, entries: evaluation.entries
                )
            }
        } catch {
            let message = "前の manifest（\(previous)）を読めません：\(error.localizedDescription)"
            if allowed {
                report.warnings.append(message + "（--allow-count-change のため続けます）")
            } else {
                report.errors.append(message + "。件数を比べられないので止めます（意図したものなら --allow-count-change）")
            }
            report.countChange = BuildReport.CountChange(
                baseline: previous, checked: false, reason: "前の manifest を読めない", allowed: allowed
            )
        }
    }

    // MARK: - 出力

    func writeDistribution(version: String, publishedAt: String, config: RulesConfig) throws {
        let v1 = options.outDirectory.appending(path: "v1")
        if FileIO.exists(v1) {
            try FileManager.default.removeItem(at: v1)
        }
        var entries: [Manifest.Entry] = []
        for category in RuleCategory.allCases {
            guard let data = outputs[category], let measure = measures[category] else { continue }
            let sha256 = Hashing.sha256Hex(data)
            let path = ManifestFormat.listPath(category: category, sha256: sha256)
            try FileIO.write(data, to: v1.appending(path: path))
            entries.append(Manifest.Entry(
                category: category.rawValue, url: path, sha256: sha256, size: data.count, ruleCount: measure.rules
            ))
        }
        guard !entries.isEmpty else {
            report.errors.append("配信するリストが 1 つもありません（すべてのカテゴリが 0 件）")
            try? FileManager.default.removeItem(at: v1)
            return
        }
        let manifest = Manifest(
            version: version, publishedAt: publishedAt, minAppBuild: config.distribution.minAppBuild, lists: entries
        )
        let problems = manifest.problems(fileSizeLimitBytes: config.budgets.fileSizeLimitBytes)
        guard problems.isEmpty else {
            report.errors += problems.map { "manifest：\($0)" }
            try? FileManager.default.removeItem(at: v1)
            return
        }
        let data = try manifest.encoded()
        try FileIO.write(data, to: v1.appending(path: "manifest.json"))
        report.manifestSHA256 = Hashing.sha256Hex(data)
        log("書きました：\(display(v1.appending(path: "manifest.json")))（署名はまだ。sign コマンドで署名する）")
    }

    // MARK: - 補助

    /// 表示用：ルートの下なら相対パスにする。
    func display(_ url: URL) -> String {
        let root = options.rootDirectory.standardizedFileURL.path(percentEncoded: false)
        let path = url.standardizedFileURL.path(percentEncoded: false)
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
    }

    /// 配信ホストを小文字にして確かめる（WebKit の if-domain は小文字だけを受け付ける）。
    public static func normalizeHost(_ text: String) throws -> String {
        let host = text.trimmingCharacters(in: .whitespaces).lowercased()
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let valid = !host.isEmpty && labels.allSatisfy { label in
            !label.isEmpty && label.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.unicodeScalars.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }
        guard valid else {
            throw RulesError("配信ホスト「\(text)」が正しいホスト名ではありません（英数字・-・. だけ、ポートは付けない）")
        }
        return host
    }
}
