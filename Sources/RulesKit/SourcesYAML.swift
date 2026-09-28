import Foundation

/// sources.yml で使える値：1 行の文字列か、true / false。
public enum YAMLScalar: Equatable, Sendable {
    case string(String)
    case bool(Bool)
}

public struct YAMLField: Equatable, Sendable {
    public var value: YAMLScalar
    public var line: Int
}

/// リストの項目 1 つ（「- 」で始まる、キーと値の組）。
public struct YAMLListItem: Equatable, Sendable {
    public var line: Int
    public var fields: [String: YAMLField]
}

/// sources.yml を読む、YAML のごく一部だけのパーサー。
///
/// Foundation には YAML を読む機能がなく、外部のライブラリも使わないので、docs/format.md の
/// 「sources.yml」に書いた形だけを受け付ける。
/// - 最上位は `sources:` だけ。その下に `- キー: 値` の項目を並べる
/// - 値は 1 行の文字列（`"…"` か `'…'` で囲んでもよい）、または true / false
/// - `#` から行末まではコメント（行の先頭か、空白の直後の `#` だけ）
/// それ以外（入れ子、複数行の値、フロー形式など）は、読み違えないようにエラーにする。
public enum SourcesYAML {
    public static func parse(_ text: String, fileName: String = "sources.yml") throws -> [YAMLListItem] {
        var items: [YAMLListItem] = []
        var sawRoot = false
        var dashIndent: Int?
        var keyIndent: Int?

        for (offset, line) in SourceText.lines(text).enumerated() {
            let lineNumber = offset + 1
            func failure(_ message: String) -> RulesError {
                RulesError("\(fileName):\(lineNumber): \(message)")
            }

            let indent = line.prefix { $0 == " " }.count
            let body = line.dropFirst(indent)
            if body.first == "\t" {
                throw failure("字下げにタブは使えません。空白で字下げしてください")
            }
            if body.allSatisfy(\.isWhitespace) || body.first == "#" {
                continue
            }
            if body.hasPrefix("---") || body.hasPrefix("...") || body.hasPrefix("%") {
                throw failure("YAML の文書の区切りや指示には対応していません")
            }

            let isListItem = body == "-" || body.hasPrefix("- ")
            if indent == 0, !isListItem {
                let (key, value) = try parseKeyValue(body, failure)
                guard key == "sources" else {
                    throw failure("最上位に書けるのは「sources:」だけです（「\(key)」があります）")
                }
                guard value == nil else {
                    throw failure("「sources:」の後は改行し、次の行から「- 」で項目を並べてください")
                }
                guard !sawRoot else {
                    throw failure("「sources:」が 2 回あります")
                }
                sawRoot = true
                continue
            }
            guard sawRoot else {
                throw failure("先に「sources:」を書いてください")
            }

            if isListItem {
                if let dashIndent, dashIndent != indent {
                    throw failure("「- 」の字下げがそろっていません（\(dashIndent) 文字にそろえてください）")
                }
                dashIndent = indent
                let afterDash = body.dropFirst()
                let spaces = afterDash.prefix { $0 == " " }.count
                let rest = afterDash.dropFirst(spaces)
                if rest.isEmpty || rest.first == "#" {
                    throw failure("「- 」と同じ行に、最初の「キー: 値」を書いてください")
                }
                if rest.hasPrefix("- ") || rest == "-" {
                    throw failure("入れ子のリストには対応していません")
                }
                keyIndent = indent + 1 + spaces
                let (key, value) = try parseKeyValue(rest, failure)
                guard let value else {
                    throw failure("「\(key)」に値がありません（入れ子には対応していません）")
                }
                items.append(YAMLListItem(line: lineNumber, fields: [key: YAMLField(value: value, line: lineNumber)]))
                continue
            }

            guard let keyIndent, !items.isEmpty else {
                throw failure("「- 」で始まる項目の中に書いてください")
            }
            guard indent == keyIndent else {
                throw failure("字下げが正しくありません（項目のキーは \(keyIndent) 文字の字下げにそろえてください）")
            }
            let (key, value) = try parseKeyValue(body, failure)
            guard let value else {
                throw failure("「\(key)」に値がありません（入れ子には対応していません）")
            }
            if items[items.count - 1].fields[key] != nil {
                throw failure("「\(key)」が同じ項目の中に 2 回あります")
            }
            items[items.count - 1].fields[key] = YAMLField(value: value, line: lineNumber)
        }

        guard sawRoot else {
            throw RulesError("\(fileName): 「sources:」がありません")
        }
        return items
    }

