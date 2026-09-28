// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo Services/RightClickMenuHelper.swift 移植；去掉单例与重载数据、
// 检查更新等与更新相关的菜单项；S1-09 起菜单为 03 §2 的阶段 1 形态：打开拾刻、设置…、
// 开机自启（勾选）、关于拾刻、退出拾刻；动作经闭包回调 AppDelegate（2026-09-28）。

import AppKit

/// 图标右键菜单（app-shell.md「组件契约」）：只在右键时临时挂到图标上，关闭后卸下。
@MainActor
final class StatusMenu: NSObject {
    struct Actions {
        let openPanel: () -> Void
        let openSettings: () -> Void
        let toggleLaunchAtLogin: () -> Void
        let launchAtLoginEnabled: () -> Bool
        let openAbout: () -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(
            title: String(localized: .menuOpen),
            action: #selector(openPanelAction),
            keyEquivalent: ""
        )
        open.target = self
        menu.addItem(open)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: String(localized: .menuSettings),
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let launchAtLogin = NSMenuItem(
            title: String(localized: .menuLaunchAtLogin),
            action: #selector(toggleLaunchAtLoginAction),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = actions.launchAtLoginEnabled() ? .on : .off
        menu.addItem(launchAtLogin)

        let about = NSMenuItem(
            title: String(localized: .menuAbout),
            action: #selector(openAboutAction),
            keyEquivalent: ""
        )
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: String(localized: .menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quit)

        return menu
    }

    @objc private func openPanelAction() {
        actions.openPanel()
    }

    @objc private func openSettingsAction() {
        actions.openSettings()
    }

    @objc private func toggleLaunchAtLoginAction() {
        actions.toggleLaunchAtLogin()
    }

    @objc private func openAboutAction() {
        actions.openAbout()
    }
}
