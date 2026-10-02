import Foundation

/// フィルタリスト（AdGuard / Adblock Plus 形式）のテキストを扱う。
public enum SourceText {
    /// 行に分ける。CRLF と CR も区切りとして扱う（Swift では "\r\n" が 1 文字になるため、明示して分ける）。
    public static func lines(_ text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r\n" || $0 == "\r" }
    }

    /// `[Adblock Plus 2.0]` のような見出しの行（`^\[Adblock.*\]$`）。
    ///
    /// 変換器はこの行をルールとして読み、何にでも当たるブロックルールを作ってしまうので、変換の前に取り除く。
    public static func isAdblockHeader<S: StringProtocol>(_ line: S) -> Bool {
        line.hasPrefix("[Adblock") && line.hasSuffix("]")
    }

    /// ルールの行か（空行・コメント・見出しを除く）。
    public static func isRuleLine<S: StringProtocol>(_ line: S) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.hasPrefix("!") && !isAdblockHeader(trimmed)
    }

    /// 見出しの行を取り除き、改行を LF にそろえる。末尾は必ず改行で終わる。
    public static func stripAdblockHeaders(_ text: String) -> (text: String, removedLines: Int) {
        var kept: [Substring] = []
        var removed = 0
        for line in lines(text) {
            if isAdblockHeader(line) {
                removed += 1
            } else {
                kept.append(line)
            }
        }
        while let last = kept.last, last.isEmpty {
            kept.removeLast()
        }
        let joined = kept.joined(separator: "\n")
        return (joined.isEmpty ? "" : joined + "\n", removed)
    }

    public static func countRuleLines(_ text: String) -> Int {
        lines(text).reduce(0) { $0 + (isRuleLine($1) ? 1 : 0) }
    }

    /// 節の見出しの行の始まり。EasyList の仲間のリストは、元のファイルごとに
    /// 「! *** easylist:easyprivacy/easyprivacy_general.txt ***」のような行で区切られている。
    public static let sectionHeadingPrefix = "! *** "

    public struct SectionFilterResult: Sendable, Equatable {
        public var text: String
        /// 除いた節の見出し（前後の空白を除いたもの）。
        public var excludedSections: [String]
        /// 除いたルールの行の数。
        public var removedRuleLines: Int
        /// 除く節の中でも、`keepLinesContaining` を含むので残したルールの行の数。
        public var keptRuleLines: Int
    }

    /// 見出しの行が `headingPrefix` で始まる節を除く（sources.yml の exclude_sections）。
    ///
    /// 節は、見出しの行から、次の見出しの行（`sectionHeadingPrefix` で始まる行）の前までとする。
    /// `keepLinesContaining` があれば、除く節の中でも、その文字列を含むルールの行は残す
    ///（sources.yml の keep_lines_containing。大文字と小文字は区別する）。
    /// 除く節の中のコメントと空行は、残さない。
    public static func excludeSections(
        _ text: String,
        headingPrefix: String,
        keepLinesContaining: String? = nil
    ) -> SectionFilterResult {
        var kept: [Substring] = []
        var sections: [String] = []
        var removed = 0
        var keptInSections = 0
        var excluding = false
        for line in lines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(sectionHeadingPrefix) {
                excluding = trimmed.hasPrefix(headingPrefix)
                if excluding {
                    sections.append(trimmed)
                    continue
                }
            }
            guard excluding else {
                kept.append(line)
                continue
            }
            guard isRuleLine(line) else {
                continue
            }
            if let keep = keepLinesContaining, !keep.isEmpty, line.contains(keep) {
                kept.append(line)
                keptInSections += 1
            } else {
                removed += 1
            }
        }
        while let last = kept.last, last.isEmpty {
            kept.removeLast()
        }
        let joined = kept.joined(separator: "\n")
        return SectionFilterResult(
            text: joined.isEmpty ? "" : joined + "\n",
            excludedSections: sections,
            removedRuleLines: removed,
            keptRuleLines: keptInSections
        )
    }

    /// 先頭のコメントの中にある、ライセンス・ホームページ・版などの行（report.json に記録する）。
    /// EasyList は英国式の綴り「Licence」なので、両方を拾う。
    public static func headerLines(_ text: String) -> [String] {
        let keys: Set<String> = ["title", "version", "last modified", "homepage", "license", "licence"]
        var result: [String] = []
        for line in lines(text) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || isAdblockHeader(trimmed) {
                continue
            }
            guard trimmed.hasPrefix("!") else {
                break
            }
            let body = trimmed.dropFirst().trimmingCharacters(in: .whitespaces)
            if let colon = body.firstIndex(of: ":"),
               keys.contains(body[..<colon].trimmingCharacters(in: .whitespaces).lowercased()) {
                result.append(trimmed)
            }
        }
        return result
    }

    /// 自作ルール（custom/*.txt）の検査。問題を「ファイル:行: 内容」の形で返す。
    ///
    /// - 各ルールのすぐ上のコメントのかたまり（空行やほかのルールをはさまない）に、
    ///   「! 根拠: <http(s) の URL> (YYYY-MM-DD)」が必要
    /// - 「!#」「!+」で始まる行（AdGuard の前処理の指示とヒント）は使えない。
    ///   変換の結果が読めなくなるのを防ぐため
    public static func lintCustomRules(_ text: String, fileName: String) -> [String] {
        var problems: [String] = []
        var hasEvidence = false
        for (offset, line) in lines(text).enumerated() {
            let lineNumber = offset + 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                hasEvidence = false
                continue
            }
            if trimmed.hasPrefix("!#") || trimmed.hasPrefix("!+") {
                problems.append("\(fileName):\(lineNumber): 「!#」「!+」で始まる行（前処理の指示・ヒント）は使えません：\(trimmed)")
                hasEvidence = false
                continue
            }
            if trimmed.hasPrefix("!") {
                switch evidence(in: trimmed) {
                case .valid:
                    hasEvidence = true
                case .malformed(let reason):
                    problems.append("\(fileName):\(lineNumber): 根拠の書き方が違います（\(reason)）。「! 根拠: https://… (YYYY-MM-DD)」の形にしてください")
                case .none:
                    break
                }
                continue
            }
            if isAdblockHeader(trimmed) {
                hasEvidence = false
                continue
            }
            if !hasEvidence {
                problems.append("\(fileName):\(lineNumber): ルール「\(trimmed)」のすぐ上に「! 根拠: <URL> (YYYY-MM-DD)」がありません")
            }
            // 次のルールには、次のルール自身の根拠が要る
            hasEvidence = false
        }
        return problems
    }

    enum Evidence: Equatable {
        case none
        case valid
        case malformed(String)
    }

    /// コメントの行が根拠の行か。「根拠:」「根拠：」で始まるのに形が違うものは、書き間違いとして報告する。
    static func evidence(in commentLine: String) -> Evidence {
        let body = commentLine.dropFirst().trimmingCharacters(in: .whitespaces)
        guard body.hasPrefix("根拠") else {
            return .none
        }
        let afterWord = body.dropFirst(2)
        if afterWord.hasPrefix("：") {
            return .malformed("「根拠」の後のコロンは半角の「:」にしてください")
        }
        guard afterWord.hasPrefix(":") else {
            return .none
        }
        let rest = afterWord.dropFirst().trimmingCharacters(in: .whitespaces)
        let parts = rest.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            return .malformed("URL と (日付) を 1 つずつ、空白で区切って書いてください")
        }
        let urlText = String(parts[0])
        guard let url = URL(string: urlText),
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = url.host(), !host.isEmpty
        else {
            return .malformed("URL は http:// か https:// で始めてください")
        }
        let dateText = parts[1]
        guard dateText.hasPrefix("("), dateText.hasSuffix(")") else {
            return .malformed("日付は (YYYY-MM-DD) の形で書いてください")
        }
        guard isValidDate(dateText.dropFirst().dropLast()) else {
            return .malformed("日付 \(dateText) が正しくありません")
        }
        return .valid
    }

    static func isValidDate<S: StringProtocol>(_ text: S) -> Bool {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2])
        else {
            return false
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? calendar.timeZone
        let components = DateComponents(calendar: calendar, year: year, month: month, day: day)
        return components.isValidDate
    }
}
