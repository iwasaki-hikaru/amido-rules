import Foundation

/// 検査の結果。問題は先頭から `maxIssues` 件まで持ち、総数は `issueCount` に数える。
public struct LintReport: Sendable, Equatable {
    public var ruleCount: Int
    public var issues: [String]
    public var issueCount: Int
    /// 例外ルール（ignore-previous-rules）の数。
    public var exceptionCount: Int = 0
    /// そのうち、ホストだけを限ったもの（RuleListLint.isHostOnlyURLFilter）の数。
    public var hostOnlyExceptionCount: Int = 0

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

    /// - Parameter forbidAllURLExceptions: 拡張の中で 2 番目以降のカテゴリ（privacy・scam）なら true。
    ///   `ignore-previous-rules` は前のカテゴリのルールにも効くので、すべての URL に効く例外
    ///  （`url-filter` が `.*` など。matchesEveryURL）は、前のカテゴリをサイトごと止めてしまう。それを失敗にする。
    ///   `.jp` のサイトすべてなど、サフィックス全体に効く例外（matchedWideSuffix）も同じく失敗にする。
    ///   URL やホストを限った例外は通す（docs/format.md）。
    public static func lint(_ data: Data, forbidAllURLExceptions: Bool, maxIssues: Int = 200) -> LintReport {
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
            if let rule = rule as? [String: Any],
               let action = rule["action"] as? [String: Any],
               action["type"] as? String == "ignore-previous-rules" {
                report.exceptionCount += 1
                if let trigger = rule["trigger"] as? [String: Any],
                   let filter = trigger["url-filter"] as? String,
                   isHostOnlyURLFilter(filter) {
                    report.hostOnlyExceptionCount += 1
                }
            }
            for problem in problems(in: rule, forbidAllURLExceptions: forbidAllURLExceptions) {
                report.issueCount += 1
                if report.issues.count < maxIssues {
                    report.issues.append("rules[\(index)]: \(problem)")
                }
            }
        }
        return report
    }

    /// ルール 1 件の問題。
    public static func problems(in rule: Any, forbidAllURLExceptions: Bool) -> [String] {
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
            problems += actionProblems(action)
            if forbidAllURLExceptions, action["type"] as? String == "ignore-previous-rules",
               let trigger = rule["trigger"] as? [String: Any],
               let filter = trigger["url-filter"] as? String, !filter.isEmpty {
                let caseSensitive = trigger["url-filter-is-case-sensitive"] as? Bool ?? false
                if matchesEveryURL(filter, caseSensitive: caseSensitive) {
                    problems.append("拡張の中で 2 番目以降のカテゴリに、すべての URL に効く例外ルール（ignore-previous-rules、url-filter \(quoted(filter))）があります。前のカテゴリのルールまで、サイトごと打ち消してしまう")
                } else if let suffix = matchedWideSuffix(filter, caseSensitive: caseSensitive) {
                    // 日本のサイト（.jp）すべてなどは、この利用者にとっては、すべての URL とほぼ同じ
                    problems.append("拡張の中で 2 番目以降のカテゴリに、「.\(suffix)」のサイトすべてに効く例外ルール（ignore-previous-rules、url-filter \(quoted(filter))）があります。前のカテゴリのルールまで、そのサイトすべてで打ち消してしまう")
                }
            }
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

    static func actionProblems(_ action: [String: Any]) -> [String] {
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
        return problems
    }

    /// すべての URL に当たるかを確かめる見本の URL。関係のないドメイン名で、ホストもパスもばらばらにしてあるので、
    /// ホストやパスを限った url-filter は、どれかに当たらない。
    ///
    /// IP アドレス・ポート・punycode の URL は入れない。「すべてに当たれば失敗」なので、変わった見本が 1 つあるだけで、
    /// ほとんどのサイトに当たる url-filter（`[a-z]\.[a-z]`・`^https?:\/\/[a-z]` など）が通ってしまうため。
    static let everyURLSamples: [[String]] = urlSamples([
        "amido-check-a.invalid/",
        "www.amido-check-b.test/path/to/page.html?q=1&r=2",
        "cdn.amido-check-c.example/x/y.js",
    ])

    /// サイトの範囲が広すぎるとみなす、トップレベルドメインなど（公開サフィックス）。
    /// 日本のサイトの多くが入るもの（jp と co.jp などの属性型）と、よく使うもの。すべての一覧ではない。
    /// 並びは、広いものを先にする（メッセージに出すのは、最初に当たったもの）。
    public static let wideSuffixes = [
        "jp", "co.jp", "ne.jp", "or.jp", "ac.jp", "ad.jp", "ed.jp", "go.jp", "gr.jp", "lg.jp",
        "com", "net", "org", "info", "io",
    ]

    /// wideSuffixes のそれぞれについて、そのサフィックスの関係のないサイト 2 つの見本の URL。
    static let wideSuffixSamples: [(suffix: String, samples: [[String]])] = wideSuffixes.map { suffix in
        (suffix, urlSamples(["www.amido-check-d.\(suffix)/", "amido-check-e.\(suffix)/path/to/page.html?q=1&r=2"]))
    }

    /// ホストから先（`example.com/path`）の並びから、https と http の見本の組を作る。
    static func urlSamples(_ rests: [String]) -> [[String]] {
        ["https://", "http://"].map { scheme in rests.map { scheme + $0 } }
    }

    /// url-filter が、すべての URL に当たるか（`.*`・`^https?://`・`/`・`[a-z]\.[a-z]` など）。
    ///
    /// 正規表現の形を数え上げるのではなく、見本の URL（everyURLSamples）で確かめる。
    /// https の見本のすべてか、http の見本のすべてに当たれば、すべての URL に当たるとみなす。
    /// 読めない正規表現は false（読めないことは urlFilterProblem か WebKit のコンパイルで分かる）。
    public static func matchesEveryURL(_ pattern: String, caseSensitive: Bool = false) -> Bool {
        guard let regex = regex(pattern, caseSensitive: caseSensitive) else {
            return false
        }
        return matchesAll(regex, everyURLSamples)
    }

    /// url-filter が、`.jp` や `.co.jp` などのサイトすべてに当たるなら、そのサフィックスを返す
    ///（`@@||*.jp^`・`@@||co.jp^` を変換した形など）。すべての URL に当たるもの（matchesEveryURL）も、ここで当たる。
    public static func matchedWideSuffix(_ pattern: String, caseSensitive: Bool = false) -> String? {
        guard let regex = regex(pattern, caseSensitive: caseSensitive) else {
            return nil
        }
        return wideSuffixSamples.first { matchesAll(regex, $0.samples) }?.suffix
    }

    private static func regex(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern, options: caseSensitive ? [] : [.caseInsensitive])
    }

    /// 見本の組（https・http）のどちらかで、すべてに当たるか。
    private static func matchesAll(_ regex: NSRegularExpression, _ sampleSets: [[String]]) -> Bool {
        sampleSets.contains { samples in
            samples.allSatisfy { url in
                regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
            }
        }
    }

    /// 変換器が `||example.com^` から作る、ホストだけを限った url-filter か
    ///（`^[^:]+://+([^:/]+\.)?example\.com[/:]`。末尾の `[/:]` と `.*` はなくてもよい）。
    /// ホストが `co.jp` のようなサフィックスだけのもの（wideSuffixes）は、ホストを限っていないので false。
    public static func isHostOnlyURLFilter(_ pattern: String) -> Bool {
        let prefix = #"^[^:]+://+([^:/]+\.)?"#
        guard pattern.hasPrefix(prefix) else {
            return false
        }
        var rest = Substring(pattern.dropFirst(prefix.count))
        for suffix in [".*", "$"] where rest.hasSuffix(suffix) {
            rest = rest.dropLast(suffix.count)
        }
        if rest.hasSuffix("[/:]") {
            rest = rest.dropLast("[/:]".count)
        }
        // 残りはホスト名（英数字と - と \.）だけ
        let host = rest.replacingOccurrences(of: #"\."#, with: ".")
        return !host.isEmpty && host.contains(".") && !wideSuffixes.contains(host.lowercased())
            && host.unicodeScalars.allSatisfy { scalar in
                ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
                    || scalar == "-" || scalar == "."
            }
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
