// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ShikeData

/// 管理应用生命周期；启动流程见 architecture-diagrams.md §3。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `-ShikeSimulateDatabaseOpenFailure` 只让第一次尝试失败（failure-modes.md「打开失败提示」）。
    private var simulatedOpenFailureUsed = false

    private(set) var environment: AppEnvironment?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试宿主下跳过全部启动步骤：不创建数据目录、不写真实偏好、不打开库（CAP-11）。
        guard ProcessInfo.processInfo.environment["SHIKE_TEST_HOST"] != "1" else { return }

        let launchOptions = LaunchOptions()

        // 数据目录：默认目录，或参数指定；无效路径不退回默认，走"打不开"提示。
        let dataDirectory: URL
        switch launchOptions.dataDirectory {
        case .default:
            dataDirectory = LaunchOptions.defaultDirectory
        case .custom(let url):
            dataDirectory = url
        case .invalid(let expandedPath):
            dataDirectory = URL(fileURLWithPath: expandedPath)
        }

        // 打开数据库；失败进入提示循环（architecture-diagrams.md §4）。
        let database: AppDatabase
        open: while true {
            do {
                database = try openDatabase(into: dataDirectory, launchOptions: launchOptions)
                break
            } catch {
                let dataError = (error as? ShikeDataError) ?? ShikeDataError.openFailed(.unknown(code: -1))
                Log.data.error("数据库打开失败：\(dataError.classification, privacy: .public)")
                alert: while true {
                    switch DatabaseOpenFailureAlert.present(error: dataError, dataDirectory: dataDirectory) {
                    case .retry:
                        continue open
                    case .openFolder:
                        DatabaseOpenFailureAlert.openInFinder(dataDirectory)
                        continue alert
                    case .quit:
                        NSApp.terminate(nil)
                        return
                    }
                }
            }
        }

        // 组装点：数据目录一并传入（app-shell.md「组件契约」）。
        environment = AppEnvironment(
            database: database,
            preferences: Preferences(defaults: .standard),
            dataDirectory: dataDirectory
        )
        // 主菜单、菜单栏图标、面板与备份由 Story 1.9～1.13 接入（§3 的后续节点）。
        Log.app.info("启动完成")
    }

    private func openDatabase(into directory: URL, launchOptions: LaunchOptions) throws -> AppDatabase {
        if launchOptions.simulateDatabaseOpenFailure && !simulatedOpenFailureUsed {
            simulatedOpenFailureUsed = true
            throw ShikeDataError.openFailed(.simulated)
        }
        let options = AppDatabase.Options(simulateWriteFailure: launchOptions.simulateWriteFailure)
        return try AppDatabase.open(directory: directory, options: options)
    }
}
