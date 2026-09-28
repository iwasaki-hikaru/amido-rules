import Foundation
import Testing
@testable import RulesKit

@Suite("拡張ごとの予算")
struct BudgetTests {
    static let config = BudgetsConfig(
        allowlistMaxDomains: 1,
        appReservedRules: 1,
        appReservedBytes: 400,
        countChange: CountChangeThreshold(relativePercent: 30, absoluteRules: 100),
        extensions: [
            "plus": ExtensionBudget(categories: [.annoyance, .scam], warnRules: 10, failRules: 20, warnBytes: 1000, failBytes: 2000),
            "basic": ExtensionBudget(categories: [.basic], warnRules: 10, failRules: 20, warnBytes: 1000, failBytes: 2000),
        ],
        fileSizeLimitBytes: 5000
    )

    func evaluate(_ lists: [RuleCategory: ListMeasure]) -> BudgetEvaluation {
        BudgetCheck.evaluate(config: Self.config, lists: lists)
    }

    @Test("件数にアプリの分（1 件）、バイト数に許可サイトの分（appReservedBytes）を足す")
    func addsReserves() throws {
        let result = evaluate([.basic: ListMeasure(rules: 5, bytes: 100)])
        let basic = try #require(result.usages.first { $0.name == "basic" })
        #expect(basic.rules == 6)
        #expect(basic.bytes == 500)
        #expect(basic.status == .ok)
        #expect(result.errors.isEmpty && result.warnings.isEmpty)
        #expect(result.usages.map(\.name) == ["basic", "plus"])
    }

    @Test("カテゴリがない拡張は、足す分だけ")
    func emptyExtension() throws {
        let plus = try #require(evaluate([:]).usages.first { $0.name == "plus" })
        #expect(plus.rules == 1)
        #expect(plus.bytes == 400)
    }

    @Test("plus は annoyance と scam の合計")
    func sumsCategories() throws {
        let plus = try #require(evaluate([
            .annoyance: ListMeasure(rules: 3, bytes: 10),
            .scam: ListMeasure(rules: 4, bytes: 20),
        ]).usages.first { $0.name == "plus" })
        #expect(plus.rules == 8)
        #expect(plus.bytes == 430)
    }

    @Test(
        "件数：警告の値を超えたら警告、上限を超えたら失敗（ちょうどは超えていない）",
        arguments: [(9, BudgetStatus.ok), (10, .warning), (19, .warning), (20, .failure)]
    )
    func ruleThresholds(rules: Int, expected: BudgetStatus) throws {
        let result = evaluate([.basic: ListMeasure(rules: rules, bytes: 1)])
        let basic = try #require(result.usages.first { $0.name == "basic" })
        #expect(basic.status == expected)
        #expect(result.errors.isEmpty == (expected != .failure))
        #expect(result.warnings.isEmpty == (expected != .warning))
    }

    @Test(
        "バイト数：警告の値を超えたら警告、上限を超えたら失敗",
        arguments: [(600, BudgetStatus.ok), (601, .warning), (1600, .warning), (1601, .failure)]
    )
    func byteThresholds(bytes: Int, expected: BudgetStatus) throws {
        let basic = try #require(evaluate([.basic: ListMeasure(rules: 1, bytes: bytes)]).usages.first { $0.name == "basic" })
        #expect(basic.status == expected)
    }

    @Test("1 ファイルは上限未満でなければ失敗")
    func fileSizeLimit() {
        // 予算（failBytes）の失敗とは別に、配信の上限を見る
        #expect(!evaluate([.scam: ListMeasure(rules: 1, bytes: 4999)]).errors.contains { $0.contains("配信の上限") })
        let result = evaluate([.scam: ListMeasure(rules: 1, bytes: 5000)])
        #expect(result.errors.contains { $0.contains("配信の上限") })
    }

    @Test("設定の検査：カテゴリの重なり・抜け・警告と上限の逆転")
    func validation() {
        var overlapping = Self.config
        overlapping.extensions["basic"]?.categories = [.basic, .scam]
        #expect(throws: RulesError.self) { try overlapping.validate() }

        var missing = Self.config
        missing.extensions["plus"]?.categories = [.annoyance]
        #expect(throws: RulesError.self) { try missing.validate() }

        var inverted = Self.config
        inverted.extensions["basic"]?.warnRules = 30
        #expect(throws: RulesError.self) { try inverted.validate() }

        var tooSmallReserve = Self.config
        tooSmallReserve.appReservedBytes = RuleConstants.maxAllowlistRuleBytes(domainCount: 1) - 1
        #expect(throws: RulesError.self) { try tooSmallReserve.validate() }

        #expect(throws: Never.self) { try Self.config.validate() }
    }

    @Test("許可サイトのルールの最大バイト数は、実際に作った最大のルールと一致する")
    func maxAllowlistRuleBytes() throws {
        for count in [1, 2, 500] {
            let domains = (0..<count).map { index in
                String(format: "%03d", index) + String(repeating: "a", count: 59) + "." + String(repeating: "b", count: 63)
                    + "." + String(repeating: "c", count: 63) + "." + String(repeating: "d", count: 62)
            }
            #expect(domains.allSatisfy { $0.utf8.count == RuleConstants.maxDomainLength })
            let rule = #"{"trigger":{"url-filter":".*","if-domain":["# + domains.map { "\"*\($0)\"" }.joined(separator: ",")
                + #"]},"action":{"type":"ignore-previous-rules"}}"#
            #expect(RuleConstants.maxAllowlistRuleBytes(domainCount: count) == 1 + rule.utf8.count)
        }
    }

    @Test("リポジトリの config を読める。scam は plus の 2 番目")
    func repositoryConfig() throws {
        let config = try RulesConfig.load(from: TestEnvironment.rulesRoot.appending(path: "config"))
        #expect(config.budgets.appReservedRules == 1)
        #expect(config.budgets.allowlistMaxDomains == 500)
        #expect(config.budgets.appReservedBytes >= RuleConstants.maxAllowlistRuleBytes(domainCount: 500))
        #expect(config.budgets.fileSizeLimitBytes == 25 * 1024 * 1024)
        #expect(config.budgets.extensionName(containing: .scam) == "plus")
        #expect(config.budgets.isFirstInExtension(.basic))
        #expect(config.budgets.isFirstInExtension(.annoyance))
        #expect(!config.budgets.isFirstInExtension(.scam))
        #expect(config.distribution.minAppBuild >= 1)
    }
}

