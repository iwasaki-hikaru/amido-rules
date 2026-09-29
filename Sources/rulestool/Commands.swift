import Foundation
import RulesKit

/// rulestool のコマンド。終了コードは 0 成功（警告は可）、1 検査の失敗、2 使い方の誤り。
@MainActor
enum CommandLineTool {
    static let mainUsage = """
    使い方：swift run -c release rulestool <コマンド> [オプション]
    （rules/ のディレクトリで実行する。相対パスはそこからのパス）

    コマンド：
      build          ルールを取得・変換・検査して、manifest（署名なし）とリストを書く
      sign           manifest に署名する（秘密鍵は環境変数 RULES_SIGNING_KEY）
      verify         署名と、各リストの sha256・size・rule_count を検証する
      compare        前の manifest と比べて、配信するものが変わったかを出す（changed / unchanged）
      site           配信するディレクトリ（dist/）を組み立てる
      keygen         署名の鍵を作る
      compile-check  JSON のリストを、macOS の WebKit でコンパイルする

    各コマンドの説明：rulestool <コマンド> --help
    終了コード：0 成功（警告は可）、1 検査の失敗、2 使い方の誤り
    """

    static let specs: [String: CommandSpec] = [
        "build": CommandSpec(
            name: "build",
            usage: """
            使い方：rulestool build --converter <path> --out <dir> [オプション]

            ソースを読み、カテゴリごとに変換して検査し、次のものを書く：
              <dir>/v1/manifest.json（署名なし）、<dir>/v1/lists/<category>.<hash8>.json、
              <dir>/report.json、<dir>/summary.md（GITHUB_STEP_SUMMARY 用）
            エラーがあれば manifest とリストは書かず、終了コード 1 で終わる。

              --converter <path>            ConverterTool の実行ファイル
              --out <dir>                   出力先
              --sources <path>              sources.yml（既定：sources.yml）
              --config <dir>                設定のディレクトリ（既定：config）
              --host <host>                 /check 用のルールのホスト（既定：config/distribution.json）
              --version <YYYY.MM.DD.N>      版（既定：今日（UTC）の YYYY.MM.DD.1）
              --published-at <RFC3339>      公開日時（既定：今）
              --offline                     上流のリストを取得せず、build/sources のキャッシュを使う
              --previous-manifest <url|path>  件数の比較に使う前の manifest
              --allow-count-change          件数の急な変化を許す（警告にする）
              --skip-compile-check          WebKit でのコンパイルを省く
              --compose-out <dir>           拡張ごとに合成した JSON（アプリが Safari に渡す形）を書く（配信はしない。
                                            iOS のシミュレーターでのコンパイルの確認に使う）
            """,
            valueOptions: ["converter", "out", "sources", "config", "host", "version", "published-at", "previous-manifest", "compose-out"],
            flags: ["offline", "allow-count-change", "skip-compile-check"]
        ),
        "sign": CommandSpec(
            name: "sign",
            usage: """
            使い方：RULES_SIGNING_KEY=<seed の Base64> rulestool sign --manifest <dir>/v1/manifest.json [--keys <path>]

            manifest.json のバイト列に Ed25519 で署名し、<manifest>.sig（Base64 と改行）を書く。
            秘密鍵から求めた公開鍵が鍵のファイルにないときは、署名しない。

              --manifest <path>   署名する manifest.json
              --keys <path>       信頼する公開鍵のファイル（既定：keys/trusted-public-keys.json）
            """,
            valueOptions: ["manifest", "keys"]
        ),
        "verify": CommandSpec(
            name: "verify",
            usage: """
            使い方：rulestool verify (--dir <dir> | --base-url <url>) [--keys <path>]

            署名を検証してから、各リストの sha256・size・rule_count と、JSON の配列であることを確かめる。

              --dir <dir>         build や site の出力（<dir>/v1/manifest.json を読む）
              --base-url <url>    配信元（<url>/v1/manifest.json を取得する）
              --keys <path>       信頼する公開鍵のファイル（既定：keys/trusted-public-keys.json）
            """,
            valueOptions: ["dir", "base-url", "keys"]
        ),
        "compare": CommandSpec(
            name: "compare",
            usage: """
            使い方：rulestool compare --manifest <dir>/v1/manifest.json --previous <url|path>

            min_app_build と、（カテゴリ, sha256）の組が同じなら unchanged、違えば changed を出す。
            前の manifest がない・読めないときは changed。
            """,
            valueOptions: ["manifest", "previous"]
        ),
        "site": CommandSpec(
            name: "site",
            usage: """
            使い方：rulestool site --site site --rules <dir> --out <dist> [--keep-previous <url|path>]

            site/ の中身（_headers・.assetsignore を含む）を <dist> に写し、build の出力の
            v1/manifest.json・manifest.json.sig・lists/* を <dist>/v1 に置く。

              --site <dir>                 サイトのファイル（既定：site）
              --rules <dir>                build の出力
              --out <dist>                 出力先（前の site の出力なら消して作り直す）
              --keep-previous <url|path>   本番の manifest。そのリストも置く（更新の途中の利用者が 404 にならないように）
            """,
            valueOptions: ["site", "rules", "out", "keep-previous"]
        ),
        "keygen": CommandSpec(
            name: "keygen",
            usage: """
            使い方：rulestool keygen --out <path>

            新しい Ed25519 の鍵を作る。秘密鍵（32 バイトの seed の Base64）を <path> に権限 0600 で書き、
            公開鍵の Base64 を標準出力に出す。<path> がすでにあれば上書きしない。
            """,
            valueOptions: ["out"]
        ),
        "compile-check": CommandSpec(
            name: "compile-check",
            usage: """
            使い方：rulestool compile-check <file.json>...

            各ファイルを、macOS の WebKit（WKContentRuleListStore）でコンパイルする。
            """,
            acceptsPositionals: true
        ),
        "fixture": CommandSpec(
            name: "fixture",
            usage: """
            使い方：rulestool fixture --out <dir>

            iOS アプリのテスト用に、RFC 8032 TEST 1 の鍵（テスト専用）で署名した小さな配信一式を書く。
            """,
            valueOptions: ["out"]
        ),
    ]

