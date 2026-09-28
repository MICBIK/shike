// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import UserNotifications

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
        // 初值读偏好（init 内赋值不触发 didSet；钩子由 AppDelegate 在此后接线）
        self.menuBarCounter = MenuBarCounter.resolve(preferences.menuBarCounter)
        self.reminderAllDayMinutes = min(1439, max(0, preferences.reminderAllDayMinutes))
        self.reminderSnoozeMinutes = Self.snoozeOptions.contains(preferences.reminderSnoozeMinutes)
            ? preferences.reminderSnoozeMinutes
            : 10
    }

    /// "稍后提醒"的合法档位（03 §9）：5 / 10（默认）/ 15 / 30 / 60 分钟。
    static let snoozeOptions = [5, 10, 15, 30, 60]

    /// 提醒设置变化钩子（S2-05）：调度器重对账 + 重注册类别；AppDelegate 接线。
    @ObservationIgnored var onReminderSettingsChanged: () -> Void = {}
    /// 菜单栏计数口径变化钩子（S2-08）：立即刷新计数显示；AppDelegate 接线。
    @ObservationIgnored var onMenuBarCounterChanged: () -> Void = {}
    /// 通知授权状态读取（S2-10）：AppDelegate 注入；nil 表示未知（未刷新）。
    @ObservationIgnored var notificationAuthorizationReader: (() async -> UNAuthorizationStatus)?
    /// "打开系统设置"（S2-10）：AppDelegate 注入真实跳转。
    @ObservationIgnored var openNotificationSettings: () -> Void = {}
    /// 通知权限的展示状态（提醒分页）。
    enum NotificationPermissionState: Equatable {
        case notDetermined
        case granted
        case denied
        case unknown
    }
    private(set) var notificationPermission: NotificationPermissionState = .unknown

    func refreshNotificationPermission() async {
        guard let reader = notificationAuthorizationReader else { return }
        switch await reader() {
        case .notDetermined: notificationPermission = .notDetermined
        case .denied: notificationPermission = .denied
        case .authorized, .provisional, .ephemeral: notificationPermission = .granted
        @unknown default: notificationPermission = .unknown
        }
    }

    // - MARK: 设置项（存储属性 + didSet 写偏好并触发钩子）
    // 经 UserDefaults 的计算属性不可被 @Observable 观测：SwiftUI 的 onChange 检测
    // 不到变化，视图里的钩子调用是死代码（盲审 3.8-F2）。故用存储属性承载，
    // didSet 持久化并触发钩子。

    /// "呼出时进入"（S1-03）；存储值非法时回落 last。
    var panelOpenMode: PanelModel.OpenMode {
        get { PanelModel.OpenMode(rawValue: preferences.panelOpenMode) ?? .last }
        set { preferences.panelOpenMode = newValue.rawValue }
    }

    /// 菜单栏计数口径（S2-08）：合法档位之外回落逾期+今天。
    var menuBarCounter: MenuBarCounter = .overdueAndToday {
        didSet {
            guard menuBarCounter != oldValue else { return }
            preferences.menuBarCounter = menuBarCounter.rawValue
            onMenuBarCounterChanged()
        }
    }

    /// 全天待办提醒时刻（S2-03）：分钟数，钳制到 0...1439（0:00–23:59）。
    var reminderAllDayMinutes: Int = 540 {
        didSet {
            let clamped = min(1439, max(0, reminderAllDayMinutes))
            guard clamped != reminderAllDayMinutes else {
                preferences.reminderAllDayMinutes = clamped
                onReminderSettingsChanged()
                return
            }
            reminderAllDayMinutes = clamped // 回落再进 didSet 完成持久化与钩子
        }
    }

    /// "稍后提醒"时长（S2-04）：非法档位回落 10 分钟。
    var reminderSnoozeMinutes: Int = 10 {
        didSet {
            guard Self.snoozeOptions.contains(reminderSnoozeMinutes) else {
                reminderSnoozeMinutes = 10 // 回落会再进 didSet 完成持久化与钩子
                return
            }
            guard reminderSnoozeMinutes != oldValue else { return }
            preferences.reminderSnoozeMinutes = reminderSnoozeMinutes
            onReminderSettingsChanged()
        }
    }
}
