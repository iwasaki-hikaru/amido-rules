import Foundation

/// URL かローカルのパス。前の manifest（本番の URL か、手元のファイル）の指定に使う。
public enum ResourceLocation: Sendable, Equatable, CustomStringConvertible {
    case remote(URL)
    case local(URL)

    /// `https://…`（手元の確認用に、ループバックだけ `http://` も可）か、ファイルのパス。
    public static func parse(_ text: String) throws -> ResourceLocation {
        let lowered = text.lowercased()
        if lowered.hasPrefix("https://") || lowered.hasPrefix("http://") {
            guard let url = URL(string: text), url.host() != nil else {
                throw RulesError("URL が正しくありません：\(text)")
            }
            try ResourceLoader.checkRemotePolicy(url)
            return .remote(url)
        }
        if lowered.hasPrefix("file://") {
            guard let url = URL(string: text), url.isFileURL else {
                throw RulesError("URL が正しくありません：\(text)")
            }
            return .local(url)
        }
        if text.contains("://") {
            throw RulesError("https:// の URL か、ファイルのパスを指定してください：\(text)")
        }
        return .local(URL(fileURLWithPath: text))
    }

    /// manifest からの相対パス（lists/…）を、同じ場所を基準に解決する。
    public func resolving(_ relativePath: String) throws -> ResourceLocation {
        switch self {
        case .remote(let base):
            guard let url = URL(string: relativePath, relativeTo: base)?.absoluteURL,
                  url.scheme == base.scheme, url.host() == base.host(), url.port == base.port
            else {
                throw RulesError("\(relativePath) を \(base.absoluteString) からの相対 URL として解決できません")
            }
            return .remote(url)
        case .local(let base):
            return .local(base.deletingLastPathComponent().appending(path: relativePath))
        }
    }

    public var description: String {
        switch self {
        case .remote(let url): url.absoluteString
        case .local(let url): url.path(percentEncoded: false)
        }
    }
}

public enum LoadOutcome: Sendable, Equatable {
    case data(Data)
    /// 存在しない（404・410、またはファイルがない）。初回のデプロイなど、「前がない」ことを表す。
    case missing
}

public enum ResourceLoader {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        // 本番の manifest や上流のリストは、途中のキャッシュを使わずに取り直す
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.httpAdditionalHeaders = [
            "Cache-Control": "no-cache",
            "User-Agent": "rulestool",
        ]
        return URLSession(configuration: configuration)
    }()

    static func isLoopback(_ url: URL) -> Bool {
        guard let host = url.host()?.lowercased() else {
            return false
        }
        return ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host)
    }

    /// HTTPS だけを許す。手元の確認用に、ループバックの HTTP だけ例外にする。
    static func checkRemotePolicy(_ url: URL) throws {
        let scheme = url.scheme?.lowercased()
        if scheme == "https" {
            return
        }
        if scheme == "http", isLoopback(url) {
            return
        }
        throw RulesError("HTTPS の URL だけ使えます（手元の確認用の http://127.0.0.1 などは例外）：\(url.absoluteString)")
    }

    public static func load(_ location: ResourceLocation) async throws -> LoadOutcome {
        switch location {
        case .local(let url):
            guard FileIO.exists(url) else {
                return .missing
            }
            do {
                return .data(try Data(contentsOf: url))
            } catch {
                throw RulesError("\(location) を読めません：\(error.localizedDescription)")
            }
        case .remote(let url):
            try checkRemotePolicy(url)
            let (data, response): (Data, URLResponse)
            do {
                (data, response) = try await session.data(for: URLRequest(url: url))
            } catch {
                throw RulesError("\(url.absoluteString) を取得できません：\(error.localizedDescription)")
            }
            if let finalURL = response.url {
                try checkRemotePolicy(finalURL)
            }
            guard let http = response as? HTTPURLResponse else {
                throw RulesError("\(url.absoluteString) の応答が HTTP ではありません")
            }
            switch http.statusCode {
            case 200:
                return .data(data)
            case 404, 410:
                return .missing
            default:
                throw RulesError("\(url.absoluteString) の取得に失敗しました（HTTP \(http.statusCode)）")
            }
        }
    }

    /// なければエラーにする。
    public static func require(_ location: ResourceLocation) async throws -> Data {
        switch try await load(location) {
        case .data(let data):
            return data
        case .missing:
            throw RulesError("\(location) がありません")
        }
    }

    /// 上流のリストを取得して、キャッシュに書く。HTTPS だけ。
    public static func fetchSource(_ url: URL, cacheFile: URL) async throws -> Data {
        guard url.scheme?.lowercased() == "https" else {
            throw RulesError("上流のリストは HTTPS で取得します：\(url.absoluteString)")
        }
        let data: Data
        switch try await load(.remote(url)) {
        case .data(let fetched):
            data = fetched
        case .missing:
            throw RulesError("\(url.absoluteString) が見つかりません（HTTP 404）")
        }
        guard !data.isEmpty else {
            throw RulesError("\(url.absoluteString) の中身が空です")
        }
        _ = try FileIO.decodeText(data, displayName: url.absoluteString)
        try FileIO.write(data, to: cacheFile)
        return data
    }
}
