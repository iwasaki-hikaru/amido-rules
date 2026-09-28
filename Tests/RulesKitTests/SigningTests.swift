import CryptoKit
import Foundation
import Testing
@testable import RulesKit

/// RFC 8032 §7.1 のテストベクタ（アプリの BlockerCore と共通）。
struct RFC8032Vector: Sendable, CustomTestStringConvertible {
    var name: String
    var secretKey: String
    var publicKey: String
    var message: String
    var signature: String

    var testDescription: String { name }

    static let all = [
        RFC8032Vector(
            name: "TEST 1",
            secretKey: "9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60",
            publicKey: "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a",
            message: "",
            signature: "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
        ),
        RFC8032Vector(
            name: "TEST 2",
            secretKey: "4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb",
            publicKey: "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c",
            message: "72",
            signature: "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
        ),
        RFC8032Vector(
            name: "TEST 3",
            secretKey: "c5aa8df43f9f837bedb7442f31dcb7b166d38535076f094b85ce3a2e0b4458f7",
            publicKey: "fc51cd8e6218a1a38da47ed00230f0580816ed13ba3303ac5deb911548908025",
            message: "af82",
            signature: "6291d657deec24024827e69c3abe01a30ce548a284743a445e3680d7db5ac3ac18ff9b538d16f290ae67f760984dc6594a7c15e9716ed28dc027beceea1ec40a"
        ),
    ]
}

@Suite("RFC 8032 のテストベクタ（CryptoKit）")
struct RFC8032Tests {
    @Test("秘密鍵から公開鍵を求められる", arguments: RFC8032Vector.all)
    func derivesPublicKey(vector: RFC8032Vector) throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(hex: vector.secretKey))
        #expect(key.publicKey.rawRepresentation == Data(hex: vector.publicKey))
    }

    @Test("RFC の署名を検証できる。1 バイト変えると検証できない", arguments: RFC8032Vector.all)
    func verifiesVectorSignature(vector: RFC8032Vector) throws {
        let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: Data(hex: vector.publicKey))
        let message = Data(hex: vector.message)
        var signature = Data(hex: vector.signature)
        #expect(signature.count == 64)
        #expect(publicKey.isValidSignature(signature, for: message))
        #expect(!publicKey.isValidSignature(signature, for: message + Data([0])))
        signature[0] ^= 0x01
        #expect(!publicKey.isValidSignature(signature, for: message))
    }

    @Test("CryptoKit の署名は毎回違うが、どれも検証できる", arguments: RFC8032Vector.all)
    func randomizedSignaturesVerify(vector: RFC8032Vector) throws {
        let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(hex: vector.secretKey))
        let message = Data(hex: vector.message)
        let first = try key.signature(for: message)
        let second = try key.signature(for: message)
        #expect(key.publicKey.isValidSignature(first, for: message))
        #expect(key.publicKey.isValidSignature(second, for: message))
    }

    @Test("Signing.verify でも、RFC の署名を .sig の形（Base64）で検証できる", arguments: RFC8032Vector.all)
    func verifiesThroughSigning(vector: RFC8032Vector) throws {
        let trusted = TrustedKeys(keys: [TrustedKeys.Key(id: vector.name, publicKey: Data(hex: vector.publicKey).base64EncodedString())])
        let signatureFile = Data(hex: vector.signature).base64EncodedString() + "\n"
        #expect(try Signing.verify(manifest: Data(hex: vector.message), signatureFile: signatureFile, trusted: trusted) == vector.name)
    }
}

@Suite("署名と検証")
struct SigningTests {
    let manifest = Data(#"{"schema" : 1, "version" : "2026.10.05.1"}"#.utf8)

    @Test("署名して検証できる（.sig は Base64 と改行）")
    func roundTrip() throws {
        let key = Curve25519.Signing.PrivateKey()
        let other = Curve25519.Signing.PrivateKey()
        let trusted = trustedKeys(other, key, ids: ["backup", "primary"])
        let signed = try Signing.sign(manifest: manifest, privateKey: key, trusted: trusted)
        #expect(signed.keyID == "primary")
        #expect(signed.signatureFile.hasSuffix("\n"))
        #expect(signed.signatureFile.count == 88 + 1)
        #expect(try Signing.verify(manifest: manifest, signatureFile: signed.signatureFile, trusted: trusted) == "primary")
    }

    @Test("前後の空白や改行があっても読める")
    func trimsWhitespace() throws {
        let key = Curve25519.Signing.PrivateKey()
        let trusted = trustedKeys(key)
        let signed = try Signing.sign(manifest: manifest, privateKey: key, trusted: trusted)
        let padded = "  \n" + signed.signatureFile.trimmingCharacters(in: .newlines) + " \r\n\n"
        #expect(try Signing.verify(manifest: manifest, signatureFile: padded, trusted: trusted) == "key0")
    }

    @Test("manifest を 1 バイトでも変えると検証できない")
    func tamperedManifest() throws {
        let key = Curve25519.Signing.PrivateKey()
        let trusted = trustedKeys(key)
        let signed = try Signing.sign(manifest: manifest, privateKey: key, trusted: trusted)
        var tampered = manifest
        tampered[tampered.startIndex] = UInt8(ascii: "[")
        #expect(throws: RulesError.self) { try Signing.verify(manifest: tampered, signatureFile: signed.signatureFile, trusted: trusted) }
        // 空白を足しただけでも、バイト列が変われば検証できない
        #expect(throws: RulesError.self) { try Signing.verify(manifest: manifest + Data(" ".utf8), signatureFile: signed.signatureFile, trusted: trusted) }
    }

    @Test("信頼する鍵が違えば検証できない")
    func wrongKey() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try Signing.sign(manifest: manifest, privateKey: key, trusted: trustedKeys(key))
        let otherTrusted = trustedKeys(Curve25519.Signing.PrivateKey())
        do {
            _ = try Signing.verify(manifest: manifest, signatureFile: signed.signatureFile, trusted: otherTrusted)
            Issue.record("検証できてしまった")
        } catch let error as RulesError {
            #expect(error.message.contains("検証できません"))
        }
    }

