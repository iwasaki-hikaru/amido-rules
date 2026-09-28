// swift-tools-version: 6.0
// rulestool：ルールの取得・変換・検査・署名・配信の準備をするツール（外部依存なし）。
// 変換器（SafariConverterLib の ConverterTool、GPLv3）は別のプログラムとして呼び出すだけで、リンクしない。
// WebKit での実コンパイルがあるので macOS だけで動かす。
import PackageDescription

let package = Package(
    name: "RulesTool",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "rulestool", targets: ["rulestool"]),
        .library(name: "RulesKit", targets: ["RulesKit"]),
    ],
    targets: [
        .target(name: "RulesKit"),
        .executableTarget(name: "rulestool", dependencies: ["RulesKit"]),
        .testTarget(name: "RulesKitTests", dependencies: ["RulesKit"]),
    ]
)
