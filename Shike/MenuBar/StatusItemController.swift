// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo AppDelegate 的菜单栏按钮相关部分（configureMenuBarButton、
// handleStatusBarButtonAction）拆成独立控制器；去掉计数与预览、隐藏图标逻辑与单例；
// 图标固定为模板图像 note.text；右键菜单暂不响应（1.11 接 StatusMenu）（2026-09-27）。

import AppKit

/// 菜单栏图标控制器：左键开关面板；右键在 1.11 临时挂上 StatusMenu。
@MainActor
final class StatusItemController {
    private let statusBarItem: NSStatusItem
    private let popoverController: PopoverController

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
            // 右键菜单在 Story 1.11 提供；本阶段右键不响应。
            break
        default:
            popoverController.toggle(from: button)
        }
    }
}