    static func main(_ arguments: [String]) async -> Int32 {
        guard let command = arguments.first else {
            printError(mainUsage)
            return 2
        }
        if ["help", "-h", "--help"].contains(command) {
            print(mainUsage)
            return 0
        }
        guard let spec = specs[command] else {
            printError("エラー：「\(command)」というコマンドはありません\n\n\(mainUsage)")
            return 2
        }
        let rest = Array(arguments.dropFirst())
        if rest.contains("--help") || rest.contains("-h") {
            print(spec.usage)
            return 0
        }
        do {
            let parsed = try ArgumentReader.parse(rest, spec: spec)
            switch command {
            case "build": return try await build(parsed)
            case "sign": return try sign(parsed)
            case "verify": return try await verify(parsed)
            case "compare": return try await compare(parsed)
            case "site": return try await site(parsed)
            case "keygen": return try keygen(parsed)
            case "compile-check": return try await compileCheck(parsed)
            case "fixture": return try fixture(parsed)
            default: return 2
            }
        } catch let error as UsageError {
            printError("エラー：\(error.message)\n\n\(spec.usage)")
            return 2
        } catch {
            printError("エラー：\(error.localizedDescription)")
            return 1
        }
    }

    // MARK: - build

    static func build(_ arguments: ParsedArguments) async throws -> Int32 {
        let options = BuildOptions(
            converter: fileURL(try arguments.required("converter")),
            outDirectory: fileURL(try arguments.required("out")),
            sourcesFile: fileURL(arguments.value("sources") ?? "sources.yml"),
            configDirectory: fileURL(arguments.value("config") ?? "config"),
            host: arguments.value("host"),
            version: arguments.value("version"),
            publishedAt: arguments.value("published-at"),
            offline: arguments.flag("offline"),
            previousManifest: arguments.value("previous-manifest"),
            allowCountChange: arguments.flag("allow-count-change"),
            skipCompileCheck: arguments.flag("skip-compile-check"),
            composeDirectory: arguments.value("compose-out").map(fileURL)
        )
        let report = await BuildPipeline.run(options) { printError($0) }

        printError("")
        for warning in report.warnings {
            printError("警告：\(warning)")
        }
        for error in report.errors.prefix(100) {
            printError("エラー：\(error)")
        }
        if report.errors.count > 100 {
            printError("……ほか \(report.errors.count - 100) 件のエラー（report.json を参照）")
        }
        for category in report.categories where category.included {
            printError("  \(category.category)：\(category.ruleCount) 件、\(category.bytes) バイト → \(category.file ?? "")")
        }
        for usage in report.extensions {
            printError("  拡張 \(usage.name)：\(usage.rules) 件（上限 \(usage.failRules)）、\(usage.bytes) バイト（上限 \(usage.failBytes)）［\(usage.status.rawValue)］")
        }
        let out = displayPath(options.outDirectory)
        printError("report：\(out)/report.json、summary：\(out)/summary.md")
        if report.ok {
            printError("成功：\(out)/v1/manifest.json を書きました（版 \(report.version ?? "-")、警告 \(report.warnings.count) 件）")
            return 0
        }
        printError("失敗：エラー \(report.errors.count) 件")
        return 1
    }

