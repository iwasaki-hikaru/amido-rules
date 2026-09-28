import CryptoKit
import Foundation

/// keys/trusted-public-keys.json：`{"keys":[{"id":"primary","publicKey":"<Base64 の 32 バイト>"}]}`
public struct TrustedKeys: Codable, Sendable, Equatable {
    public struct Key: Codable, Sendable, Equatable {
        public var id: String
        public var publicKey: String

        public init(id: String, publicKey: String) {
            self.id = id
            self.publicKey = publicKey
        }
    }

    public var keys: [Key]

    public init(keys: [Key]) {
        self.keys = keys
    }

    public static func load(from url: URL) throws -> TrustedKeys {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RulesError("鍵のファイル \(url.path(percentEncoded: false)) を読めません：\(error.localizedDescription)")
        }
        let keys: TrustedKeys
        do {
            keys = try JSONDecoder().decode(TrustedKeys.self, from: data)
        } catch {
            throw RulesError("鍵のファイル \(url.path(percentEncoded: false)) の形式が正しくありません：\(describe(error))")
        }
        _ = try keys.publicKeys()
        return keys
    }

    /// 公開鍵を読む。32 バイトでないものや、id が重なるものはエラー。
    public func publicKeys() throws -> [(id: String, key: Curve25519.Signing.PublicKey)] {
        var ids: Set<String> = []
        return try keys.map { entry in
            guard !entry.id.isEmpty, ids.insert(entry.id).inserted else {
                throw RulesError("鍵の id「\(entry.id)」が空か、重なっています")
            }
            let raw = try Signing.decodeBase64(entry.publicKey, length: 32, what: "公開鍵「\(entry.id)」")
            do {
                return (entry.id, try Curve25519.Signing.PublicKey(rawRepresentation: raw))
            } catch {
                throw RulesError("公開鍵「\(entry.id)」を読めません：\(error.localizedDescription)")
            }
        }
    }
}

/// Ed25519（CryptoKit の Curve25519.Signing）での署名と検証。
///
/// CryptoKit の署名は毎回違う値になる（Apple の仕様）。同じ manifest を署名し直すと .sig は変わるが、
/// どれも正しく検証できる。テストでは値を比べず、検証できるかで確かめる。
public enum Signing {
    /// Base64（標準、パディングあり）を読む。前後の空白と改行は除く。長さが違えばエラー。
    public static func decodeBase64(_ text: String, length: Int, what: String) throws -> Data {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RulesError("\(what)が空です")
        }
        guard let data = Data(base64Encoded: trimmed) else {
            throw RulesError("\(what)が Base64 として読めません")
        }
        guard data.count == length else {
            throw RulesError("\(what)の長さが \(data.count) バイトです（\(length) バイトのはず）")
        }
        return data
    }

    /// 秘密鍵（32 バイトの seed の Base64）を読む。
    public static func privateKey(seedBase64: String) throws -> Curve25519.Signing.PrivateKey {
        let seed = try decodeBase64(seedBase64, length: 32, what: "秘密鍵（RULES_SIGNING_KEY）")
        do {
            return try Curve25519.Signing.PrivateKey(rawRepresentation: seed)
        } catch {
            throw RulesError("秘密鍵を読めません：\(error.localizedDescription)")
        }
    }

    public static func publicKeyBase64(of privateKey: Curve25519.Signing.PrivateKey) -> String {
        privateKey.publicKey.rawRepresentation.base64EncodedString()
    }

    /// manifest のバイト列に署名し、.sig の中身（Base64 と改行）を返す。
    ///
    /// 秘密鍵から求めた公開鍵が trusted にないときは署名しない（アプリが検証できない .sig を配信しないため）。
    /// 署名したあと、trusted の鍵で検証できることも確かめる。
    public static func sign(
        manifest: Data,
        privateKey: Curve25519.Signing.PrivateKey,
        trusted: TrustedKeys
    ) throws -> (signatureFile: String, keyID: String) {
        let publicKey = publicKeyBase64(of: privateKey)
        let raw = privateKey.publicKey.rawRepresentation
        guard try trusted.publicKeys().contains(where: { $0.key.rawRepresentation == raw }) else {
            throw RulesError("秘密鍵から求めた公開鍵 \(publicKey) が、信頼する鍵のファイルにありません。署名しません")
        }
        let signature: Data
        do {
            signature = try privateKey.signature(for: manifest)
        } catch {
            throw RulesError("署名できません：\(error.localizedDescription)")
        }
        let signatureFile = signature.base64EncodedString() + "\n"
        let keyID = try verify(manifest: manifest, signatureFile: signatureFile, trusted: trusted)
        return (signatureFile, keyID)
    }

    /// .sig の中身で manifest のバイト列を検証し、検証できた鍵の id を返す。
    public static func verify(manifest: Data, signatureFile: String, trusted: TrustedKeys) throws -> String {
        let signature = try decodeBase64(signatureFile, length: 64, what: "署名（manifest.json.sig）")
        let keys = try trusted.publicKeys()
        guard !keys.isEmpty else {
            throw RulesError("信頼する公開鍵が 1 本もありません（keys/trusted-public-keys.json）")
        }
        for (id, key) in keys where key.isValidSignature(signature, for: manifest) {
            return id
        }
        throw RulesError("署名を検証できません（manifest が改ざんされたか、鍵が違います）")
    }

    /// 新しい鍵を作る。返すのは seed と公開鍵の Base64。
    public static func generateKey() -> (seedBase64: String, publicKeyBase64: String) {
        let key = Curve25519.Signing.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), publicKeyBase64(of: key))
    }

    /// 秘密鍵のファイルを、持ち主だけが読める権限（0600）で新しく作る。すでにあれば上書きしない。
    public static func writeSecretFile(_ contents: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let path = url.path(percentEncoded: false)
        // O_EXCL で「なければ作る」を 1 回で行う（確かめてから作る間に、別のファイルができる隙をなくす）
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else {
            if errno == EEXIST {
                throw RulesError("\(path) はすでにあります。上書きしません")
            }
            throw RulesError("\(path) を作れません：\(String(cString: strerror(errno)))")
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: Data(contents.utf8))
            try handle.close()
        } catch {
            throw RulesError("\(path) に書けません：\(error.localizedDescription)")
        }
    }
}
