// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 启动参数（conventions.md「偏好设置与调试启动参数」）：格式为 `-Shike<名称> <值>`，也接受 `-Shike<名称>=<值>`。
struct LaunchOptions: Sendable, Equatable {
    /// `-ShikeDataDirectory` 解析结果：展开 `~` 后不是绝对路径即为 invalid，绝不退回默认目录。
    enum DataDirectory: Sendable, Equatable {
        case `default`
        case custom(URL)
        /// 保存展开后的原始路径；交给 AppDatabase.open 的绝对路径校验按"打不开"处理。
        case invalid(expandedPath: String)
    }

    let simulateDatabaseOpenFailure: Bool
    let simulateWriteFailure: Bool
    let dataDirectory: DataDirectory

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        /// 取旗标的值：支持 `-Flag 值` 与 `-Flag=值` 两种写法。
        /// 裸旗标（后面没有值）返回空串，而不是当作未指定——避免手敲漏值时静默退回真实数据目录。
        func value(of flag: String) -> String? {
            for (index, argument) in arguments.enumerated() {
                if argument == flag {
                    return index + 1 < arguments.endIndex ? arguments[index + 1] : ""
                }
                if argument.hasPrefix(flag + "=") {
                    return String(argument.dropFirst(flag.count + 1))
                }
            }
            return nil
        }

        func flag(_ flag: String) -> Bool {
            value(of: flag)?.caseInsensitiveCompare("YES") == .orderedSame
        }

        self.simulateDatabaseOpenFailure = flag("-ShikeSimulateDatabaseOpenFailure")
        self.simulateWriteFailure = flag("-ShikeSimulateWriteFailure")

        if let raw = value(of: "-ShikeDataDirectory") {
            let expanded = (raw as NSString).expandingTildeInPath
            if expanded.hasPrefix("/") {
                self.dataDirectory = .custom(URL(fileURLWithPath: expanded, isDirectory: true))
            } else {
                self.dataDirectory = .invalid(expandedPath: expanded)
            }
        } else {
            self.dataDirectory = .default
        }
    }

    /// 默认数据目录（app-shell.md「LaunchOptions」）。
    static let defaultDirectory = URL(
        fileURLWithPath: ("~/Library/Application Support/Shike" as NSString).expandingTildeInPath,
        isDirectory: true
    )
}
