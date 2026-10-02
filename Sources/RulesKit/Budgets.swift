import Foundation

/// カテゴリのリストを、拡張に渡す 1 つの配列につなぐ（アプリの RuleComposer と同じく、バイト単位でつなぐ）。
public enum RuleListJoin {
    public static func join(_ lists: [Data], appending extraRules: [String] = []) throws -> Data {
        var parts: [Data] = []
        for list in lists {
            parts.append(try innerElements(of: list))
        }
        parts += extraRules.map { Data($0.utf8) }
        parts.removeAll { $0.isEmpty }
        var result = Data("[".utf8)
        for (index, part) in parts.enumerated() {
            if index > 0 {
                result.append(UInt8(ascii: ","))
            }
            result.append(part)
        }
        result.append(UInt8(ascii: "]"))
        return result
    }

    /// `[` と `]` の内側。前後の空白は除く。
    static func innerElements(of list: Data) throws -> Data {
        let whitespace: Set<UInt8> = [0x20, 0x09, 0x0A, 0x0D]
        var start = list.startIndex
        var end = list.endIndex
        while start < end, whitespace.contains(list[start]) { start += 1 }
        while end > start, whitespace.contains(list[end - 1]) { end -= 1 }
        guard end - start >= 2, list[start] == UInt8(ascii: "["), list[end - 1] == UInt8(ascii: "]") else {
            throw RulesError("リストが JSON の配列ではありません")
        }
        var innerStart = start + 1
        var innerEnd = end - 1
        while innerStart < innerEnd, whitespace.contains(list[innerStart]) { innerStart += 1 }
        while innerEnd > innerStart, whitespace.contains(list[innerEnd - 1]) { innerEnd -= 1 }
        return list.subdata(in: innerStart..<innerEnd)
    }
}

public enum BudgetStatus: String, Codable, Sendable {
    case ok
    case warning
    case failure
}

/// 拡張 1 つの使用量と予算。
public struct ExtensionUsage: Codable, Sendable, Equatable {
    public var name: String
    public var categories: [RuleCategory]
    /// カテゴリの合計に、アプリが足す分（appReservedRules）を加えた件数。
    public var rules: Int
    /// カテゴリのファイルの合計に、アプリが足すルール（許可サイトと自分のルール）の分（appReservedBytes）を加えたバイト数。
    public var bytes: Int
    public var warnRules: Int
    public var failRules: Int
    public var warnBytes: Int
    public var failBytes: Int
    public var status: BudgetStatus
}

public struct ListMeasure: Sendable, Equatable {
    public var rules: Int
    public var bytes: Int

    public init(rules: Int, bytes: Int) {
        self.rules = rules
        self.bytes = bytes
    }
}

public struct BudgetEvaluation: Sendable, Equatable {
    public var usages: [ExtensionUsage] = []
    public var errors: [String] = []
    public var warnings: [String] = []
}

/// 拡張ごとの件数とバイト数の予算（config/budgets.json）を確かめる。
///
/// 実機の Safari は、WebKit の上限（15 万件）よりずっと少ない件数やサイズで失敗することがあるので、
/// 件数とバイト数の両方で見る。1 ファイルの大きさは、配信の上限（25 MiB 未満）として別に見る。
public enum BudgetCheck {
    public static func evaluate(config: BudgetsConfig, lists: [RuleCategory: ListMeasure]) -> BudgetEvaluation {
        var result = BudgetEvaluation()
        for (name, budget) in config.orderedExtensions {
            let present = budget.categories.compactMap { lists[$0] }
            let rules = present.reduce(0) { $0 + $1.rules } + config.appReservedRules
            let bytes = present.reduce(0) { $0 + $1.bytes } + config.appReservedBytes
            var status = BudgetStatus.ok
            if rules > budget.failRules {
                status = .failure
                result.errors.append("拡張 \(name) の件数 \(Formatting.count(rules)) が上限 \(Formatting.count(budget.failRules)) を超えています")
            } else if rules > budget.warnRules {
                status = .warning
                result.warnings.append("拡張 \(name) の件数 \(Formatting.count(rules)) が警告の値 \(Formatting.count(budget.warnRules)) を超えています")
            }
            if bytes > budget.failBytes {
                status = .failure
                result.errors.append("拡張 \(name) のバイト数 \(Formatting.bytes(bytes)) が上限 \(Formatting.bytes(budget.failBytes)) を超えています")
            } else if bytes > budget.warnBytes {
                if status == .ok { status = .warning }
                result.warnings.append("拡張 \(name) のバイト数 \(Formatting.bytes(bytes)) が警告の値 \(Formatting.bytes(budget.warnBytes)) を超えています")
            }
            result.usages.append(ExtensionUsage(
                name: name,
                categories: budget.categories,
                rules: rules,
                bytes: bytes,
                warnRules: budget.warnRules,
                failRules: budget.failRules,
                warnBytes: budget.warnBytes,
                failBytes: budget.failBytes,
                status: status
            ))
        }
        for category in RuleCategory.allCases {
            if let measure = lists[category], measure.bytes >= config.fileSizeLimitBytes {
                result.errors.append("\(category.rawValue) のファイル（\(Formatting.bytes(measure.bytes))）が配信の上限 \(Formatting.bytes(config.fileSizeLimitBytes)) 以上です")
            }
        }
        return result
    }
}

