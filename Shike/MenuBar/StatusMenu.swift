// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo Services/RightClickMenuHelper.swift 移植；去掉单例与重载数据、
// 检查更新等与更新相关的菜单项；菜单项换成拾刻的三项（设置…、关于拾刻、退出拾刻），
// 动作经闭包回调 AppDelegate（2026-09-27）。

import AppKit

/// 图标右键菜单（app-shell.md「组件契约」）：只在右键时临时挂到图标上，关闭后卸下。
@MainActor
final class StatusMenu: NSObject {
    struct Actions {
        let openSettings: () -> Void
        let openAbout: () -> Void
    }

    private let actions: Actions

    init(actions: Actions) {
        self.actions = actions
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let settings = NSMenuItem(
            title: String(localized: .menuSettings),
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

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

    @objc private func openSettingsAction() {
        actions.openSettings()
    }

    @objc private func openAboutAction() {
        actions.openAbout()
    }
}
