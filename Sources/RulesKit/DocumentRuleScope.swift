import Foundation

/// 変換後のリストで、「resource-type が document だけの block ルール」を、トップの文書に限る
/// （`load-context: ["top-frame"]` を足す）。
///
/// EasyList の `$popup` と、ブロックのルールの `$document` は、ポップアップとページそのもの
/// （トップの文書）を止める指定（ABP・uBlock Origin・AdGuard の定義。iframe は `$subdocument`）。
/// 変換器はこれを `resource-type: ["document"]` にするが、WebKit の document は、トップの文書にも
/// iframe の中の文書（子の文書）にも当たる。iOS 17・18 だけでなく、`top-document`・`child-document` が
/// 入った Safari 26 でも、document は両方に当たる。
/// そのため、広告ブロック対策の仕組み（html-load.com など）の iframe まで止まり、
/// サイトがページ全体を覆う警告を出して、本文が読めなくなる（2026-09-29 に WebKit で確認）。
///
/// `load-context` は Safari 15・iOS 15 から使える（WebKit 235790@main）。Apple 自身の変換
/// （Web 拡張の declarativeNetRequest の main_frame）も、document ＋ top-frame にしている。
/// iframe を止める指定（`$subdocument`）は、変換器が `load-context: ["child-frame"]` を付けるので、
/// ここでは触らない（load-context がすでにあるルールは変えない）。
///
/// 副作用：`third-party` や `if-domain` と組み合わさったもの（今の EasyList で 88 件）は、WebKit がトップの文書を
/// それ自身のページとして扱うため、トップの文書では当たらなくなる。これらはもともとポップアップを止めておらず、
/// iframe だけを止めていたので、ポップアップの防ぎ方は変わらない。
public enum DocumentRuleScope {
    public struct Result: Sendable, Equatable {
        public var data: Data
        /// load-context を足したルールの数。
        public var changed: Int
    }

    /// 変えるルールがなければ、`data` をそのまま返す（バイト列を変えない）。
    /// ルールの配列として読めないときもそのまま返す（形の問題は RuleListLint が報告する）。
    public static func restrictToTopFrame(_ data: Data) throws -> Result {
        guard var rules = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            return Result(data: data, changed: 0)
        }
        var changed = 0
        for index in rules.indices {
            guard var trigger = rules[index]["trigger"] as? [String: Any],
                  let action = rules[index]["action"] as? [String: Any],
                  action["type"] as? String == "block",
                  trigger["resource-type"] as? [String] == ["document"],
                  trigger["load-context"] == nil
            else { continue }
            trigger["load-context"] = ["top-frame"]
            rules[index]["trigger"] = trigger
            changed += 1
        }
        guard changed > 0 else {
            return Result(data: data, changed: 0)
        }
        // キーの順番を決めて、同じ入力からは同じバイト列（同じハッシュ）にする
        let output = try JSONSerialization.data(withJSONObject: rules, options: [.sortedKeys, .withoutEscapingSlashes])
        return Result(data: output, changed: changed)
    }
}
