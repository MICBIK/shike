// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 1.8：LaunchOptions 解析三个调试参数（conventions.md「偏好设置与调试启动参数」）。
struct LaunchOptionsTests {
    @Test("无参数时：两个开关为假，数据目录为默认")
    func noArgumentsYieldsDefaults() {
        let options = LaunchOptions(arguments: [])
        #expect(!options.simulateDatabaseOpenFailure)
        #expect(!options.simulateWriteFailure)
        #expect(options.dataDirectory == .default)
        #expect(LaunchOptions.defaultDirectory.path.hasSuffix("Application Support/Shike"))
    }

    @Test("三个参数齐全时全部解析；-ShikeDataDirectory 展开 ~")
    func parsesAllThreeArguments() throws {
        let options = LaunchOptions(arguments: [
            "-ShikeSimulateDatabaseOpenFailure", "YES",
            "-ShikeSimulateWriteFailure", "YES",
            "-ShikeDataDirectory", "~/Documents/ShikeTest",
        ])
        #expect(options.simulateDatabaseOpenFailure)
        #expect(options.simulateWriteFailure)
        guard case .custom(let url) = options.dataDirectory else {
            Issue.record("应为 custom，实际 \(options.dataDirectory)")
            return
        }
        #expect(!url.path.contains("~"))
        #expect(url.path.hasSuffix("Documents/ShikeTest"))
    }

    @Test("-ShikeDataDirectory 为相对路径时判为无效，保留展开后的路径")
    func relativePathIsInvalid() {
        let options = LaunchOptions(arguments: ["-ShikeDataDirectory", "relative/path"])
        #expect(options.dataDirectory == .invalid(expandedPath: "relative/path"))
    }

    @Test("-ShikeDataDirectory 为 ~ 时展开为家目录绝对路径，属有效 custom")
    func tildeAloneExpandsToHome() {
        // "~" 展开为家目录绝对路径，属于有效的 custom 目录。
        let options = LaunchOptions(arguments: ["-ShikeDataDirectory", "~"])
        guard case .custom = options.dataDirectory else {
            Issue.record("~ 展开后应为绝对路径")
            return
        }
    }

    @Test("开关值大小写不敏感；缺值时按假处理")
    func yesIsCaseInsensitiveAndMissingValueIsFalse() {
        #expect(LaunchOptions(arguments: ["-ShikeSimulateWriteFailure", "yes"]).simulateWriteFailure)
        #expect(!LaunchOptions(arguments: ["-ShikeSimulateWriteFailure", "NO"]).simulateWriteFailure)
        // 参数是最后一项、没有值时：开关为假，目录判为无效
        #expect(!LaunchOptions(arguments: ["-ShikeSimulateWriteFailure"]).simulateWriteFailure)
        // 裸旗标（末尾没有值）不按"未指定"处理：目录判为无效，绝不静默退回真实数据目录
        #expect(LaunchOptions(arguments: ["-ShikeDataDirectory"]).dataDirectory == .invalid(expandedPath: ""))
    }

    @Test("接受 -Flag=值 写法")
    func equalsSyntax() {
        let options = LaunchOptions(arguments: [
            "-ShikeSimulateWriteFailure=YES",
            "-ShikeDataDirectory=/tmp/shike-eq",
        ])
        #expect(options.simulateWriteFailure)
        #expect(options.dataDirectory == .custom(URL(fileURLWithPath: "/tmp/shike-eq", isDirectory: true)))
        // 空值（-Flag=）同样判为无效
        #expect(LaunchOptions(arguments: ["-ShikeDataDirectory="]).dataDirectory == .invalid(expandedPath: ""))
    }
}

/// Story 1.8：ErrorText 覆盖 11 种原因，文案与 app-shell.md「阶段 0 文案」表逐字一致。
struct ErrorTextTests {
    @Test("每种原因都有不为空的文案")
    func everyReasonHasNonEmptyText() {
        let reasons: [DataFailureReason] = [
            .diskFull, .readOnly, .permissionDenied, .corrupted, .busy, .newerSchema,
            .ioError, .constraintViolation, .invalidLocation, .simulated, .unknown(code: 23),
        ]
        for reason in reasons {
            #expect(!ErrorText.reason(reason).isEmpty, "\(reason) 的文案为空")
        }
    }

    @Test("文案与文案表逐字一致")
    func matchesCopyTable() {
        #expect(ErrorText.reason(.diskFull) == "磁盘空间不足")
        #expect(ErrorText.reason(.readOnly) == "数据文件是只读的")
        #expect(ErrorText.reason(.permissionDenied) == "没有访问数据目录的权限")
        #expect(ErrorText.reason(.corrupted) == "数据文件已损坏")
        #expect(ErrorText.reason(.busy) == "数据文件正被占用，请稍后重试")
        #expect(ErrorText.reason(.newerSchema) == "数据文件来自更新版本的拾刻")
        #expect(ErrorText.reason(.ioError) == "读写数据文件时出错")
        #expect(ErrorText.reason(.constraintViolation) == "数据不符合约束（程序错误）")
        #expect(ErrorText.reason(.invalidLocation) == "数据目录路径无效")
        #expect(ErrorText.reason(.simulated) == "模拟的错误（调试参数）")
        #expect(ErrorText.reason(.unknown(code: 23)) == "未知错误（代码 23）")
    }
}
