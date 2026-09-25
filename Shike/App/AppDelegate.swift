// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

/// 管理应用生命周期。启动流程（打开数据库、创建界面控制器等）
/// 按 architecture-diagrams.md §3 由后续故事逐步补入。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试宿主下不做任何启动动作：不打开库、不建菜单栏图标（CAP-11）。
        guard ProcessInfo.processInfo.environment["SHIKE_TEST_HOST"] != "1" else { return }

        // 正常启动的流程（组装、打开数据库、创建界面控制器）
        // 按 architecture-diagrams.md §3 由 Story 1.7～1.9 补入；本故事只建立生命周期骨架。
    }
}
