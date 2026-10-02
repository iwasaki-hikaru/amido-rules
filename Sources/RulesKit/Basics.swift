import CryptoKit
import Foundation

/// 利用者に見せるエラー。`message` は、そのまま表示する日本語の文。
public struct RulesError: Error, LocalizedError, CustomStringConvertible, Sendable, Equatable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String { message }
    public var errorDescription: String? { message }
}

/// 配信するカテゴリ（docs/format.md）。宣言の順番が、manifest の並び順になる。
/// 拡張の中の順番（config/budgets.json）も、この順番にそろえる（プラスは annoyance → privacy → scam）。
public enum RuleCategory: String, CaseIterable, Codable, Sendable, Comparable {
    case basic
    case annoyance
    /// トラッキング防止（EasyPrivacy）。
    case privacy
    case scam

    public var order: Int {
        Self.allCases.firstIndex(of: self) ?? 0
    }

    public static func < (lhs: RuleCategory, rhs: RuleCategory) -> Bool {
        lhs.order < rhs.order
    }

    /// 動作確認ページ（/check）で隠れるかを見る要素のクラス名。scam にはない。
    public var checkClassName: String? {
        switch self {
        case .basic: "cb-check-basic"
        case .annoyance: "cb-check-annoyance"
        case .privacy: "cb-check-privacy"
        case .scam: nil
        }
    }

    /// /check 用のルール（`<配信ホスト>##.cb-check-…`）。
    public func checkRule(host: String) -> String? {
        checkClassName.map { "\(host)##.\($0)" }
    }

    static var knownNames: String {
        allCases.map(\.rawValue).joined(separator: "・")
    }
}

/// 固定の値（docs/format.md と BlockerCore に合わせる）。
public enum RuleConstants {
    /// 絶対に一致しないダミールール（BlockerCore の DummyRule と同じ文字列）。
    public static let dummyRuleJSON = #"{"trigger":{"url-filter":"^https?://never-matches\\.invalid/"},"action":{"type":"block"}}"#

    /// コンパイルの確認で末尾に足す、許可サイトのルールの見本（アプリが足すものと同じ形）。
    public static let sampleAllowlistRuleJSON = #"{"trigger":{"url-filter":".*","if-domain":["*example.com"]},"action":{"type":"ignore-previous-rules"}}"#

    /// ドメイン名の最大の長さ（DNS の上限）。
    public static let maxDomainLength = 253

    /// 許可サイトのルールが最大になったとき（`domainCount` 件、どれも最大の長さ）のバイト数。
    /// 配列につなぐときの `,` 1 バイトを含む。config/budgets.json の appReservedBytes はこれ以上にする。
    public static func maxAllowlistRuleBytes(domainCount: Int) -> Int {
        let prefix = #"{"trigger":{"url-filter":".*","if-domain":["#
        let suffix = #"]},"action":{"type":"ignore-previous-rules"}}"#
        // 1 件は "*<ドメイン>"（ドメインの長さ ＋ 3）。件と件の間に `,`
        let domains = domainCount * (maxDomainLength + 3) + max(domainCount - 1, 0)
        return 1 + prefix.utf8.count + domains + suffix.utf8.count
    }
}

public enum Hashing {
    /// SHA-256 を小文字の 16 進（64 文字）で返す。
    public static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum JSONOutput {
    /// manifest と report で使う書き方：キーを並べ替え、字下げし、`/` をエスケープしない。
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return encoder
    }
}

enum FileIO {
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// UTF-8 のテキストとして読む。先頭の BOM は取り除く。
    static func readText(_ url: URL, displayName: String) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RulesError("\(displayName) を読めません：\(error.localizedDescription)")
        }
        return try decodeText(data, displayName: displayName)
    }

    static func decodeText(_ data: Data, displayName: String) throws -> String {
        guard var text = String(data: data, encoding: .utf8) else {
            throw RulesError("\(displayName) が UTF-8 のテキストではありません")
        }
        if text.hasPrefix("\u{FEFF}") {
            text.removeFirst()
        }
        return text
    }
}

/// 表示用の数の書き方（ロケールに左右されないよう自前で 3 桁ごとに区切る）。
enum Formatting {
    static func count(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 {
                result.append(",")
            }
            result.append(character)
        }
        return value < 0 ? "-" + result : result
    }

    static func bytes(_ value: Int) -> String {
        let mib = Double(value) / 1_048_576
        return String(format: "%.2f MiB", mib) + "（\(count(value)) B）"
    }

    static func seconds(_ value: Double) -> String {
        String(format: "%.2f 秒", value)
    }
}
