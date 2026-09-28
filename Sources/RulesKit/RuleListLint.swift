import Foundation

/// 検査の結果。問題は先頭から `maxIssues` 件まで持ち、総数は `issueCount` に数える。
public struct LintReport: Sendable, Equatable {
    public var ruleCount: Int
    public var issues: [String]
    public var issueCount: Int

    public var isValid: Bool { issueCount == 0 }
}

/// 変換後のリスト（Safari のコンテンツブロッカーの JSON）の検査。
///
/// 対象は iOS 17（Safari 16.4〜17）の WebKit。1 件でも読めないルールがあると、Safari はリスト全体を
/// 読み込まない（WKErrorDomain 6）。また、古い WebKit は知らないキーを黙って無視するので、
/// 新しい Safari 専用のキーがあると、条件が外れて広く当たりすぎる。どちらも配信の前に止める。
/// 問題は `rules[番号]`（0 始まり）で示す。
public enum RuleListLint {
    /// 1 つの trigger に 1 つだけ書ける条件のキー（WebKit の ContentExtensionParser）。
    public static let conditionKeys = [
        "if-domain", "unless-domain", "if-top-url", "unless-top-url", "if-frame-url", "unless-frame-url",
    ]
    /// Safari 26 から。iOS 17 では無視され、条件なしのルールになってしまう。
    public static let safari26OnlyTriggerKeys: Set<String> = [
        "if-frame-url", "unless-frame-url", "frame-url-filter-is-case-sensitive", "request-method",
    ]
    public static let allowedTriggerKeys: Set<String> = [
        "url-filter", "url-filter-is-case-sensitive", "if-domain", "unless-domain", "resource-type",
        "load-type", "if-top-url", "unless-top-url", "top-url-filter-is-case-sensitive", "load-context",
    ]
    public static let allowedActionTypes: Set<String> = [
        "block", "block-cookies", "css-display-none", "ignore-previous-rules", "make-https",
    ]
    public static let allowedActionKeys: Set<String> = ["type", "selector"]
    public static let allowedResourceTypes: Set<String> = [
        "document", "image", "style-sheet", "script", "font", "raw", "svg-document", "media", "popup",
        "ping", "fetch", "websocket", "other",
    ]
    public static let safari26OnlyResourceTypes: Set<String> = ["top-document", "child-document"]
    public static let allowedLoadTypes: Set<String> = ["first-party", "third-party"]
    public static let allowedLoadContexts: Set<String> = ["top-frame", "child-frame"]

    /// - Parameter forbidExceptions: 拡張の中で 2 番目以降のカテゴリ（scam）なら true。
    ///   `ignore-previous-rules` が前のカテゴリのルールまで打ち消してしまうため、1 件でもあれば失敗にする。
    public static func lint(_ data: Data, forbidExceptions: Bool, maxIssues: Int = 200) -> LintReport {
        let json: Any
        do {
            json = try JSONSerialization.jsonObject(with: data)
        } catch {
            return LintReport(ruleCount: 0, issues: ["JSON として読めません：\(error.localizedDescription)"], issueCount: 1)
        }
        guard let rules = json as? [Any] else {
            return LintReport(ruleCount: 0, issues: ["最上位が配列ではありません"], issueCount: 1)
        }
        guard !rules.isEmpty else {
            return LintReport(ruleCount: 0, issues: ["空の配列です（Safari は読み込めない）"], issueCount: 1)
        }
        var report = LintReport(ruleCount: rules.count, issues: [], issueCount: 0)
        for (index, rule) in rules.enumerated() {
            for problem in problems(in: rule, forbidExceptions: forbidExceptions) {
                report.issueCount += 1
                if report.issues.count < maxIssues {
                    report.issues.append("rules[\(index)]: \(problem)")
                }
            }
        }
        return report
    }

