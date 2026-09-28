import Foundation

/// ConverterTool の標準出力（JSON）。
public struct ConverterResult: Codable, Sendable, Equatable {
    public var sourceRulesCount: Int
    public var sourceSafariCompatibleRulesCount: Int
    public var safariRulesCount: Int
    public var advancedRulesCount: Int
    public var discardedSafariRules: Int
    public var errorsCount: Int
    /// Safari 形式のルールの JSON 配列（文字列のまま）。配信するファイルは、このバイト列そのもの。
    public var safariRulesJSON: String
}

/// SafariConverterLib の ConverterTool を、別のプログラムとして実行する（GPL のコードをリンクしないため）。
public struct ConverterRunner: Sendable {
    public var executable: URL

    public init(executable: URL) {
        self.executable = executable
    }

    /// 呼び出すときの引数。
    /// - `--safari-version 17`：省くと新しい Safari 向けのキーが出る（内部では 16.4 扱いで iOS 17 に合う）
    /// - `--input-path`：標準入力で渡すと、最初の空行で読み込みが止まる
    public static func arguments(inputPath: String) -> [String] {
        ["convert", "--safari-version", "17", "--advanced-blocking", "false", "--input-path", inputPath]
    }

    /// 変換器に渡す環境変数。
    ///
    /// 変換器（Swift 製）は、実行のたびに Swift のハッシュの種が変わるので、ドメインごとの要素隠しのルールの
    /// 並びが毎回入れ替わる（中身と例外ルールの位置は同じ。EasyList で 58,950 件中 4,000 件ほどが動く）。
    /// そのままだと、入力が同じでも sha256 が毎回変わり、compare が必ず changed になって、利用者が同じ
    /// 中身を取り直すことになる。SWIFT_DETERMINISTIC_HASHING=1 で種を固定し、同じ入力から同じバイト列を作る。
    /// 出力には手を加えない。
    public static func environment(_ base: [String: String]) -> [String: String] {
        var environment = base
        environment["SWIFT_DETERMINISTIC_HASHING"] = "1"
        return environment
    }

    public func convert(inputFile: URL) async throws -> ConverterResult {
        let executablePath = executable.path(percentEncoded: false)
        guard FileManager.default.isExecutableFile(atPath: executablePath) else {
            throw RulesError("変換器が見つからないか、実行できません：\(executablePath)（scripts/fetch-converter.sh でビルドしてください）")
        }

        // 出力は数 MB になるので、パイプではなく一時ファイルに受ける（パイプが詰まって止まるのを避ける）
        let temporary = FileManager.default.temporaryDirectory.appending(path: "rulestool-convert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let stdoutURL = temporary.appending(path: "stdout.json")
        let stderrURL = temporary.appending(path: "stderr.txt")
        FileManager.default.createFile(atPath: stdoutURL.path(percentEncoded: false), contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path(percentEncoded: false), contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)

        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(inputPath: inputFile.path(percentEncoded: false))
        process.environment = Self.environment(ProcessInfo.processInfo.environment)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: RulesError("変換器を起動できません：\(error.localizedDescription)"))
            }
        }
        let reason = process.terminationReason
        try? stdoutHandle.close()
        try? stderrHandle.close()

        let stdout = (try? Data(contentsOf: stdoutURL)) ?? Data()
        let stderr = String(decoding: (try? Data(contentsOf: stderrURL)) ?? Data(), as: UTF8.self)
        let stderrTail = stderr.split(separator: "\n").suffix(20).joined(separator: "\n")

        guard reason == .exit, status == 0 else {
            let how = reason == .exit ? "終了コード \(status)" : "シグナル \(status)"
            throw RulesError("変換器が失敗しました（\(how)）。\n\(stderrTail)")
        }
        do {
            return try JSONDecoder().decode(ConverterResult.self, from: stdout)
        } catch {
            throw RulesError("変換器の出力を JSON として読めません：\(describe(error))\n\(stderrTail)")
        }
    }
}