@Suite("件数の変化の検査")
struct CountChangeTests {
    let threshold = CountChangeThreshold(relativePercent: 30, absoluteRules: 100)

    func evaluate(_ previous: Int, _ current: Int, allow: Bool = false) -> CountChangeEvaluation {
        CountChangeCheck.evaluate(previous: ["basic": previous], current: [.basic: current], threshold: threshold, allow: allow)
    }

    @Test(
        "30% を超え、かつ 100 件を超えたときだけ失敗",
        arguments: [
            (1000, 1200, false), // +20%、+200
            (1000, 1300, false), // +30% ちょうど
            (1000, 1301, true), // +30.1%、+301
            (1000, 500, true), // -50%、-500
            (100, 190, false), // +90% でも +90 件
            (100_000, 100_500, false), // +500 件でも +0.5%
            (200, 301, true), // +50.5%、+101
            (200, 300, false), // +100 件ちょうど
        ]
    )
    func thresholds(previous: Int, current: Int, fails: Bool) {
        let result = evaluate(previous, current)
        #expect(result.errors.isEmpty == !fails, "\(previous) → \(current)")
        #expect(result.entries.first?.status == (fails ? .exceeded : .ok))
        #expect(result.entries.first?.delta == current - previous)
    }

    @Test("許可すれば、失敗の代わりに警告")
    func allowed() {
        let result = evaluate(1000, 100, allow: true)
        #expect(result.errors.isEmpty)
        #expect(result.warnings.count == 1)
        #expect(result.entries.first?.status == .exceeded)
    }

    @Test("カテゴリがなくなったら失敗（許可すれば警告）")
    func removedCategory() {
        let removed = CountChangeCheck.evaluate(
            previous: ["basic": 10, "annoyance": 5], current: [.basic: 10], threshold: threshold, allow: false
        )
        #expect(removed.errors.count == 1)
        #expect(removed.entries.map(\.status) == [.ok, .removed])
        let allowed = CountChangeCheck.evaluate(
            previous: ["basic": 10, "annoyance": 5], current: [.basic: 10], threshold: threshold, allow: true
        )
        #expect(allowed.errors.isEmpty)
        #expect(allowed.warnings.count == 1)
    }

    @Test("新しいカテゴリは比べない")
    func addedCategory() {
        let result = CountChangeCheck.evaluate(
            previous: ["basic": 10], current: [.basic: 10, .scam: 50_000], threshold: threshold, allow: false
        )
        #expect(result.errors.isEmpty)
        #expect(result.entries.map(\.status) == [.ok, .added])
    }
}
