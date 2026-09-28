import Foundation

/// 配信するディレクトリ（dist/）を組み立てる。
///
/// site/ の中身（_headers と .assetsignore も含む）をそのまま写し、build の出力の v1/ を足す。
/// `keepPrevious` を指定すると、本番の manifest が指しているリストも dist/v1/lists に置く。
/// 更新の途中の利用者（古い manifest を読んだ直後の人）が、リストの取得で 404 にならないようにするため。
public enum SiteAssembler {
    public struct Result: Sendable, Equatable {
        public var copiedSiteFiles: Int
        public var lists: [String]
        public var keptPreviousLists: [String]
        public var warnings: [String]
    }

    public static func assemble(
        site: URL,
        rules: URL,
        out: URL,
        keepPrevious: ResourceLocation?,
        fileSizeLimitBytes: Int = ManifestFormat.defaultFileSizeLimitBytes
    ) async throws -> Result {
        let fileManager = FileManager.default
        var warnings: [String] = []

        guard FileIO.isDirectory(site) else {
            throw RulesError("site のディレクトリがありません：\(site.path(percentEncoded: false))")
        }
        if FileIO.exists(site.appending(path: "v1")) {
            throw RulesError("site/ の中に v1 があります。v1 はツールが作るので、site/ には置かないでください")
        }
        if !FileIO.exists(site.appending(path: "_headers")) {
            warnings.append("site/_headers がありません（.sig の Content-Type などが既定のままになる）")
        }

        let rulesV1 = rules.appending(path: "v1")
        let manifestURL = rulesV1.appending(path: "manifest.json")
        guard FileIO.exists(manifestURL) else {
            throw RulesError("\(manifestURL.path(percentEncoded: false)) がありません。先に build を実行してください")
        }
        let manifest = try Manifest.decode(try Data(contentsOf: manifestURL))
        let signatureURL = rulesV1.appending(path: "manifest.json.sig")
        if !FileIO.exists(signatureURL) {
            warnings.append("manifest.json.sig がありません（署名していない manifest は、アプリが受け入れない）")
        }

        try prepareOutputDirectory(out)
        try fileManager.copyItem(at: site, to: out)
        removeFinderFiles(in: out)
        let copiedSiteFiles = countFiles(in: out)

        let outV1 = out.appending(path: "v1")
        let outLists = outV1.appending(path: "lists")
        try fileManager.createDirectory(at: outLists, withIntermediateDirectories: true)
        try fileManager.copyItem(at: manifestURL, to: outV1.appending(path: "manifest.json"))
        if FileIO.exists(signatureURL) {
            try fileManager.copyItem(at: signatureURL, to: outV1.appending(path: "manifest.json.sig"))
        }
        var lists: [String] = []
        for entry in manifest.lists {
            guard ManifestFormat.isValidListURL(entry.url) else {
                throw RulesError("manifest の url「\(entry.url)」が正しくありません")
            }
            let source = rulesV1.appending(path: entry.url)
            let data = try Data(contentsOf: source)
            if let problem = DistributionVerifier.listProblem(data, entry: entry) {
                throw RulesError("\(entry.url)：\(problem)")
            }
            try fileManager.copyItem(at: source, to: outV1.appending(path: entry.url))
            lists.append(entry.url)
        }

        var kept: [String] = []
        if let keepPrevious {
            let (keptLists, keepWarnings) = await copyPreviousLists(
                from: keepPrevious,
                into: outV1,
                fileSizeLimitBytes: fileSizeLimitBytes
            )
            kept = keptLists
            warnings += keepWarnings
        }
        return Result(copiedSiteFiles: copiedSiteFiles, lists: lists, keptPreviousLists: kept, warnings: warnings)
    }

    /// 出力先を空にする。前の site の出力（v1/manifest.json がある）か空のディレクトリだけを消す。
    /// 指定を間違えたときに、関係のないディレクトリを消さないため。
    static func prepareOutputDirectory(_ out: URL) throws {
        let fileManager = FileManager.default
        guard FileIO.exists(out) else {
            try fileManager.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
            return
        }
        let contents = (try? fileManager.contentsOfDirectory(atPath: out.path(percentEncoded: false))) ?? []
        let looksLikeOutput = FileIO.exists(out.appending(path: "v1/manifest.json"))
        guard contents.isEmpty || looksLikeOutput else {
            throw RulesError("\(out.path(percentEncoded: false)) は空でなく、site の出力にも見えません。消さずに止めます")
        }
        try fileManager.removeItem(at: out)
    }

    /// 本番の manifest が指しているリストを取得して置く。取れなくても失敗にはしない（新しい版の配信を止めないため）。
    static func copyPreviousLists(
        from location: ResourceLocation,
        into outV1: URL,
        fileSizeLimitBytes: Int
    ) async -> (kept: [String], warnings: [String]) {
        var kept: [String] = []
        var warnings: [String] = []
        let manifest: Manifest
        do {
            switch try await ResourceLoader.load(location) {
            case .missing:
                return ([], ["前の manifest（\(location)）がありません。前の版のリストは置きません（初回の配信なら正常）"])
            case .data(let data):
                manifest = try Manifest.decode(data)
            }
        } catch {
            return ([], ["前の manifest（\(location)）を読めません：\(error.localizedDescription)"])
        }
        for entry in manifest.lists {
            guard ManifestFormat.isValidListURL(entry.url) else {
                warnings.append("前の manifest の url「\(entry.url)」が正しくないので飛ばします")
                continue
            }
            let destination = outV1.appending(path: entry.url)
            if FileIO.exists(destination) {
                continue
            }
            do {
                let data = try await ResourceLoader.require(try location.resolving(entry.url))
                if let problem = DistributionVerifier.listProblem(data, entry: entry) {
                    warnings.append("前の版の \(entry.url)：\(problem)。置きません")
                    continue
                }
                try FileIO.write(data, to: destination)
                kept.append(entry.url)
            } catch {
                warnings.append("前の版の \(entry.url) を取得できません：\(error.localizedDescription)")
            }
        }
        return (kept, warnings)
    }

    static func removeFinderFiles(in directory: URL) {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for case let url as URL in enumerator where url.lastPathComponent == ".DS_Store" {
            try? fileManager.removeItem(at: url)
        }
    }

    static func countFiles(in directory: URL) -> Int {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey]
        ) else {
            return 0
        }
        var count = 0
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                count += 1
            }
        }
        return count
    }
}
