// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 设置分页的有序注册表（app-shell.md「组件契约」）：
/// 顺序即 03 §9 的六个分页；后续阶段只需把对应分页的占位视图换掉。
enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case reminders
    case cards
    case `data`
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: String(localized: .settingsTabGeneral)
        case .shortcuts: String(localized: .settingsTabShortcuts)
        case .reminders: String(localized: .settingsTabReminders)
        case .cards: String(localized: .settingsTabCards)
        case .data: String(localized: .settingsTabData)
        case .about: String(localized: .settingsTabAbout)
        }
    }

    /// 占位分页显示的阶段号；真实的分页（通用 S1-03 起、快捷键 S1-02、关于）没有占位。
    var placeholderStage: Int? {
        switch self {
        case .general, .shortcuts, .reminders, .about: nil
        case .cards: 3
        case .data: 4
        }
    }
}

/// 设置窗口的分页选择状态（SettingsWindowController 与 SettingsView 共享）。
@MainActor
@Observable
final class SettingsModel {
    var selectedTab: SettingsTab = .general
    let hotkeyService: HotkeyService
    let launchAtLogin: LaunchAtLoginService
    private let preferences: Preferences

    init(hotkeyService: HotkeyService, launchAtLogin: LaunchAtLoginService, preferences: Preferences) {
        self.hotkeyService = hotkeyService
        self.launchAtLogin = launchAtLogin
        self.preferences = preferences
    }

    /// "稍后提醒"的合法档位（03 §9）：5 / 10（默认）/ 15 / 30 / 60 分钟。
    static let snoozeOptions = [5, 10, 15, 30, 60]

    /// 提醒设置变化钩子（S2-05）：调度器重对账 + 重注册类别；AppDelegate 接线。
    @ObservationIgnored var onReminderSettingsChanged: () -> Void = {}

    /// "呼出时进入"（S1-03）；存储值非法时回落 last。
    var panelOpenMode: PanelModel.OpenMode {
        get { PanelModel.OpenMode(rawValue: preferences.panelOpenMode) ?? .last }
        set { preferences.panelOpenMode = newValue.rawValue }
    }

    /// 菜单栏计数口径（S2-08）：合法档位之外回落逾期+今天。
    var menuBarCounter: MenuBarCounter {
        get { MenuBarCounter(rawValue: preferences.menuBarCounter) ?? .overdueAndToday }
        set { preferences.menuBarCounter = newValue.rawValue }
    }

    /// 全天待办提醒时刻（S2-03）：分钟数，钳制到 0...1439（0:00–23:59）。
    var reminderAllDayMinutes: Int {
        get { min(1439, max(0, preferences.reminderAllDayMinutes)) }
        set { preferences.reminderAllDayMinutes = min(1439, max(0, newValue)) }
    }

    /// "稍后提醒"时长（S2-04）：非法值回落 10 分钟。
    var reminderSnoozeMinutes: Int {
        get {
            let stored = preferences.reminderSnoozeMinutes
            return Self.snoozeOptions.contains(stored) ? stored : 10
        }
        set { preferences.reminderSnoozeMinutes = newValue }
    }
}
