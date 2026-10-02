import Foundation

/// 件数変化の検査のしきい値。両方を超えたときだけ失敗にする。
public struct CountChangeThreshold: Codable, Sendable, Equatable {
    public var relativePercent: Double
    public var absoluteRules: Int

    public init(relativePercent: Double, absoluteRules: Int) {
        self.relativePercent = relativePercent
        self.absoluteRules = absoluteRules
    }
}

/// 拡張 1 つの予算と、入れるカテゴリ（並びは拡張の中での順番）。
public struct ExtensionBudget: Codable, Sendable, Equatable {
    public var categories: [RuleCategory]
    public var warnRules: Int
    public var failRules: Int
    public var warnBytes: Int
    public var failBytes: Int

    public init(categories: [RuleCategory], warnRules: Int, failRules: Int, warnBytes: Int, failBytes: Int) {
        self.categories = categories
        self.warnRules = warnRules
        self.failRules = failRules
        self.warnBytes = warnBytes
        self.failBytes = failBytes
    }
}

/// config/budgets.json。
public struct BudgetsConfig: Codable, Sendable, Equatable {
    /// アプリが許可サイトとして登録できるドメインの上限。
    public var allowlistMaxDomains: Int
    /// アプリが足すルールの件数（許可サイトの 1 件と、自分のルールの上限 userRulesMaxCount）。予算はこの分を空けて確かめる。
    public var appReservedRules: Int
    /// アプリが足すルールのバイト数の上限（許可サイトが allowlistMaxDomains 件のときと、自分のルールの上限
    /// userRulesMaxBytes の合計以上）。予算はこの分を空けて確かめる。
    public var appReservedBytes: Int
    public var countChange: CountChangeThreshold
    public var extensions: [String: ExtensionBudget]
    public var fileSizeLimitBytes: Int
    /// アプリで利用者が足せる「自分のルール」の件数の上限（アプリの Budgets.userRulesMaxCount と同じ値）。
    public var userRulesMaxCount: Int
    /// 自分のルールの合計のバイト数の上限（配列につなぐときの `,` を含む。アプリの Budgets.userRulesMaxBytes と同じ値）。
    public var userRulesMaxBytes: Int

    public init(
        allowlistMaxDomains: Int,
        appReservedRules: Int,
        appReservedBytes: Int,
        countChange: CountChangeThreshold,
        extensions: [String: ExtensionBudget],
        fileSizeLimitBytes: Int,
        userRulesMaxCount: Int,
        userRulesMaxBytes: Int
    ) {
        self.allowlistMaxDomains = allowlistMaxDomains
        self.appReservedRules = appReservedRules
        self.appReservedBytes = appReservedBytes
        self.countChange = countChange
        self.extensions = extensions
        self.fileSizeLimitBytes = fileSizeLimitBytes
        self.userRulesMaxCount = userRulesMaxCount
        self.userRulesMaxBytes = userRulesMaxBytes
    }

    /// 拡張を、最初のカテゴリの順番で並べたもの（basic → plus）。
    public var orderedExtensions: [(name: String, budget: ExtensionBudget)] {
        extensions
            .map { (name: $0.key, budget: $0.value) }
            .sorted { lhs, rhs in
                let l = lhs.budget.categories.first?.order ?? Int.max
                let r = rhs.budget.categories.first?.order ?? Int.max
                return l == r ? lhs.name < rhs.name : l < r
            }
    }

    public func extensionName(containing category: RuleCategory) -> String? {
        orderedExtensions.first { $0.budget.categories.contains(category) }?.name
    }

    /// 拡張の中で最初のカテゴリか。2 番目以降のカテゴリには、すべての URL に効く例外ルールを入れられない（docs/format.md）。
    public func isFirstInExtension(_ category: RuleCategory) -> Bool {
        orderedExtensions.contains { $0.budget.categories.first == category }
    }

