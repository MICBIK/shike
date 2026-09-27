// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ShikeData

/// 打开失败提示（failure-modes.md「打开失败提示」、architecture-diagrams.md §4）。
/// 提示期间 AppEnvironment 与菜单栏图标都还不存在，App 不改用内存库、不新建空库。
@MainActor
enum DatabaseOpenFailureAlert {
    enum Action {
        case retry
        case openFolder
        case quit
    }

    static func reason(of error: ShikeDataError) -> DataFailureReason {
        switch error {
        case .openFailed(let reason),
             .readFailed(let reason),
             .writeFailed(let reason),
             .backupFailed(let reason):
            reason
        case .notFound:
            .unknown(code: 0)
        }
    }

    /// 显示提示（先 `NSApp.activate()`），返回用户的选择。按钮依次为：重试（默认）、打开数据目录、退出。
    static func present(error: ShikeDataError, dataDirectory: URL) -> Action {
        NSApp.activate()

        let alert = NSAlert()
        alert.messageText = String(localized: .dbAlertTitle)
        alert.informativeText = "\(ErrorText.reason(reason(of: error)))\n\n\(dataDirectory.path)"
        alert.addButton(withTitle: String(localized: .dbAlertRetry))
        alert.addButton(withTitle: String(localized: .dbAlertOpenFolder))
        alert.addButton(withTitle: String(localized: .dbAlertQuit))
        Log.ui.info("展示打开失败提示：\(reason(of: error).classification, privacy: .public)")

        return switch alert.runModal() {
        case NSApplication.ModalResponse.alertSecondButtonReturn: .openFolder
        case NSApplication.ModalResponse.alertThirdButtonReturn: .quit
        default: .retry
        }
    }

    /// 在访达中打开数据目录；目录不存在时打开上一级。
    static func openInFinder(_ directory: URL) {
        var target = directory
        if !FileManager.default.fileExists(atPath: target.path) {
            target = target.deletingLastPathComponent()
        }
        // open 的 Bool 只表示是否唤起了访达；失败时静默即可，提示循环随后会再次展示提示。
        _ = NSWorkspace.shared.open(target)
    }
}
