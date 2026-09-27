// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import os

/// 许可证窗口（app-shell.md「组件契约」）：单实例只读文本窗口，显示随 App 打包的
/// LICENSE 全文；断网时也能查看（内容来自本地资源，无网络访问）。
@MainActor
final class LicenseWindowController {
    private let window: NSWindow

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: .licenseWindowTitle)

        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 560))
        let license = Self.loadLicenseText()
        // 空内容只在构建破损（LICENSE 未打包）时出现；此时显示诊断文本而不是无声的空白窗口。
        textView.string = license.isEmpty ? "LICENSE could not be loaded from the app bundle." : license
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 560))
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        window.contentView = scrollView
        window.center()
    }

    /// 显示许可证窗口（单实例由 AppDelegate 持有，重复调用只带到最前）。
    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// 从 App 包读取 LICENSE 全文；读取失败记日志并显示空内容
    /// （LICENSE 经 project.yml 打包，正常构建必然存在；失败即构建破损，不能静默当作"没有许可证"）。
    /// 纯读取，nonisolated 供 L2 直接调用。
    nonisolated static func loadLicenseText() -> String {
        do {
            guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            Log.data.error("读取打包的 LICENSE 失败：\(error.localizedDescription, privacy: .public)")
            return ""
        }
    }
}
