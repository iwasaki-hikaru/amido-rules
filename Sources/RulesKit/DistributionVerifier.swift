import Foundation

/// 配信する一式（manifest・署名・リスト）を、アプリと同じ順番で検証する。
///
/// 1. 署名を、manifest の**バイト列のまま**検証する（JSON として読むのは検証のあと）
/// 2. manifest が取り決めに合っているか
/// 3. 各リストの size・sha256・JSON の配列か・rule_count
public enum DistributionVerifier {
    public struct ListResult: Sendable, Equatable {
        public var category: String
        public var ruleCount: Int
        public var size: Int
    }

    public struct Result: Sendable, Equatable {
        public var keyID: String
        public var manifest: Manifest
        public var manifestLocation: String
        public var lists: [ListResult]
    }

    /// `--dir`：build の出力（<dir>/v1/manifest.json）か、site の出力（dist/v1/…）。v1 そのものを指してもよい。
    public static func manifestLocation(directory: URL) -> ResourceLocation {
        let nested = directory.appending(path: "v1/manifest.json")
        let direct = directory.appending(path: "manifest.json")
        if !FileIO.exists(nested), FileIO.exists(direct) {
            return .local(direct)
        }
        return .local(nested)
    }

    /// `--base-url`：サイトのルート（…/v1/manifest.json を足す）。…/v1/ や …/manifest.json を指してもよい。
    public static func manifestLocation(baseURL text: String) throws -> ResourceLocation {
        var text = text
        if !text.hasSuffix("/manifest.json") {
            if !text.hasSuffix("/") {
                text += "/"
            }
            text += text.hasSuffix("/v1/") ? "manifest.json" : "v1/manifest.json"
        }
        let location = try ResourceLocation.parse(text)
        guard case .remote = location else {
            throw RulesError("--base-url には https:// の URL を指定してください：\(text)")
        }
        return location
    }

    public static func verify(
        manifestAt location: ResourceLocation,
        trusted: TrustedKeys,
        fileSizeLimitBytes: Int = ManifestFormat.defaultFileSizeLimitBytes
    ) async throws -> Result {
        let manifestData = try await ResourceLoader.require(location)
        let signatureLocation: ResourceLocation
        switch location {
        case .remote(let url):
            signatureLocation = .remote(URL(string: url.absoluteString + ".sig") ?? url)
        case .local(let url):
            signatureLocation = .local(URL(fileURLWithPath: url.path(percentEncoded: false) + ".sig"))
        }
        let signatureData = try await ResourceLoader.require(signatureLocation)
        let signatureText = try FileIO.decodeText(signatureData, displayName: "manifest.json.sig")
        let keyID = try Signing.verify(manifest: manifestData, signatureFile: signatureText, trusted: trusted)

        let manifest = try Manifest.decode(manifestData)
        let problems = manifest.problems(fileSizeLimitBytes: fileSizeLimitBytes)
        guard problems.isEmpty else {
            throw RulesError("manifest.json が取り決めに合っていません：\n" + problems.map { "  - \($0)" }.joined(separator: "\n"))
        }

        var results: [ListResult] = []
        var listProblems: [String] = []
        for entry in manifest.lists {
            let label = "\(entry.category)（\(entry.url)）"
            do {
                let data = try await ResourceLoader.require(try location.resolving(entry.url))
                if let problem = listProblem(data, entry: entry) {
                    listProblems.append("\(label)：\(problem)")
                } else {
                    results.append(ListResult(category: entry.category, ruleCount: entry.ruleCount, size: entry.size))
                }
            } catch {
                listProblems.append("\(label)：\(error.localizedDescription)")
            }
        }
        guard listProblems.isEmpty else {
            throw RulesError("リストの検証に失敗しました：\n" + listProblems.map { "  - \($0)" }.joined(separator: "\n"))
        }
        return Result(keyID: keyID, manifest: manifest, manifestLocation: location.description, lists: results)
    }

    /// リスト 1 つが manifest の記載と合っているか。
    public static func listProblem(_ data: Data, entry: Manifest.Entry) -> String? {
        if data.count != entry.size {
            return "大きさが \(data.count) バイトです（manifest では \(entry.size)）"
        }
        let hash = Hashing.sha256Hex(data)
        if hash != entry.sha256 {
            return "SHA-256 が合いません（\(hash)）"
        }
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return "JSON の配列ではありません"
        }
        if array.isEmpty {
            return "空の配列です"
        }
        if !array.allSatisfy({ $0 is [String: Any] }) {
            return "配列の要素にオブジェクトでないものがあります"
        }
        if array.count != entry.ruleCount {
            return "ルールの数が \(array.count) 件です（manifest では \(entry.ruleCount)）"
        }
        return nil
    }
}
