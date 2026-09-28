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

    /// 占位分页显示的阶段号；关于页没有占位。
    var placeholderStage: Int? {
        switch self {
        case .general, .shortcuts: 1
        case .reminders: 2
        case .cards: 3
        case .data: 4
        case .about: nil
        }
    }
}

/// 设置窗口的分页选择状态（SettingsWindowController 与 SettingsView 共享）。
@MainActor
@Observable
final class SettingsModel {
    var selectedTab: SettingsTab = .general
}
