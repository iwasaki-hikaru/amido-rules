import Foundation

/// sources.yml の項目 1 つ。
public struct SourceEntry: Sendable, Equatable {
    public enum Origin: Sendable, Equatable {
        /// 上流のリスト（HTTPS）。build/sources/<slug>.txt にキャッシュする。
        case url(URL)
        /// リポジトリの中のファイル（sources.yml のあるディレクトリからの相対パス）。
        case path(String)
    }

    public var name: String
    public var origin: Origin
    public var license: String
    public var attribution: String
    public var category: RuleCategory
    public var enabled: Bool
    /// sources.yml の中の行番号（項目の「- 」の行）。
    public var line: Int
    /// キャッシュのファイル名に使う名前（名前から作る。EasyList なら easylist）。
    public var slug: String
    /// 除く節の見出しの行の始まり（`! *** ` で始まる。SourceText.excludeSections）。
    public var excludeSections: String? = nil
    /// 除く節の中でも、この文字列を含むルールの行は残す。
    public var keepLinesContaining: String? = nil

    /// custom/ の下の自作ルール。各ルールに根拠のコメントが必要。
    /// path のソースは custom/ の下だけに限る（SourcesFile.parse）。
    /// 書き方しだいで根拠の検査を抜けないように、path のソースはすべて自作ルールとして扱う。
    public var isCustom: Bool {
        if case .path = origin {
            return true
        }
        return false
    }

    public var locationDescription: String {
        switch origin {
        case .url(let url): url.absoluteString
        case .path(let path): path
        }
    }
}

public enum SourcesFile {
    public static let knownKeys: Set<String> = [
        "name", "url", "path", "license", "attribution", "category", "enabled",
        "exclude_sections", "keep_lines_containing",
    ]

    public static func load(from url: URL, denylist: Denylist) throws -> [SourceEntry] {
        let text = try FileIO.readText(url, displayName: url.lastPathComponent)
        return try parse(text, fileName: url.lastPathComponent, denylist: denylist)
    }

