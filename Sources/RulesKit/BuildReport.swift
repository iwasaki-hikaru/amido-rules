import Foundation

/// build の結果（report.json）。summary.md はここから作る。
public struct BuildReport: Codable, Sendable, Equatable {
    public struct Source: Codable, Sendable, Equatable {
        public var name: String
        public var category: String
        public var enabled: Bool
        public var kind: String
        public var location: String
        public var license: String
        public var attribution: String
        public var cacheFile: String?
        public var fromCache: Bool?
        public var bytes: Int?
        public var sha256: String?
        public var ruleLines: Int?
        public var removedHeaderLines: Int?
        /// 上流のリストの先頭にある「! Licence:」「! Homepage:」などの行。
        public var headerLines: [String] = []
        /// sources.yml の exclude_sections と keep_lines_containing（書いたときだけ）。
        public var excludeSections: String?
        public var keepLinesContaining: String?
        /// 除いた節の見出し。上流が節の名前を変えると、ここが変わる（docs/runbook.md）。
        public var excludedSections: [String]?
        /// 除いたルールの行の数と、除く節の中でも残したルールの行の数。
        public var excludedRuleLines: Int?
        public var keptRuleLines: Int?
    }

    public struct Converter: Codable, Sendable, Equatable {
        public var sourceRulesCount: Int
        public var sourceSafariCompatibleRulesCount: Int
        public var safariRulesCount: Int
        public var advancedRulesCount: Int
        public var discardedSafariRules: Int
        public var errorsCount: Int
        public var seconds: Double
    }

    public struct Category: Codable, Sendable, Equatable {
        public var category: String
        public var extensionName: String?
        public var sources: [String] = []
        public var inputRuleLines: Int = 0
        public var checkRule: String?
        public var converter: Converter?
        public var ruleCount: Int = 0
        public var bytes: Int = 0
        public var sha256: String?
        public var file: String?
        /// manifest に載せたか（0 件のカテゴリは載せない）。
        public var included: Bool = false
        public var lintIssueCount: Int = 0
        /// トップの文書に限った（load-context: top-frame を足した）document の block ルールの数（DocumentRuleScope）。
        public var topFrameDocumentRules: Int?
        /// 拡張の中で 2 番目以降のカテゴリか（例外ルールが前のカテゴリにも効く。docs/format.md）。
        public var laterInExtension: Bool?
        /// 例外ルール（ignore-previous-rules）の数と、そのうちホストだけを限ったもの（`@@||example.com^` の形）の数。
        public var exceptionRules: Int?
        public var hostOnlyExceptionRules: Int?
    }

    public struct CompileEntry: Codable, Sendable, Equatable {
        /// 「extension:basic」か「category:basic」。
        public var target: String
        public var rules: Int
        public var bytes: Int
        public var seconds: Double?
        public var ok: Bool
        public var error: String?
    }

    public struct Compile: Codable, Sendable, Equatable {
        public var skipped: Bool
        public var reason: String?
        public var entries: [CompileEntry] = []
    }

    public struct CountChange: Codable, Sendable, Equatable {
        public var baseline: String?
        public var checked: Bool
        public var reason: String?
        public var allowed: Bool
        public var entries: [CountChangeEntry] = []
    }

    public var ok: Bool = false
    public var generatedAt: String
    public var version: String?
    public var publishedAt: String?
    public var minAppBuild: Int?
    public var host: String?
    public var converterPath: String?
    public var offline: Bool
    public var manifestSHA256: String?
    public var errors: [String] = []
    public var warnings: [String] = []
    public var sources: [Source] = []
    public var categories: [Category] = []
    public var extensions: [ExtensionUsage] = []
    public var compile: Compile?
    public var countChange: CountChange?

    public func encoded() throws -> Data {
        try JSONOutput.encoder().encode(self)
    }

