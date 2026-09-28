// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

/// 隐藏主菜单（architecture-diagrams.md §3 节点 G）：
/// 应用菜单（设置… ⌘,、退出拾刻 ⌘Q）与编辑菜单（标准编辑选择器，target 为 nil，
/// 由响应链处理——NSApp.delegate 即 AppDelegate 在链上）。没有可见菜单栏时快捷键依然可用。
@MainActor
enum MainMenu {
    static func make() -> NSMenu {
        let menu = NSMenu()

        let appMenuItem = NSMenuItem()
        menu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(item(
            title: String(localized: .menuSettings),
            action: #selector(AppDelegate.openSettingsFromMenu(_:)),
            key: ",",
            modifiers: .command
        ))
        appMenu.addItem(.separator())
        appMenu.addItem(item(
            title: String(localized: .menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            key: "q",
            modifiers: .command
        ))

        let editMenuItem = NSMenuItem()
        editMenuItem.title = String(localized: .mainMenuEdit)
        editMenuItem.submenu = editMenu()
        menu.addItem(editMenuItem)

        return menu
    }

    private static func editMenu() -> NSMenu {
        let edit = NSMenu()
        edit.addItem(item(title: String(localized: .mainMenuUndo), action: #selector(EditActionSelectors.undo(_:)), key: "z", modifiers: .command))
        edit.addItem(item(title: String(localized: .mainMenuRedo), action: #selector(EditActionSelectors.redo(_:)), key: "z", modifiers: [.command, .shift]))
        edit.addItem(item(title: String(localized: .mainMenuCut), action: #selector(NSText.cut(_:)), key: "x", modifiers: .command))
        edit.addItem(item(title: String(localized: .mainMenuCopy), action: #selector(NSText.copy(_:)), key: "c", modifiers: .command))
        edit.addItem(item(title: String(localized: .mainMenuPaste), action: #selector(NSText.paste(_:)), key: "v", modifiers: .command))
        edit.addItem(item(title: String(localized: .mainMenuSelectAll), action: #selector(NSText.selectAll(_:)), key: "a", modifiers: .command))
        return edit
    }

    private static func item(title: String, action: Selector, key: String, modifiers: NSEvent.ModifierFlags) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = nil
        return item
    }
}

/// 仅用于取得 undo:/redo: 的 selector（Swift 6 下不允许用字符串构造 Selector）；
/// 动作实际由响应链上的系统实现处理，本协议没有任何实现类型。
@objc private protocol EditActionSelectors {
    @objc(undo:) func undo(_ sender: Any?)
    @objc(redo:) func redo(_ sender: Any?)
}