    /// ルール 1 件の問題。
    public static func problems(in rule: Any, forbidExceptions: Bool) -> [String] {
        guard let rule = rule as? [String: Any] else {
            return ["オブジェクトではありません"]
        }
        var problems: [String] = []
        for key in rule.keys.sorted() where key != "trigger" && key != "action" {
            problems.append("知らないキー「\(key)」があります")
        }
        if let trigger = rule["trigger"] as? [String: Any] {
            problems += triggerProblems(trigger)
        } else {
            problems.append("trigger がないか、オブジェクトではありません")
        }
        if let action = rule["action"] as? [String: Any] {
            problems += actionProblems(action, forbidExceptions: forbidExceptions)
        } else {
            problems.append("action がないか、オブジェクトではありません")
        }
        return problems
    }

    static func triggerProblems(_ trigger: [String: Any]) -> [String] {
        var problems: [String] = []
        for key in trigger.keys.sorted() where !allowedTriggerKeys.contains(key) {
            if safari26OnlyTriggerKeys.contains(key) {
                problems.append("trigger の「\(key)」は Safari 26 からのキーです（iOS 17 では無視され、条件なしのルールになる）")
            } else {
                problems.append("trigger に知らないキー「\(key)」があります")
            }
        }

        if let filter = trigger["url-filter"] as? String, !filter.isEmpty {
            if let problem = urlFilterProblem(filter) {
                problems.append("url-filter \(quoted(filter))：\(problem)")
            }
        } else {
            problems.append("url-filter がないか、空です")
        }

        let conditions = conditionKeys.filter { trigger[$0] != nil }
        if conditions.count > 1 {
            problems.append("条件のキーが \(conditions.count) つあります（\(conditions.joined(separator: "・"))）。WebKit は 1 つの trigger に 1 つだけ許す")
        }

        for key in ["if-domain", "unless-domain"] {
            guard let value = trigger[key] else { continue }
            guard let domains = value as? [Any], !domains.isEmpty else {
                problems.append("\(key) が空でない配列ではありません")
                continue
            }
            for domain in domains {
                if let problem = domainProblem(domain) {
                    problems.append("\(key) の \(quoted(domain))：\(problem)")
                }
            }
        }

        for key in ["if-top-url", "unless-top-url"] {
            guard let value = trigger[key] else { continue }
            guard let patterns = value as? [Any], !patterns.isEmpty else {
                problems.append("\(key) が空でない配列ではありません")
                continue
            }
            for pattern in patterns {
                guard let pattern = pattern as? String, !pattern.isEmpty else {
                    problems.append("\(key) に空の値か、文字列でない値があります")
                    continue
                }
                if let problem = urlFilterProblem(pattern) {
                    problems.append("\(key) の \(quoted(pattern))：\(problem)")
                }
            }
        }

        if let value = trigger["resource-type"] {
            problems += listProblems(
                value, key: "resource-type", allowed: allowedResourceTypes,
                safari26Only: safari26OnlyResourceTypes
            )
        }
        if let value = trigger["load-type"] {
            problems += listProblems(value, key: "load-type", allowed: allowedLoadTypes, safari26Only: [])
        }
        if let value = trigger["load-context"] {
            problems += listProblems(value, key: "load-context", allowed: allowedLoadContexts, safari26Only: [])
        }
        for key in ["url-filter-is-case-sensitive", "top-url-filter-is-case-sensitive"] {
            if let value = trigger[key], !(value is Bool) {
                problems.append("\(key) は true か false にしてください")
            }
        }
        return problems
    }

    static func actionProblems(_ action: [String: Any], forbidExceptions: Bool) -> [String] {
        var problems: [String] = []
        for key in action.keys.sorted() where !allowedActionKeys.contains(key) {
            problems.append("action に知らないキー「\(key)」があります")
        }
        guard let type = action["type"] as? String else {
            problems.append("action.type がありません")
            return problems
        }
        guard allowedActionTypes.contains(type) else {
            problems.append("action.type「\(type)」は iOS 17 で使えません（使えるのは \(allowedActionTypes.sorted().joined(separator: "・"))）")
            return problems
        }
        if type == "css-display-none" {
            if let selector = action["selector"] as? String, !selector.trimmingCharacters(in: .whitespaces).isEmpty {
                // よい
            } else {
                problems.append("css-display-none に selector がないか、空です")
            }
        }
        if type == "ignore-previous-rules", forbidExceptions {
            problems.append("拡張の中で 2 番目以降のカテゴリに、例外ルール（ignore-previous-rules）があります。前のカテゴリのルールまで打ち消してしまう")
        }
        return problems
    }

