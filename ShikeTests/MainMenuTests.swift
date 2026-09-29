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

    @Test("占位阶段号：提醒无占位（S2-03 起）、卡片无占位（S3-02 起）、数据 4；通用、快捷键与关于页没有占位")
    func placeholderStages() {
        #expect(SettingsTab.general.placeholderStage == nil)
        #expect(SettingsTab.shortcuts.placeholderStage == nil)
        #expect(SettingsTab.reminders.placeholderStage == nil) // S2-03/S2-04 起真实化
        #expect(SettingsTab.cards.placeholderStage == nil) // S3-02 起真实化
        #expect(SettingsTab.data.placeholderStage == 4)
        #expect(SettingsTab.about.placeholderStage == nil)
    }
}

/// Story 1.11/2.9：右键菜单的菜单项与快捷键（app-shell.md「组件契约」、03 §2）。
@MainActor
struct StatusMenuTests {
    /// 构造菜单（开机自启注入为已启用）。
    private func makeMenu(launchAtLoginEnabled: Bool) -> StatusMenu {
        let statusMenu = StatusMenu(actions: .init(
            openPanel: {},
            openMainWindow: {},
            openSettings: {},
            toggleLaunchAtLogin: {},
            launchAtLoginEnabled: { launchAtLoginEnabled },
            hideAllCards: {},
            showAllCards: {},
            hasCards: { false },
            allCardsHidden: { false },
            openAbout: {}
        ))
        _ = statusMenu.buildMenu() // 预热
        return statusMenu
    }

    @Test("右键菜单（S1-09 + S3.5-01）：打开拾刻、打开主窗口、设置…（⌘,）、开机自启（勾选）、关于拾刻、退出拾刻（⌘Q）")
    func menuStructure() {
        // NSMenuItem.target 是弱引用：菜单实例必须在断言期间存活
        let statusMenu = makeMenu(launchAtLoginEnabled: true)
        let items = statusMenu.buildMenu().items

        #expect(items.count == 8)
        #expect(items[0].title == "打开拾刻")
        #expect(items[1].title == "打开主窗口")
        #expect(items[2].isSeparatorItem)
        #expect(items[3].title == "设置…")
        #expect(items[3].keyEquivalent == ",")
        #expect(items[4].title == "开机自启")
        #expect(items[4].state == .on)
        #expect(items[5].title == "关于拾刻")
        #expect(items[6].isSeparatorItem)
        #expect(items[7].title == "退出拾刻")
        #expect(items[7].action == #selector(NSApplication.terminate(_:)))
        #expect(items[7].keyEquivalent == "q")
        #expect(items[7].target == nil)
    }

    @Test("右键菜单动作回调：打开拾刻、打开主窗口、设置、切换开机自启、关于；未启用时勾选态为 off")
    func menuActions() {
        var openedPanel = false
        var openedMainWindow = false
        var openedSettings = false
        var toggledLogin = false
        var openedAbout = false
        let statusMenu = StatusMenu(actions: .init(
            openPanel: { openedPanel = true },
            openMainWindow: { openedMainWindow = true },
            openSettings: { openedSettings = true },
            toggleLaunchAtLogin: { toggledLogin = true },
            launchAtLoginEnabled: { false },
            hideAllCards: {},
            showAllCards: {},
            hasCards: { false },
            allCardsHidden: { false },
            openAbout: { openedAbout = true }
        ))
        let items = statusMenu.buildMenu().items
        _ = items[0].target?.perform(items[0].action!, with: items[0])
        _ = items[1].target?.perform(items[1].action!, with: items[1])
        _ = items[3].target?.perform(items[3].action!, with: items[3])
        _ = items[4].target?.perform(items[4].action!, with: items[4])
        _ = items[5].target?.perform(items[5].action!, with: items[5])
        #expect(openedPanel && openedMainWindow && openedSettings && toggledLogin && openedAbout)
        #expect(items[4].state == .off) // 未启用形态
        // 无卡片时右键菜单不出现"隐藏/显示所有卡片"项（S3-09）
        #expect(!items.contains { $0.title == String(localized: .menuHideAllCards) })
    }

    @Test("有卡片时右键菜单出现互斥的隐藏/显示所有卡片项（S3-09，03 §10.6）")
    func hideShowAllCardsItems() {
        var hidAll = false
        var showedAll = false
        func build(hidden: Bool) -> (StatusMenu, [NSMenuItem]) {
            let menu = StatusMenu(actions: .init(
                openPanel: {},
                openMainWindow: {},
                openSettings: {},
                toggleLaunchAtLogin: {},
                launchAtLoginEnabled: { false },
                hideAllCards: { hidAll = true },
                showAllCards: { showedAll = true },
                hasCards: { true },
                allCardsHidden: { hidden },
                openAbout: {}
            ))
            // NSMenuItem.target 弱引用：菜单实例必须与断言同生命周期
            return (menu, menu.buildMenu().items)
        }
        let (visibleMenu, visibleItems) = build(hidden: false)
        let hideItem = visibleItems.first { $0.title == String(localized: .menuHideAllCards) }
        #expect(hideItem != nil)
        _ = hideItem?.target?.perform(hideItem!.action!, with: hideItem!)
        #expect(hidAll)

        let (hiddenMenu, hiddenItems) = build(hidden: true)
        let showItem = hiddenItems.first { $0.title == String(localized: .menuShowAllCards) }
        #expect(showItem != nil)
        _ = showItem?.target?.perform(showItem!.action!, with: showItem!)
        #expect(showedAll)
        // 互斥：隐藏态不显示"隐藏所有卡片"
        #expect(!hiddenItems.contains { $0.title == String(localized: .menuHideAllCards) })
        _ = visibleMenu // 菜单实例存活到断言结束（target 弱引用）
        _ = hiddenMenu
    }
}