    // MARK: - sign / verify / keygen

    static func sign(_ arguments: ParsedArguments) throws -> Int32 {
        let manifestURL = fileURL(try arguments.required("manifest"))
        let keysURL = fileURL(arguments.value("keys") ?? "keys/trusted-public-keys.json")
        guard let seed = ProcessInfo.processInfo.environment["RULES_SIGNING_KEY"],
              !seed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            printError("エラー：環境変数 RULES_SIGNING_KEY に秘密鍵（32 バイトの seed の Base64）を入れてください")
            return 1
        }
        let manifestData: Data
        do {
            manifestData = try Data(contentsOf: manifestURL)
        } catch {
            throw RulesError("\(manifestURL.path(percentEncoded: false)) を読めません：\(error.localizedDescription)")
        }
        let manifest = try Manifest.decode(manifestData)
        let problems = manifest.problems()
        guard problems.isEmpty else {
            throw RulesError("manifest が取り決めに合っていないので署名しません：\n" + problems.map { "  - \($0)" }.joined(separator: "\n"))
        }
        let trusted = try TrustedKeys.load(from: keysURL)
        let privateKey = try Signing.privateKey(seedBase64: seed)
        let signed = try Signing.sign(manifest: manifestData, privateKey: privateKey, trusted: trusted)
        let signatureURL = URL(fileURLWithPath: manifestURL.path(percentEncoded: false) + ".sig")
        try Data(signed.signatureFile.utf8).write(to: signatureURL, options: .atomic)
        printError("署名しました：\(signatureURL.path(percentEncoded: false))（鍵 \(signed.keyID)、版 \(manifest.version)）")
        return 0
    }

    static func verify(_ arguments: ParsedArguments) async throws -> Int32 {
        let keysURL = fileURL(arguments.value("keys") ?? "keys/trusted-public-keys.json")
        let location: ResourceLocation
        switch (arguments.value("dir"), arguments.value("base-url")) {
        case (let dir?, nil):
            location = DistributionVerifier.manifestLocation(directory: fileURL(dir))
        case (nil, let base?):
            location = try DistributionVerifier.manifestLocation(baseURL: base)
        default:
            throw UsageError(message: "--dir か --base-url のどちらか 1 つを指定してください")
        }
        let trusted = try TrustedKeys.load(from: keysURL)
        let result = try await DistributionVerifier.verify(manifestAt: location, trusted: trusted)
        print("manifest：\(result.manifestLocation)")
        print("署名：OK（鍵 \(result.keyID)）")
        print("版：\(result.manifest.version)（\(result.manifest.publishedAt)）、min_app_build \(result.manifest.minAppBuild)")
        for list in result.lists {
            print("  \(list.category)：\(list.ruleCount) 件、\(list.size) バイト、sha256 OK")
        }
        print("すべて検証できました")
        return 0
    }

    static func keygen(_ arguments: ParsedArguments) throws -> Int32 {
        let url = fileURL(try arguments.required("out"))
        let generated = Signing.generateKey()
        try Signing.writeSecretFile(generated.seedBase64 + "\n", to: url)
        printError("秘密鍵を書きました：\(url.path(percentEncoded: false))（権限 0600。中身は表示しない）")
        printError("公開鍵（Base64）を標準出力に出します。keys/trusted-public-keys.json とアプリの AppConfig に登録してください")
        print(generated.publicKeyBase64)
        return 0
    }

    // MARK: - compare / site

    static func compare(_ arguments: ParsedArguments) async throws -> Int32 {
        let manifestURL = fileURL(try arguments.required("manifest"))
        let previousText = try arguments.required("previous")
        let current = try Manifest.decode(try Data(contentsOf: manifestURL))
        do {
            let location = try ResourceLocation.parse(previousText)
            switch try await ResourceLoader.load(location) {
            case .missing:
                printError("前の manifest（\(previousText)）がありません。changed として扱います")
                print("changed")
            case .data(let data):
                let previous = try Manifest.decode(data)
                let unchanged = ManifestComparison.isUnchanged(current: current, previous: previous)
                printError(unchanged
                    ? "配信するリストと min_app_build は、前の版（\(previous.version)）と同じです"
                    : "前の版（\(previous.version)）から変わっています")
                print(unchanged ? "unchanged" : "changed")
            }
        } catch {
            // 本番に届かないときは、配信し直すほうを選ぶ（同じものを配信し直しても害はない）
            printError("警告：前の manifest（\(previousText)）を読めません：\(error.localizedDescription)。changed として扱います")
            print("changed")
        }
        return 0
    }

    static func site(_ arguments: ParsedArguments) async throws -> Int32 {
        let siteURL = fileURL(arguments.value("site") ?? "site")
        let rulesURL = fileURL(try arguments.required("rules"))
        let outURL = fileURL(try arguments.required("out"))
        let keepPrevious = try arguments.value("keep-previous").map(ResourceLocation.parse)
        let result = try await SiteAssembler.assemble(site: siteURL, rules: rulesURL, out: outURL, keepPrevious: keepPrevious)
        for warning in result.warnings {
            printError("警告：\(warning)")
        }
        printError("site のファイル \(result.copiedSiteFiles) 個と、リスト \(result.lists.count) 個を置きました：\(displayPath(outURL))")
        if !result.keptPreviousLists.isEmpty {
            printError("前の版のリストも置きました：\(result.keptPreviousLists.joined(separator: "、"))")
        }
        return 0
    }

    // MARK: - compile-check / fixture

    static func compileCheck(_ arguments: ParsedArguments) async throws -> Int32 {
        guard !arguments.positionals.isEmpty else {
            throw UsageError(message: "コンパイルする JSON のファイルを指定してください")
        }
        #if canImport(WebKit)
        var failed = 0
        for path in arguments.positionals {
            do {
                let data = try Data(contentsOf: fileURL(path))
                let count = (try? JSONSerialization.jsonObject(with: data) as? [Any])?.count
                let seconds = try await CompileChecker.compile(data)
                print("OK：\(path)（\(count.map(String.init) ?? "?") 件、\(String(format: "%.2f", seconds)) 秒）")
            } catch {
                failed += 1
                printError("失敗：\(path)：\(error.localizedDescription)")
            }
        }
        return failed == 0 ? 0 : 1
        #else
        printError("エラー：この環境には WebKit がありません")
        return 1
        #endif
    }

    static func fixture(_ arguments: ParsedArguments) throws -> Int32 {
        let url = fileURL(try arguments.required("out"))
        let written = try SampleFixture.write(to: url)
        printError("テスト用の配信一式を書きました：\(displayPath(url))（RFC 8032 TEST 1 の鍵で署名。テスト専用）")
        if !written.signatureRewritten {
            printError("manifest が変わっていないので、署名はそのままにしました")
        }
        return 0
    }

    // MARK: - 補助

    static func fileURL(_ path: String) -> URL {
        URL(fileURLWithPath: path).standardizedFileURL
    }

    /// 表示用のパス。ディレクトリの URL は末尾に「/」が付くので、後ろにファイル名をつなげても「//」にならないよう外す。
    static func displayPath(_ url: URL) -> String {
        let path = url.path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    static func printError(_ message: String) {
        FileHandle.standardError.write(Data((message + "\n").utf8))
    }
}
