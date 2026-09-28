import Foundation

/// 使い方の誤り（終了コード 2）。
struct UsageError: Error {
    var message: String
}

/// コマンドが受け付けるオプション。
struct CommandSpec {
    var name: String
    var usage: String
    /// 値を取るオプション（`--out <dir>` の out）。
    var valueOptions: Set<String> = []
    /// 値を取らないオプション（`--offline`）。
    var flags: Set<String> = []
    /// オプションでない引数（compile-check のファイル）を受け付けるか。
    var acceptsPositionals = false
}

struct ParsedArguments {
    var values: [String: String] = [:]
    var flags: Set<String> = []
    var positionals: [String] = []

    func value(_ name: String) -> String? {
        values[name]
    }

    func required(_ name: String) throws -> String {
        guard let value = values[name], !value.isEmpty else {
            throw UsageError(message: "--\(name) を指定してください")
        }
        return value
    }

    func flag(_ name: String) -> Bool {
        flags.contains(name)
    }
}

/// 手書きの引数の読み取り（外部のライブラリを使わないため）。
/// `--name value` と `--name=value` の両方を受け付ける。同じオプションを 2 回書くと誤りにする。
enum ArgumentReader {
    static func parse(_ arguments: [String], spec: CommandSpec) throws -> ParsedArguments {
        var parsed = ParsedArguments()
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                guard spec.acceptsPositionals else {
                    throw UsageError(message: "余分な引数があります：\(arguments[(index + 1)...].joined(separator: " "))")
                }
                parsed.positionals += arguments[(index + 1)...]
                break
            }
            if argument.hasPrefix("--") {
                var name = String(argument.dropFirst(2))
                var inlineValue: String?
                if let equals = name.firstIndex(of: "=") {
                    inlineValue = String(name[name.index(after: equals)...])
                    name = String(name[..<equals])
                }
                if spec.valueOptions.contains(name) {
                    let value: String
                    if let inlineValue {
                        value = inlineValue
                    } else {
                        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
                            throw UsageError(message: "--\(name) の値がありません")
                        }
                        value = arguments[index + 1]
                        index += 1
                    }
                    guard parsed.values[name] == nil else {
                        throw UsageError(message: "--\(name) が 2 回あります")
                    }
                    parsed.values[name] = value
                } else if spec.flags.contains(name) {
                    guard inlineValue == nil else {
                        throw UsageError(message: "--\(name) には値を付けません")
                    }
                    parsed.flags.insert(name)
                } else {
                    throw UsageError(message: "\(spec.name) に --\(name) というオプションはありません")
                }
            } else if argument.hasPrefix("-"), argument != "-" {
                throw UsageError(message: "\(spec.name) に \(argument) というオプションはありません")
            } else {
                guard spec.acceptsPositionals else {
                    throw UsageError(message: "余分な引数「\(argument)」があります")
                }
                parsed.positionals.append(argument)
            }
            index += 1
        }
        return parsed
    }
}
