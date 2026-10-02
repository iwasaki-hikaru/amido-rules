import Foundation

/// manifest.json（schema 1、docs/format.md）。
public struct Manifest: Codable, Sendable, Equatable {
    public struct Entry: Codable, Sendable, Equatable {
        public var category: String
        public var url: String
        public var sha256: String
        public var size: Int
        public var ruleCount: Int

        public init(category: String, url: String, sha256: String, size: Int, ruleCount: Int) {
            self.category = category
            self.url = url
            self.sha256 = sha256
            self.size = size
            self.ruleCount = ruleCount
        }

        enum CodingKeys: String, CodingKey {
            case category
            case url
            case sha256
            case size
            case ruleCount = "rule_count"
        }
    }

    public static let currentSchema = 1

    public var schema: Int
    public var version: String
    public var publishedAt: String
    public var minAppBuild: Int
    public var lists: [Entry]

    public init(schema: Int = Manifest.currentSchema, version: String, publishedAt: String, minAppBuild: Int, lists: [Entry]) {
        self.schema = schema
        self.version = version
        self.publishedAt = publishedAt
        self.minAppBuild = minAppBuild
        self.lists = lists
    }

    enum CodingKeys: String, CodingKey {
        case schema
        case version
        case publishedAt = "published_at"
        case minAppBuild = "min_app_build"
        case lists
    }

    /// キーを並べ替え、字下げして、`/` をエスケープせずに書く。
    public func encoded() throws -> Data {
        try JSONOutput.encoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> Manifest {
        do {
            return try JSONDecoder().decode(Manifest.self, from: data)
        } catch {
            throw RulesError("manifest.json を読めません：\(describe(error))")
        }
    }

    /// 取り決め（docs/format.md）に合っているか。問題を文のリストで返す。
    public func problems(fileSizeLimitBytes: Int = ManifestFormat.defaultFileSizeLimitBytes) -> [String] {
        var problems: [String] = []
        if schema != Manifest.currentSchema {
            problems.append("schema が \(schema) です（\(Manifest.currentSchema) だけに対応）")
        }
        if !ManifestFormat.isValidVersion(version) {
            problems.append("version「\(version)」が YYYY.MM.DD.N の形ではありません")
        }
        if !ManifestFormat.isValidPublishedAt(publishedAt) {
            problems.append("published_at「\(publishedAt)」が UTC の秒までの RFC 3339（例 2026-10-05T03:00:00Z）ではありません")
        }
        if minAppBuild < 1 {
            problems.append("min_app_build は 1 以上にしてください")
        }
        var seen: Set<String> = []
        var previousOrder = -1
        for entry in lists {
            let label = "lists の \(entry.category)"
            guard let category = RuleCategory(rawValue: entry.category) else {
                problems.append("\(label)：知らないカテゴリです")
                continue
            }
            if !seen.insert(entry.category).inserted {
                problems.append("\(label)：同じカテゴリが 2 回あります")
            }
            if category.order < previousOrder {
                problems.append("\(label)：lists が \(RuleCategory.knownNames) の順に並んでいません")
            }
            previousOrder = category.order
            if !ManifestFormat.isValidSHA256(entry.sha256) {
                problems.append("\(label)：sha256 が 64 文字の小文字の 16 進ではありません")
            }
            if !ManifestFormat.isValidListURL(entry.url) {
                problems.append("\(label)：url「\(entry.url)」が lists/<category>.<hash8>.json の形ではありません")
            } else if entry.url != ManifestFormat.listPath(category: category, sha256: entry.sha256) {
                problems.append("\(label)：url「\(entry.url)」が、カテゴリと sha256 の先頭 8 文字に合っていません")
            }
            if entry.size < 1 || entry.size >= fileSizeLimitBytes {
                problems.append("\(label)：size \(entry.size) が 1 以上 \(fileSizeLimitBytes) 未満ではありません")
            }
            if entry.ruleCount < 1 {
                problems.append("\(label)：rule_count は 1 以上にしてください")
            }
        }
        return problems
    }
}

public enum ManifestFormat {
    public static let defaultFileSizeLimitBytes = 25 * 1024 * 1024

    /// `^lists/[a-z]+\.[0-9a-f]{8}\.json$`
    public static func isValidListURL(_ url: String) -> Bool {
        guard url.hasPrefix("lists/"), url.hasSuffix(".json") else {
            return false
        }
        let middle = url.dropFirst("lists/".count).dropLast(".json".count)
        let parts = middle.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return false
        }
        let name = parts[0]
        let hash = parts[1]
        return !name.isEmpty
            && name.unicodeScalars.allSatisfy { ("a"..."z").contains($0) }
            && hash.count == 8
            && isLowercaseHex(hash)
    }

    public static func isValidSHA256(_ value: String) -> Bool {
        value.count == 64 && isLowercaseHex(value)
    }

    static func isLowercaseHex<S: StringProtocol>(_ value: S) -> Bool {
        value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    public static func hash8(_ sha256: String) -> String {
        String(sha256.prefix(8))
    }

    public static func listFileName(category: RuleCategory, sha256: String) -> String {
        "\(category.rawValue).\(hash8(sha256)).json"
    }

    public static func listPath(category: RuleCategory, sha256: String) -> String {
        "lists/" + listFileName(category: category, sha256: sha256)
    }

    /// `YYYY.MM.DD.N`（N は 1 以上）。日付も正しいかを見る。
    public static func isValidVersion(_ version: String) -> Bool {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              SourceText.isValidDate("\(parts[0])-\(parts[1])-\(parts[2])"),
              let number = Int(parts[3]), number >= 1,
              parts[3].allSatisfy({ $0.isASCII && $0.isNumber }), !parts[3].hasPrefix("0")
        else {
            return false
        }
        return true
    }

    /// その日（UTC）の 1 番目の版。
    public static func defaultVersion(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter.string(from: date) + ".1"
    }

    /// UTC、秒まで（`2026-10-05T03:00:00Z`）。
    public static func formatPublishedAt(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let seconds = floor(date.timeIntervalSince1970)
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    /// RFC 3339 の日時を読み、UTC の秒までに直す（`+09:00` や小数の秒も受け付ける）。
    public static func normalizePublishedAt(_ text: String) -> String? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: text) ?? fractional.date(from: text) else {
            return nil
        }
        return formatPublishedAt(date)
    }

    public static func isValidPublishedAt(_ text: String) -> Bool {
        guard text.count == 20, text.hasSuffix("Z") else {
            return false
        }
        return normalizePublishedAt(text) == text
    }
}

/// 2 つの manifest で、配信するものが変わったか（compare コマンド）。
///
/// min_app_build と、（カテゴリ, sha256）の組の集まりが同じなら「変わっていない」。
/// version と published_at は毎回変わるので比べない。
public enum ManifestComparison {
    public static func isUnchanged(current: Manifest, previous: Manifest) -> Bool {
        guard current.minAppBuild == previous.minAppBuild else {
            return false
        }
        func pairs(_ manifest: Manifest) -> Set<String> {
            Set(manifest.lists.map { "\($0.category)\u{0}\($0.sha256)" })
        }
        return pairs(current) == pairs(previous)
    }
}