    @Test("信頼する鍵が 1 本もなければ検証できない")
    func noTrustedKeys() throws {
        let key = Curve25519.Signing.PrivateKey()
        let signed = try Signing.sign(manifest: manifest, privateKey: key, trusted: trustedKeys(key))
        #expect(throws: RulesError.self) { try Signing.verify(manifest: manifest, signatureFile: signed.signatureFile, trusted: TrustedKeys(keys: [])) }
    }

    @Test(
        "署名の Base64 が壊れている・長さが違う",
        arguments: [
            ("!!!not base64!!!", "Base64"),
            ("", "空"),
            (Data(count: 63).base64EncodedString(), "63 バイト"),
            (Data(count: 65).base64EncodedString(), "65 バイト"),
            (Data(count: 32).base64EncodedString(), "32 バイト"),
            (String(Data(count: 64).base64EncodedString().dropLast(2)), "Base64"),
        ]
    )
    func malformedSignature(signature: String, fragment: String) {
        let trusted = trustedKeys(Curve25519.Signing.PrivateKey())
        do {
            _ = try Signing.verify(manifest: manifest, signatureFile: signature, trusted: trusted)
            Issue.record("エラーにならなかった")
        } catch let error as RulesError {
            #expect(error.message.contains(fragment), "\(error.message)")
        } catch {
            Issue.record("想定外のエラー：\(error)")
        }
    }

    @Test("秘密鍵（seed）は 32 バイト")
    func seedLength() throws {
        let seed = Curve25519.Signing.PrivateKey().rawRepresentation
        #expect(throws: Never.self) { try Signing.privateKey(seedBase64: seed.base64EncodedString() + "\n") }
        #expect(throws: RulesError.self) { try Signing.privateKey(seedBase64: Data(count: 31).base64EncodedString()) }
        #expect(throws: RulesError.self) { try Signing.privateKey(seedBase64: Data(count: 64).base64EncodedString()) }
        #expect(throws: RulesError.self) { try Signing.privateKey(seedBase64: "not base64") }
    }

    @Test("秘密鍵の公開鍵が信頼する鍵にないときは、署名しない")
    func refusesUntrustedKey() {
        let key = Curve25519.Signing.PrivateKey()
        let trusted = trustedKeys(Curve25519.Signing.PrivateKey())
        do {
            _ = try Signing.sign(manifest: manifest, privateKey: key, trusted: trusted)
            Issue.record("署名できてしまった")
        } catch let error as RulesError {
            #expect(error.message.contains("署名しません"))
            #expect(error.message.contains(key.publicKey.rawRepresentation.base64EncodedString()))
        } catch {
            Issue.record("想定外のエラー：\(error)")
        }
        #expect(throws: RulesError.self) { try Signing.sign(manifest: manifest, privateKey: key, trusted: TrustedKeys(keys: [])) }
    }

    @Test("鍵のファイル：形式と、id の重なり・公開鍵の長さ")
    func keysFile() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "keys.json")

        let key = Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()
        try write(#"{"keys":[{"id":"primary","publicKey":"\#(key)"}]}"#, to: url)
        #expect(try TrustedKeys.load(from: url).keys.count == 1)

        try write(#"{"keys":[{"id":"a","publicKey":"\#(key)"},{"id":"a","publicKey":"\#(key)"}]}"#, to: url)
        #expect(throws: RulesError.self) { try TrustedKeys.load(from: url) }

        try write(#"{"keys":[{"id":"a","publicKey":"\#(Data(count: 31).base64EncodedString())"}]}"#, to: url)
        #expect(throws: RulesError.self) { try TrustedKeys.load(from: url) }

        try write(#"{"key":[]}"#, to: url)
        #expect(throws: RulesError.self) { try TrustedKeys.load(from: url) }
    }

    @Test("リポジトリの keys/trusted-public-keys.json は正しい形")
    func repositoryKeysFile() throws {
        _ = try TrustedKeys.load(from: TestEnvironment.rulesRoot.appending(path: "keys/trusted-public-keys.json"))
    }

    @Test("keygen：0600 で書き、上書きしない。公開鍵は秘密鍵から求めたもの")
    func keygen() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "nested/dev-signing-key")

        let generated = Signing.generateKey()
        try Signing.writeSecretFile(generated.seedBase64 + "\n", to: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        let stored = try String(contentsOf: url, encoding: .utf8)
        let key = try Signing.privateKey(seedBase64: stored)
        #expect(Signing.publicKeyBase64(of: key) == generated.publicKeyBase64)
        #expect(try Signing.decodeBase64(generated.publicKeyBase64, length: 32, what: "公開鍵").count == 32)

        do {
            try Signing.writeSecretFile("other\n", to: url)
            Issue.record("上書きできてしまった")
        } catch let error as RulesError {
            #expect(error.message.contains("上書きしません"))
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == stored)
    }
}
