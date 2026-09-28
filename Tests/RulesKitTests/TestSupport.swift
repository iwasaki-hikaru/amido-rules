import CryptoKit
import Foundation
@testable import RulesKit

/// テストで使う場所と道具。
enum TestEnvironment {
    /// rules/ ディレクトリ（このファイルから 3 階層上）。
    static let rulesRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // RulesKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // rules

    static let fixtures = rulesRoot.appending(path: "Tests/Fixtures")

    /// ConverterTool。環境変数 CONVERTER_PATH、なければ .tools の下のビルド済みのもの。
    static var converterURL: URL? {
        let path = ProcessInfo.processInfo.environment["CONVERTER_PATH"]
            ?? rulesRoot.appending(path: ".tools/SafariConverterLib/.build/release/ConverterTool").path(percentEncoded: false)
        return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }

    static var hasConverter: Bool { converterURL != nil }

    static let repositoryDenylist = Denylist(urlSubstrings: ["280blocker", "tofukko"])
}

func makeTemporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "RulesKitTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
}

/// テスト用の配信一式を、任意のリストと鍵で作る。`ruleCountOverride` で manifest の件数をわざと違えられる。
@discardableResult
func makeDistribution(
    in directory: URL,
    lists: [(category: RuleCategory, json: String, ruleCountOverride: Int?)],
    key: Curve25519.Signing.PrivateKey,
    trusted: TrustedKeys
) throws -> Manifest {
    let v1 = directory.appending(path: "v1")
    var entries: [Manifest.Entry] = []
    for list in lists {
        let data = Data(list.json.utf8)
        let count = (try JSONSerialization.jsonObject(with: data) as? [Any])?.count ?? 0
        let sha256 = Hashing.sha256Hex(data)
        let path = ManifestFormat.listPath(category: list.category, sha256: sha256)
        try FileManager.default.createDirectory(at: v1.appending(path: "lists"), withIntermediateDirectories: true)
        try data.write(to: v1.appending(path: path))
        entries.append(Manifest.Entry(
            category: list.category.rawValue, url: path, sha256: sha256, size: data.count,
            ruleCount: list.ruleCountOverride ?? count
        ))
    }
    let manifest = Manifest(version: "2026.02.03.1", publishedAt: "2026-02-03T04:05:06Z", minAppBuild: 1, lists: entries)
    let manifestData = try manifest.encoded()
    try manifestData.write(to: v1.appending(path: "manifest.json"))
    let signed = try Signing.sign(manifest: manifestData, privateKey: key, trusted: trusted)
    try Data(signed.signatureFile.utf8).write(to: v1.appending(path: "manifest.json.sig"))
    return manifest
}

func trustedKeys(_ keys: Curve25519.Signing.PrivateKey..., ids: [String]? = nil) -> TrustedKeys {
    TrustedKeys(keys: keys.enumerated().map { index, key in
        TrustedKeys.Key(id: ids?[index] ?? "key\(index)", publicKey: key.publicKey.rawRepresentation.base64EncodedString())
    })
}

/// 小さな、正しいルールのリスト（example.com / example.org だけ）。
enum SampleLists {
    static let basic = #"[{"trigger":{"url-filter":"^https?://ads\\.example\\.com/"},"action":{"type":"block"}}]"#
    static let annoyance = #"[{"trigger":{"url-filter":".*","if-domain":["*example.org"]},"action":{"type":"css-display-none","selector":".popup"}},{"trigger":{"url-filter":".*","if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".overlay"}}]"#
}