    /// 読んで、項目ごとに確かめる。問題はまとめて 1 つのエラーにする。
    public static func parse(_ text: String, fileName: String = "sources.yml", denylist: Denylist) throws -> [SourceEntry] {
        let items = try SourcesYAML.parse(text, fileName: fileName)
        var entries: [SourceEntry] = []
        var problems: [String] = []
        var names: [String: Int] = [:]
        var slugs: [String: Int] = [:]

        for item in items {
            func problem(_ message: String, line: Int? = nil) {
                problems.append("\(fileName):\(line ?? item.line): \(message)")
            }
            for key in item.fields.keys.sorted() where !knownKeys.contains(key) {
                problem("知らないキー「\(key)」があります（使えるのは \(knownKeys.sorted().joined(separator: "・"))）", line: item.fields[key]?.line)
            }

            func string(_ key: String, required: Bool = true) -> String? {
                guard let field = item.fields[key] else {
                    if required { problem("「\(key)」がありません") }
                    return nil
                }
                guard case .string(let value) = field.value else {
                    problem("「\(key)」は文字列で書いてください", line: field.line)
                    return nil
                }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    problem("「\(key)」が空です", line: field.line)
                    return nil
                }
                return trimmed
            }

            let name = string("name")
            let license = string("license")
            let attribution = string("attribution")
            let categoryName = string("category")
            let urlText = string("url", required: false)
            let pathText = string("path", required: false)
            let excludeSections = string("exclude_sections", required: false)
            let keepLinesContaining = string("keep_lines_containing", required: false)

            if let excludeSections, !excludeSections.hasPrefix(SourceText.sectionHeadingPrefix) {
                problem(
                    "「exclude_sections」は、節の見出しの行の始まり（\"\(SourceText.sectionHeadingPrefix)…\" の形）で書いてください：\(excludeSections)",
                    line: item.fields["exclude_sections"]?.line
                )
            }
            if keepLinesContaining != nil, item.fields["exclude_sections"] == nil {
                problem("「keep_lines_containing」は「exclude_sections」と一緒に書いてください", line: item.fields["keep_lines_containing"]?.line)
            }

            var category: RuleCategory?
            if let categoryName {
                category = RuleCategory(rawValue: categoryName)
                if category == nil {
                    problem("カテゴリ「\(categoryName)」は使えません（\(RuleCategory.knownNames) のどれか）", line: item.fields["category"]?.line)
                }
            }

            var enabled: Bool?
            if let field = item.fields["enabled"] {
                if case .bool(let value) = field.value {
                    enabled = value
                } else {
                    problem("「enabled」は true か false で書いてください", line: field.line)
                }
            } else {
                problem("「enabled」がありません（true か false）")
            }

            var origin: SourceEntry.Origin?
            switch (urlText, pathText) {
            case (nil, nil):
                if item.fields["url"] == nil, item.fields["path"] == nil {
                    problem("「url」か「path」のどちらか 1 つが必要です")
                }
            case (.some, .some):
                problem("「url」と「path」は、どちらか 1 つだけにしてください")
            case (.some(let text), nil):
                let line = item.fields["url"]?.line
                if let hit = denylist.match(text) {
                    problem("URL に使えないリスト（config/denylist.json の「\(hit)」）が含まれています：\(text)", line: line)
                } else if let url = URL(string: text), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty {
                    origin = .url(url)
                } else {
                    problem("url は https:// で始まる正しい URL にしてください：\(text)", line: line)
                }
            case (nil, .some(let path)):
                let line = item.fields["path"]?.line
                let components = path.split(separator: "/", omittingEmptySubsequences: false)
                // 「.」の部分は取り除いて比べる（./custom/a.txt は custom/a.txt と同じ）
                let normalized = components.filter { $0 != "." }
                if let hit = denylist.match(path) {
                    problem("path に使えないリスト（config/denylist.json の「\(hit)」）が含まれています：\(path)", line: line)
                } else if path.hasPrefix("/") || path.contains("\\") || components.contains("..") || components.contains("") || path.contains("://") {
                    problem("path は、リポジトリの中の相対パスにしてください（/ で始めない、.. を含めない）：\(path)", line: line)
                } else if normalized.count < 2 || normalized.first != "custom" {
                    // 自作ルールの根拠の検査を抜けないように、path は custom/ の下だけにする（大文字小文字も区別する）
                    problem("path は custom/ の下のファイルにしてください：\(path)", line: line)
                } else {
                    origin = .path(normalized.joined(separator: "/"))
                }
            }

            if let name {
                if let other = names[name] {
                    problem("名前「\(name)」が \(other) 行目の項目と重なっています")
                }
                names[name] = item.line
            }

            guard let name, let license, let attribution, let category, let enabled, let origin else {
                continue
            }
            let entrySlug = slug(for: name, fallbackSeed: origin)
            if case .url = origin {
                if let other = slugs[entrySlug] {
                    problem("キャッシュの名前「\(entrySlug)」が \(other) 行目の項目と重なっています。名前を変えてください")
                }
                slugs[entrySlug] = item.line
            }
            entries.append(SourceEntry(
                name: name,
                origin: origin,
                license: license,
                attribution: attribution,
                category: category,
                enabled: enabled,
                line: item.line,
                slug: entrySlug,
                excludeSections: excludeSections,
                keepLinesContaining: keepLinesContaining
            ))
        }

        if !problems.isEmpty {
            throw RulesError("\(fileName) に問題があります：\n" + problems.map { "  - \($0)" }.joined(separator: "\n"))
        }
        return entries
    }

    /// 名前の英数字を小文字にして、それ以外を - でつなぐ（「EasyList」→「easylist」）。
    /// 英数字がない名前は、URL か path のハッシュから作る。
    static func slug(for name: String, fallbackSeed origin: SourceEntry.Origin) -> String {
        var result = ""
        var pendingDash = false
        for scalar in name.lowercased().unicodeScalars {
            if scalar.isASCII, CharacterSet.alphanumerics.contains(scalar) {
                if pendingDash, !result.isEmpty {
                    result.append("-")
                }
                pendingDash = false
                result.unicodeScalars.append(scalar)
            } else {
                pendingDash = true
            }
        }
        if result.isEmpty {
            let seed: String
            switch origin {
            case .url(let url): seed = url.absoluteString
            case .path(let path): seed = path
            }
            result = "source-" + Hashing.sha256Hex(Data(seed.utf8)).prefix(8)
        }
        return result
    }
}