    public func validate() throws {
        var problems: [String] = []
        var seen: [RuleCategory: String] = [:]
        for (name, budget) in orderedExtensions {
            if budget.categories.isEmpty {
                problems.append("拡張 \(name) にカテゴリがありません")
            }
            for category in budget.categories {
                if let other = seen[category] {
                    problems.append("カテゴリ \(category.rawValue) が拡張 \(other) と \(name) の両方にあります")
                }
                seen[category] = name
            }
            if budget.warnRules <= 0 || budget.failRules <= 0 || budget.warnBytes <= 0 || budget.failBytes <= 0 {
                problems.append("拡張 \(name) の予算は 1 以上にしてください")
            }
            if budget.warnRules > budget.failRules || budget.warnBytes > budget.failBytes {
                problems.append("拡張 \(name) の警告の値が、失敗の値より大きくなっています")
            }
        }
        for category in RuleCategory.allCases where seen[category] == nil {
            problems.append("カテゴリ \(category.rawValue) がどの拡張にも入っていません")
        }
        if userRulesMaxCount < 0 || userRulesMaxBytes < 0 {
            problems.append("userRulesMaxCount と userRulesMaxBytes は 0 以上にしてください")
        } else if appReservedRules < 1 + userRulesMaxCount {
            problems.append("appReservedRules（\(appReservedRules)）が、許可サイトの 1 件と自分のルールの上限 \(userRulesMaxCount) 件の合計より小さくなっています")
        }
        if allowlistMaxDomains < 0 {
            problems.append("allowlistMaxDomains は 0 以上にしてください")
        } else if userRulesMaxBytes >= 0 {
            let allowlistBytes = RuleConstants.maxAllowlistRuleBytes(domainCount: allowlistMaxDomains)
            if appReservedBytes < allowlistBytes + userRulesMaxBytes {
                problems.append("appReservedBytes（\(appReservedBytes)）が、許可サイト \(allowlistMaxDomains) 件のルールの最大 \(allowlistBytes) バイトと、自分のルールの上限 \(userRulesMaxBytes) バイトの合計より小さくなっています")
            }
        }
        if fileSizeLimitBytes <= 0 {
            problems.append("fileSizeLimitBytes は 1 以上にしてください")
        }
        if countChange.relativePercent < 0 || countChange.absoluteRules < 0 {
            problems.append("countChange の値は 0 以上にしてください")
        }
        if !problems.isEmpty {
            throw RulesError("config/budgets.json が正しくありません：\n" + problems.map { "  - \($0)" }.joined(separator: "\n"))
        }
    }
}

/// config/denylist.json。URL にこれらの文字列を含むソースは使わない。
public struct Denylist: Codable, Sendable, Equatable {
    public var urlSubstrings: [String]

    public init(urlSubstrings: [String]) {
        self.urlSubstrings = urlSubstrings
    }

    /// 当たった文字列（大文字と小文字は区別しない）。
    public func match(_ text: String) -> String? {
        let lowered = text.lowercased()
        return urlSubstrings.first { !$0.isEmpty && lowered.contains($0.lowercased()) }
    }
}

/// config/distribution.json。
public struct DistributionConfig: Codable, Sendable, Equatable {
    public var host: String
    public var minAppBuild: Int

    public init(host: String, minAppBuild: Int) {
        self.host = host
        self.minAppBuild = minAppBuild
    }
}

/// config/ ディレクトリの設定一式。
public struct RulesConfig: Sendable, Equatable {
    public var budgets: BudgetsConfig
    public var denylist: Denylist
    public var distribution: DistributionConfig

    public init(budgets: BudgetsConfig, denylist: Denylist, distribution: DistributionConfig) {
        self.budgets = budgets
        self.denylist = denylist
        self.distribution = distribution
    }

    public static func load(from directory: URL) throws -> RulesConfig {
        let budgets: BudgetsConfig = try decode("budgets.json", in: directory)
        try budgets.validate()
        let denylist: Denylist = try decode("denylist.json", in: directory)
        let distribution: DistributionConfig = try decode("distribution.json", in: directory)
        if distribution.minAppBuild < 1 {
            throw RulesError("config/distribution.json の minAppBuild は 1 以上にしてください")
        }
        return RulesConfig(budgets: budgets, denylist: denylist, distribution: distribution)
    }

    static func decode<T: Decodable>(_ name: String, in directory: URL) throws -> T {
        let url = directory.appending(path: name)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RulesError("\(url.path(percentEncoded: false)) を読めません：\(error.localizedDescription)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RulesError("\(url.path(percentEncoded: false)) の形式が正しくありません：\(describe(error))")
        }
    }
}

/// デコードのエラーを、どのキーで何が起きたかがわかる短い文にする。
func describe(_ error: any Error) -> String {
    guard let error = error as? DecodingError else {
        return error.localizedDescription
    }
    func path(_ context: DecodingError.Context) -> String {
        let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
        return keys.isEmpty ? "（最上位）" : keys.joined(separator: ".")
    }
    switch error {
    case .keyNotFound(let key, let context):
        return "\(path(context)) に「\(key.stringValue)」がありません"
    case .typeMismatch(_, let context), .valueNotFound(_, let context):
        return "\(path(context)) の型が違います（\(context.debugDescription)）"
    case .dataCorrupted(let context):
        return "\(path(context))：\(context.debugDescription)"
    @unknown default:
        return error.localizedDescription
    }
}
