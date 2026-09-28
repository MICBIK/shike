// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Testing

@testable import Shike

/// Story 1.11：主菜单的菜单项、选择器与快捷键（app-shell.md「组件契约」、「L2 测试清单」）。
@MainActor
struct MainMenuTests {
    @Test("应用菜单：设置…（⌘,）与退出拾刻（⌘Q，terminate:）")
    func appMenuStructure() {
        let menu = MainMenu.make()
        #expect(menu.items.count == 2)

        let appItems = menu.items[0].submenu?.items ?? []
        #expect(appItems.count == 3)
        #expect(appItems[0].title == "设置…")
        #expect(appItems[0].keyEquivalent == ",")
        #expect(appItems[0].keyEquivalentModifierMask == .command)
        #expect(appItems[1].isSeparatorItem)
        #expect(appItems[2].title == "退出拾刻")
        #expect(appItems[2].action == #selector(NSApplication.terminate(_:)))
        #expect(appItems[2].keyEquivalent == "q")
        #expect(appItems[2].keyEquivalentModifierMask == .command)
    }

    @Test("编辑菜单：六项、标准选择器与快捷键，target 为 nil")
    func editMenuStructure() {
        let menu = MainMenu.make()
        let editItem = menu.items[1]
        #expect(editItem.title == "编辑")

        let expected: [(String, String, String, NSEvent.ModifierFlags)] = [
            ("撤销", "undo:", "z", .command),
            ("重做", "redo:", "z", [.command, .shift]),
            ("剪切", "cut:", "x", .command),
            ("复制", "copy:", "c", .command),
            ("粘贴", "paste:", "v", .command),
            ("全选", "selectAll:", "a", .command),
        ]
        let items = editItem.submenu?.items ?? []
        #expect(items.count == expected.count)
        for (index, want) in expected.enumerated() {
            let item = items[index]
            #expect(item.title == want.0, "第 \(index) 项标题不符")
            #expect(item.action?.description == want.1, "\(want.0) 选择器不符")
            #expect(item.keyEquivalent == want.2, "\(want.0) 快捷键不符")
            #expect(item.keyEquivalentModifierMask == want.3, "\(want.0) 修饰键不符")
            #expect(item.target == nil, "\(want.0) 应由响应链处理")
        }
    }
}

/// Story 1.11：设置分页的顺序与占位阶段号（app-shell.md「组件契约」）。
struct SettingsTabTests {
    @Test("分页顺序：通用、快捷键、提醒、卡片、数据、关于")
    func tabOrder() {
        #expect(SettingsTab.allCases.map(\.title) == ["通用", "快捷键", "提醒", "卡片", "数据", "关于"])
    }

    @Test("占位阶段号依次为 1、1、2、3、4；关于页没有占位")
    func placeholderStages() {
        #expect(SettingsTab.general.placeholderStage == 1)
        #expect(SettingsTab.shortcuts.placeholderStage == 1)
        #expect(SettingsTab.reminders.placeholderStage == 2)
        #expect(SettingsTab.cards.placeholderStage == 3)
        #expect(SettingsTab.data.placeholderStage == 4)
        #expect(SettingsTab.about.placeholderStage == nil)
    }
}

/// Story 1.11：右键菜单的菜单项与快捷键（app-shell.md「组件契约」）。
@MainActor
struct StatusMenuTests {
    @Test("右键菜单：设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q）")
    func menuStructure() {
        var openedSettings = false
        var openedAbout = false
        // NSMenuItem.target 是弱引用：菜单实例必须在断言期间存活
        let statusMenu = StatusMenu(actions: .init(
            openSettings: { openedSettings = true },
            openAbout: { openedAbout = true }
        ))
        let menu = statusMenu.buildMenu()

        let items = menu.items
        #expect(items.count == 4)
        #expect(items[0].title == "设置…")
        #expect(items[0].keyEquivalent == ",")
        #expect(items[1].title == "关于拾刻")
        #expect(items[2].isSeparatorItem)
        #expect(items[3].title == "退出拾刻")
        #expect(items[3].action == #selector(NSApplication.terminate(_:)))
        #expect(items[3].keyEquivalent == "q")
        #expect(items[3].target == nil)

        // 设置/关于的动作经 target 回调
        _ = items[0].target?.perform(items[0].action!, with: items[0])
        #expect(openedSettings)
        _ = items[1].target?.perform(items[1].action!, with: items[1])
        #expect(openedAbout)
    }
}
