// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo AppDelegate 的菜单栏按钮相关部分（configureMenuBarButton、
// handleStatusBarButtonAction、showRightClickMenu）拆成独立控制器；去掉计数与预览、
// 隐藏图标逻辑与单例；图标固定为模板图像 note.text；右键菜单经 menuProvider 临时挂载（2026-09-27）。

import AppKit

/// 菜单栏图标控制器：左键开关面板；右键在 1.11 临时挂上 StatusMenu。
@MainActor
final class StatusItemController {
    private let statusBarItem: NSStatusItem
    private let popoverController: PopoverController

    /// 右键菜单的提供者（1.11 起 AppDelegate 注入 StatusMenu）；返回 nil 表示不响应。
    var menuProvider: (() -> NSMenu?)?

    /// 状态栏按钮（S1-02 起供全局快捷键的 toggle 提供锚点）。
    var statusBarButton: NSStatusBarButton? { statusBarItem.button }

    init(popoverController: PopoverController) {
        self.popoverController = popoverController
        self.statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenuBarButton()
    }

    private func configureMenuBarButton() {
        guard let button = statusBarItem.button else { return }
        button.image = NSImage(
            systemSymbolName: "note.text",
            accessibilityDescription: String(localized: .appName)
        )
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        // 右键也送动作：1.11 的 StatusMenu 依赖右键事件分派（app-shell.md「组件契约」）。
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.target = self
        button.action = #selector(handleStatusBarButtonAction)
    }

    @objc private func handleStatusBarButtonAction() {
        guard let event = NSApp.currentEvent, let button = statusBarItem.button else { return }
        switch event.type {
        case .rightMouseUp:
            showRightClickMenu(button: button)
        default:
            popoverController.toggle(from: button)
        }
    }

    /// 右键时临时挂上菜单，performClick 触发，随后卸下（app-shell.md「组件契约」、04 §6.2）。
    private func showRightClickMenu(button: NSStatusBarButton) {
        guard let menu = menuProvider?() else { return }
        statusBarItem.menu = menu
        button.performClick(nil)
        statusBarItem.menu = nil
    }
}