    /// GITHUB_STEP_SUMMARY に足す Markdown。
    public func summaryMarkdown() -> String {
        var lines: [String] = []
        lines.append("## ルールのビルド：\(ok ? "成功" : "失敗")")
        lines.append("")
        lines.append("- 版：`\(version ?? "-")`（\(publishedAt ?? "-")）、min_app_build \(minAppBuild.map(String.init) ?? "-")")
        lines.append("- 配信ホスト（/check 用）：`\(host ?? "-")`")
        lines.append("- エラー \(errors.count) 件、警告 \(warnings.count) 件\(offline ? "（オフライン：キャッシュを使用）" : "")")
        lines.append("")

        if !categories.isEmpty {
            lines.append("### カテゴリ")
            lines.append("")
            lines.append("| カテゴリ | 拡張 | 入力の行数 | 変換後の件数 | バイト数 | 変換エラー | トップの文書に限った件数 | manifest |")
            lines.append("|---|---|---:|---:|---:|---:|---:|---|")
            for category in categories {
                let converted = category.converter.map { Formatting.count($0.safariRulesCount) } ?? "-"
                let errorsCount = category.converter.map { Formatting.count($0.errorsCount) } ?? "-"
                let bytes = category.bytes > 0 ? Formatting.bytes(category.bytes) : "-"
                let scoped = category.topFrameDocumentRules.map { Formatting.count($0) } ?? "-"
                lines.append("| \(category.category) | \(category.extensionName ?? "-") | \(Formatting.count(category.inputRuleLines)) | \(converted) | \(bytes) | \(errorsCount) | \(scoped) | \(category.included ? "`\(category.file ?? "")`" : "載せない") |")
            }
            lines.append("")
        }

        if !extensions.isEmpty {
            lines.append("### 拡張ごとの予算")
            lines.append("")
            lines.append("| 拡張 | カテゴリ | 件数（警告 / 上限） | バイト数（警告 / 上限） | 判定 |")
            lines.append("|---|---|---:|---:|---|")
            for usage in extensions {
                let status = switch usage.status {
                case .ok: "OK"
                case .warning: "警告"
                case .failure: "失敗"
                }
                lines.append("| \(usage.name) | \(usage.categories.map(\.rawValue).joined(separator: " → ")) | \(Formatting.count(usage.rules))（\(Formatting.count(usage.warnRules)) / \(Formatting.count(usage.failRules))） | \(Formatting.bytes(usage.bytes))（\(Formatting.bytes(usage.warnBytes)) / \(Formatting.bytes(usage.failBytes))） | \(status) |")
            }
            lines.append("")
            lines.append("件数とバイト数は、アプリが足す分（許可サイトのルールと自分のルールの上限。config/budgets.json の appReservedRules と appReservedBytes）を含みます。")
            lines.append("")
        }

        if let compile {
            lines.append("### WebKit でのコンパイル（macOS）")
            lines.append("")
            if compile.skipped {
                lines.append("行っていません（\(compile.reason ?? "")）。")
            } else {
                lines.append("| 対象 | 件数 | 時間 | 結果 |")
                lines.append("|---|---:|---:|---|")
                for entry in compile.entries {
                    lines.append("| \(entry.target) | \(Formatting.count(entry.rules)) | \(entry.seconds.map(Formatting.seconds) ?? "-") | \(entry.ok ? "OK" : "失敗：\(entry.error ?? "")") |")
                }
            }
            lines.append("")
        }

        if let countChange {
            lines.append("### 前の版との件数の比較")
            lines.append("")
            if !countChange.checked {
                lines.append("比べていません（\(countChange.reason ?? "")）。")
            } else {
                lines.append("比べた相手：`\(countChange.baseline ?? "-")`\(countChange.allowed ? "（変化を許可して実行）" : "")")
                lines.append("")
                lines.append("| カテゴリ | 前 | 今回 | 変化 | 判定 |")
                lines.append("|---|---:|---:|---:|---|")
                for entry in countChange.entries {
                    let change = entry.percent.map { String(format: "%+.1f%%", $0) } ?? "-"
                    let status = switch entry.status {
                    case .ok: "OK"
                    case .exceeded: "しきい値超え"
                    case .removed: "なくなった"
                    case .added: "新しい"
                    }
                    lines.append("| \(entry.category) | \(entry.previous.map(Formatting.count) ?? "-") | \(entry.current.map(Formatting.count) ?? "-") | \(change) | \(status) |")
                }
            }
            lines.append("")
        }

        let laterCategories = categories.filter { $0.laterInExtension == true && ($0.exceptionRules ?? 0) > 0 }
        if !laterCategories.isEmpty {
            lines.append("### 前のカテゴリにも効く例外ルール")
            lines.append("")
            lines.append("拡張の中で 2 番目以降のカテゴリの例外ルールは、同じ拡張の前のカテゴリにも効きます。すべての URL に効くものは失敗にしています。ホストだけを限ったものは、そのホストのほとんどの読み込みを許します（docs/format.md）。")
            lines.append("")
            lines.append("| カテゴリ | 拡張 | 例外ルール | うちホストだけを限ったもの |")
            lines.append("|---|---|---:|---:|")
            for category in laterCategories {
                lines.append("| \(category.category) | \(category.extensionName ?? "-") | \(Formatting.count(category.exceptionRules ?? 0)) | \(Formatting.count(category.hostOnlyExceptionRules ?? 0)) |")
            }
            lines.append("")
        }

        let enabledSources = sources.filter(\.enabled)
        if !enabledSources.isEmpty {
            lines.append("### ソース")
            lines.append("")
            lines.append("| 名前 | カテゴリ | ライセンス | ルールの行数 | 取得 |")
            lines.append("|---|---|---|---:|---|")
            for source in enabledSources {
                let how = source.kind == "url" ? (source.fromCache == true ? "キャッシュ" : "取得") : "リポジトリ"
                lines.append("| \(source.name) | \(source.category) | \(source.license) | \(source.ruleLines.map(Formatting.count) ?? "-") | \(how) |")
            }
            lines.append("")
            for source in enabledSources {
                guard let sections = source.excludedSections else { continue }
                var text = "- \(source.name)：節を \(sections.count) 個除きました（ルールの行 \(Formatting.count(source.excludedRuleLines ?? 0)) 行）"
                if let keep = source.keepLinesContaining {
                    text += "。除いた節の中でも「\(keep)」を含む \(Formatting.count(source.keptRuleLines ?? 0)) 行は残しています"
                }
                lines.append(text)
            }
            if enabledSources.contains(where: { $0.excludedSections != nil }) {
                lines.append("")
            }
        }

        func list(_ title: String, _ items: [String]) {
            guard !items.isEmpty else { return }
            lines.append("### \(title)（\(items.count) 件）")
            lines.append("")
            for item in items.prefix(50) {
                let text = item.replacingOccurrences(of: "\n", with: "<br>")
                lines.append("- \(text)")
            }
            if items.count > 50 {
                lines.append("- ……ほか \(items.count - 50) 件（report.json を参照）")
            }
            lines.append("")
        }
        list("エラー", errors)
        list("警告", warnings)
        return lines.joined(separator: "\n")
    }
}
