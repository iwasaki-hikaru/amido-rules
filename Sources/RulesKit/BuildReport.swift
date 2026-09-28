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
            lines.append("| カテゴリ | 拡張 | 入力の行数 | 変換後の件数 | バイト数 | 変換エラー | manifest |")
            lines.append("|---|---|---:|---:|---:|---:|---|")
            for category in categories {
                let converted = category.converter.map { Formatting.count($0.safariRulesCount) } ?? "-"
                let errorsCount = category.converter.map { Formatting.count($0.errorsCount) } ?? "-"
                let bytes = category.bytes > 0 ? Formatting.bytes(category.bytes) : "-"
                lines.append("| \(category.category) | \(category.extensionName ?? "-") | \(Formatting.count(category.inputRuleLines)) | \(converted) | \(bytes) | \(errorsCount) | \(category.included ? "`\(category.file ?? "")`" : "載せない") |")
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
            lines.append("件数はアプリが足す分（許可サイトのルール）を、バイト数はその分の 256 バイトを含みます。")
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
