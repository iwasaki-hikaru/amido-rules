import Foundation

/// iOS アプリのテスト用の、署名した小さな配信一式（テスト専用）。
///
/// 署名の鍵は RFC 8032 §7.1 の TEST 1 の秘密鍵。**公開されている鍵なので、本番では絶対に使わない**。
/// manifest とリストは毎回同じバイト列になる。署名は CryptoKit の仕様で毎回変わるので、
/// すでにある .sig がそのまま検証できるなら書き換えない（fixture の差分を出さないため）。
public enum SampleFixture {
    /// RFC 8032 TEST 1 の秘密鍵（seed）と公開鍵。
    public static let testSecretKeyHex = "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60"
    public static let testPublicKeyHex = "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
    public static let keyID = "rfc8032-test1"

    public static let version = "2026.01.01.1"
    public static let publishedAt = "2026-01-01T00:00:00Z"
    public static let minAppBuild = 1

    /// テスト用のドメイン（RFC 2606 の example.com / example.org）だけに当たるルール。
    public static let basicRulesJSON = #"[{"trigger":{"url-filter":"^https?://ads\\.example\\.com/"},"action":{"type":"block"}},{"trigger":{"url-filter":".*","if-domain":["*example.org"]},"action":{"type":"css-display-none","selector":".ad-banner"}}]"#
    public static let annoyanceRulesJSON = #"[{"trigger":{"url-filter":".*","if-domain":["*example.com"]},"action":{"type":"css-display-none","selector":".popup-overlay"}}]"#

    public static var publicKeyBase64: String {
        Data(hex: testPublicKeyHex).base64EncodedString()
    }

    public static var trustedKeys: TrustedKeys {
        TrustedKeys(keys: [TrustedKeys.Key(id: keyID, publicKey: publicKeyBase64)])
    }

    public struct Written: Sendable, Equatable {
        public var manifestSHA256: String
        public var signatureRewritten: Bool
    }

    /// <dir>/v1/manifest.json・manifest.json.sig・lists/*.json と、<dir>/test-public-keys.json を書く。
    @discardableResult
    public static func write(to directory: URL) throws -> Written {
        let v1 = directory.appending(path: "v1")
        let lists: [(RuleCategory, String)] = [(.basic, basicRulesJSON), (.annoyance, annoyanceRulesJSON)]
        var entries: [Manifest.Entry] = []
        var listFiles: Set<String> = []
        for (category, json) in lists {
            let data = Data(json.utf8)
            let rules = try JSONSerialization.jsonObject(with: data) as? [Any] ?? []
            let sha256 = Hashing.sha256Hex(data)
            let path = ManifestFormat.listPath(category: category, sha256: sha256)
            try FileIO.write(data, to: v1.appending(path: path))
            listFiles.insert(ManifestFormat.listFileName(category: category, sha256: sha256))
            entries.append(Manifest.Entry(
                category: category.rawValue, url: path, sha256: sha256, size: data.count, ruleCount: rules.count
            ))
        }
        // 古い fixture のリストが残らないようにする
        let listsDirectory = v1.appending(path: "lists")
        for name in (try? FileManager.default.contentsOfDirectory(atPath: listsDirectory.path(percentEncoded: false))) ?? []
        where !listFiles.contains(name) {
            try FileManager.default.removeItem(at: listsDirectory.appending(path: name))
        }

        let manifest = Manifest(version: version, publishedAt: publishedAt, minAppBuild: minAppBuild, lists: entries)
        let manifestData = try manifest.encoded()
        let manifestURL = v1.appending(path: "manifest.json")
        try FileIO.write(manifestData, to: manifestURL)

        let signatureURL = v1.appending(path: "manifest.json.sig")
        let trusted = trustedKeys
        var rewritten = true
        if let existing = try? String(contentsOf: signatureURL, encoding: .utf8),
           (try? Signing.verify(manifest: manifestData, signatureFile: existing, trusted: trusted)) != nil {
            rewritten = false
        } else {
            let seed = Data(hex: testSecretKeyHex).base64EncodedString()
            let key = try Signing.privateKey(seedBase64: seed)
            let signed = try Signing.sign(manifest: manifestData, privateKey: key, trusted: trusted)
            try FileIO.write(Data(signed.signatureFile.utf8), to: signatureURL)
        }

        let keysFile = FixtureKeysFile(
            comment: "テスト専用：RFC 8032 TEST 1 の公開鍵。秘密鍵が公開されているので、本番では絶対に信頼しない",
            keys: trusted.keys
        )
        try FileIO.write(try JSONOutput.encoder().encode(keysFile), to: directory.appending(path: "test-public-keys.json"))
        return Written(manifestSHA256: Hashing.sha256Hex(manifestData), signatureRewritten: rewritten)
    }

    struct FixtureKeysFile: Codable {
        var comment: String
        var keys: [TrustedKeys.Key]
    }
}

extension Data {
    /// 16 進の文字列から作る（テストベクタ用。形が違えば空になる）。
    public init(hex: String) {
        var bytes: [UInt8] = []
        var iterator = hex.utf8.makeIterator()
        while let high = iterator.next(), let low = iterator.next() {
            guard let h = Self.nibble(high), let l = Self.nibble(low) else {
                self.init()
                return
            }
            bytes.append(h << 4 | l)
        }
        self.init(bytes)
    }

    private static func nibble(_ character: UInt8) -> UInt8? {
        switch character {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): character - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): character - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): character - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