    /// 「キー: 値」を分ける。値がなければ nil。
    private static func parseKeyValue(
        _ text: Substring,
        _ failure: (String) -> RulesError
    ) throws -> (String, YAMLScalar?) {
        guard let colon = text.firstIndex(of: ":") else {
            throw failure("「キー: 値」の形で書いてください")
        }
        let key = String(text[..<colon])
        guard isValidKey(key) else {
            throw failure("キー「\(key)」は使えません（英小文字・数字・_・- だけにしてください）")
        }
        var rest = text[text.index(after: colon)...]
        if let first = rest.first, first != " " {
            throw failure("「\(key):」の後には空白を入れてください")
        }
        rest = rest.drop { $0 == " " }
        if rest.isEmpty || rest.first == "#" {
            return (key, nil)
        }
        return (key, try parseValue(rest, failure))
    }

    private static func isValidKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first, ("a"..."z").contains(first) || ("A"..."Z").contains(first) else {
            return false
        }
        return key.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
        }
    }

    private static func parseValue(_ text: Substring, _ failure: (String) -> RulesError) throws -> YAMLScalar {
        if text.first == "\"" {
            return .string(try parseQuoted(text, quote: "\"", failure))
        }
        if text.first == "'" {
            return .string(try parseQuoted(text, quote: "'", failure))
        }

        // 空白の直後の # からがコメント（URL の #fragment は残る）
        var end = text.endIndex
        var previousIsSpace = false
        for index in text.indices {
            let character = text[index]
            if character == "#", previousIsSpace {
                end = index
                break
            }
            previousIsSpace = character == " " || character == "\t"
        }
        var value = text[..<end]
        while let last = value.last, last == " " || last == "\t" {
            value = value.dropLast()
        }

        if let first = value.first, "[]{}&*!|>%@`,?".contains(first) {
            throw failure("「\(first)」で始まる値には対応していません。1 行の文字列（必要なら \"…\" で囲む）か true / false にしてください")
        }
        if value.hasPrefix("- ") {
            throw failure("入れ子のリストには対応していません")
        }
        if value.contains(": ") || value.hasSuffix(":") {
            throw failure("値に「: 」を含めるときは \"…\" で囲んでください")
        }
        switch value {
        case "true": return .bool(true)
        case "false": return .bool(false)
        default: return .string(String(value))
        }
    }

    /// `"…"`（\" \\ \/ \n \t のエスケープ）と `'…'`（'' で ' を表す）。
    private static func parseQuoted(
        _ text: Substring,
        quote: Character,
        _ failure: (String) -> RulesError
    ) throws -> String {
        var result = ""
        var index = text.index(after: text.startIndex)
        var closed = false
        while index < text.endIndex {
            let character = text[index]
            if quote == "\"", character == "\\" {
                let next = text.index(after: index)
                guard next < text.endIndex else {
                    throw failure("「\\」の後に文字がありません")
                }
                switch text[next] {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: throw failure("「\\\(text[next])」というエスケープには対応していません")
                }
                index = text.index(after: next)
                continue
            }
            if character == quote {
                let next = text.index(after: index)
                if quote == "'", next < text.endIndex, text[next] == "'" {
                    result.append("'")
                    index = text.index(after: next)
                    continue
                }
                closed = true
                index = next
                break
            }
            result.append(character)
            index = text.index(after: index)
        }
        guard closed else {
            throw failure("「\(quote)」が閉じていません")
        }
        let after = text[index...]
        let trimmed = after.drop { $0 == " " || $0 == "\t" }
        if !trimmed.isEmpty, !(trimmed.first == "#" && trimmed.startIndex != after.startIndex) {
            throw failure("「\(quote)…\(quote)」の後に余分な文字があります")
        }
        return result
    }
}