    /// url-filter（と if-top-url など）の正規表現が、WebKit の URLFilterParser で読めるか。
    ///
    /// WebKit が受け付けない書き方：
    /// - ASCII 以外の文字
    /// - `|`（または）：Disjunctions are not supported
    /// - `{n,m}`（回数の指定）：*・+・? 以外の量指定はエラー
    /// - `\d` `\w` `\s` `\b` とその大文字（文字クラスの省略記法と単語境界）
    ///
    /// ただし、`\|` と `\{` のようにエスケープしたもの、`[…]` の中の `|` と `{` は、ただの文字として読める。
    /// 実際の EasyList の出力に `\/addyn\|.*;adtech;` のような `\|` があり、macOS の WebKit でコンパイルできることも
    /// 確かめたので、エスケープされていない `|` と `{` だけを問題にする（ルールを黙って捨てることはしない）。
    public static func urlFilterProblem(_ pattern: String) -> String? {
        guard pattern.unicodeScalars.allSatisfy(\.isASCII) else {
            return "ASCII 以外の文字があります"
        }
        let characters = Array(pattern.utf8)
        var index = 0
        var inClass = false
        while index < characters.count {
            let character = characters[index]
            if character == UInt8(ascii: "\\") {
                guard index + 1 < characters.count else {
                    return "末尾が「\\」で終わっています"
                }
                let next = characters[index + 1]
                if "dwsbDWSB".utf8.contains(next) {
                    return "「\\\(Character(Unicode.Scalar(next)))」は Safari で使えません"
                }
                index += 2
                continue
            }
            if inClass {
                if character == UInt8(ascii: "]") {
                    inClass = false
                }
            } else if character == UInt8(ascii: "[") {
                inClass = true
            } else if character == UInt8(ascii: "|") {
                return "「|」（または）は Safari で使えません"
            } else if character == UInt8(ascii: "{") {
                return "「{」（回数の指定）は Safari で使えません"
            }
            index += 1
        }
        return nil
    }

    /// if-domain / unless-domain の値：空でない小文字の ASCII（先頭の * は可）。
    static func domainProblem(_ value: Any) -> String? {
        guard let domain = value as? String else {
            return "文字列ではありません"
        }
        let body = domain.hasPrefix("*") ? String(domain.dropFirst()) : domain
        if body.isEmpty {
            return "空です"
        }
        if !body.unicodeScalars.allSatisfy(\.isASCII) {
            return "ASCII 以外の文字があります（Punycode にする必要がある）"
        }
        if body.contains(where: \.isUppercase) {
            return "大文字があります（WebKit は小文字だけを受け付ける）"
        }
        return nil
    }

    static func listProblems(_ value: Any, key: String, allowed: Set<String>, safari26Only: Set<String>) -> [String] {
        guard let values = value as? [Any], !values.isEmpty else {
            return ["\(key) が空でない配列ではありません"]
        }
        var problems: [String] = []
        for item in values {
            guard let item = item as? String else {
                problems.append("\(key) に文字列でない値があります")
                continue
            }
            if safari26Only.contains(item) {
                problems.append("\(key) の「\(item)」は Safari 26 からの値です")
            } else if !allowed.contains(item) {
                problems.append("\(key) の「\(item)」は使えません")
            }
        }
        return problems
    }

    static func quoted(_ value: Any) -> String {
        let text = "\(value)"
        let short = text.count > 80 ? String(text.prefix(80)) + "…" : text
        return "「\(short)」"
    }
}