/// 前の版からの件数の変化。
public struct CountChangeEntry: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case ok
        case exceeded
        case removed
        case added
    }

    public var category: String
    public var previous: Int?
    public var current: Int?
    public var delta: Int?
    public var percent: Double?
    public var status: Status
}

public struct CountChangeEvaluation: Sendable, Equatable {
    public var entries: [CountChangeEntry] = []
    public var errors: [String] = []
    public var warnings: [String] = []
}

/// 件数の急な変化（上流の事故など）を止める。
///
/// 変化が relativePercent % を超え、**かつ** absoluteRules 件を超えたときだけ失敗にする（小さいリストの
/// 数件の増減で止めないため）。カテゴリがなくなったときも失敗にする。新しいカテゴリは比べない。
/// `allow` のとき（手動実行で許可したとき）は、失敗の代わりに警告にする。
public enum CountChangeCheck {
    public static func evaluate(
        previous: [String: Int],
        current: [RuleCategory: Int],
        threshold: CountChangeThreshold,
        allow: Bool
    ) -> CountChangeEvaluation {
        var result = CountChangeEvaluation()
        func report(_ message: String) {
            if allow {
                result.warnings.append(message + "（--allow-count-change で許可）")
            } else {
                result.errors.append(message + "。意図した変化なら --allow-count-change を付けて流し直してください")
            }
        }

        var names = Set(previous.keys)
        names.formUnion(current.keys.map(\.rawValue))
        let ordered = names.sorted { lhs, rhs in
            let l = RuleCategory(rawValue: lhs)?.order ?? Int.max
            let r = RuleCategory(rawValue: rhs)?.order ?? Int.max
            return l == r ? lhs < rhs : l < r
        }
        for name in ordered {
            let old = previous[name]
            let new = RuleCategory(rawValue: name).flatMap { current[$0] }
            switch (old, new) {
            case (let old?, let new?):
                let delta = new - old
                let percent = old > 0 ? Double(delta) * 100 / Double(old) : 0
                let exceeded = delta.magnitude > UInt(max(threshold.absoluteRules, 0))
                    && Double(delta.magnitude) * 100 > threshold.relativePercent * Double(old)
                result.entries.append(CountChangeEntry(
                    category: name, previous: old, current: new, delta: delta, percent: percent,
                    status: exceeded ? .exceeded : .ok
                ))
                if exceeded {
                    report("\(name) の件数が \(Formatting.count(old)) から \(Formatting.count(new)) に変わりました（\(String(format: "%+.1f", percent))%、\(delta > 0 ? "+" : "")\(Formatting.count(delta)) 件）")
                }
            case (let old?, nil):
                result.entries.append(CountChangeEntry(
                    category: name, previous: old, current: nil, delta: -old, percent: -100, status: .removed
                ))
                report("\(name) が前の版にはありましたが、今回はありません（\(Formatting.count(old)) 件 → 0 件）")
            case (nil, let new?):
                result.entries.append(CountChangeEntry(
                    category: name, previous: nil, current: new, delta: nil, percent: nil, status: .added
                ))
            case (nil, nil):
                break
            }
        }
        return result
    }
}
