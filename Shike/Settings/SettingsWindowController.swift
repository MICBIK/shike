// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// 设置窗口（03 §9）：单实例，由 AppDelegate 持有；打开时先 NSApp.activate()
/// 再 makeKeyAndOrderFront；已经打开时只带到最前，停在当前分页。
@MainActor
final class SettingsWindowController {
    let model = SettingsModel()
    private let window: NSWindow
    private let hostingController: NSHostingController<SettingsView>

    init(onViewLicense: @escaping () -> Void) {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: .settingsWindowTitle)
        hostingController = NSHostingController(rootView: SettingsView(model: model, onViewLicense: onViewLicense))
        window.contentViewController = hostingController
        window.center()
    }

    /// 显示设置窗口；`tab` 为 nil 表示停在当前分页。
    func show(tab: SettingsTab? = nil) {
        if let tab {
            model.selectedTab = tab
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // 真机验收：实测不在最前时，在此补充 orderFrontRegardless()（app-shell.md「组件契约」）。
    }
}
