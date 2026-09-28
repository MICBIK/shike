// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import os
import ShikeData
import UserNotifications

/// 提醒通知的类别与动作处理（S2-04，03 §11）：
/// - 类别 `reminder` 带"完成""稍后提醒"两个动作；
/// - 前台同样展示横幅；
/// - 点通知本体打开面板、切待办、定位并高亮（回调注入）；
/// - 动作在数据库就绪后执行（AppDelegate 组装完成后才设 delegate，冷启动天然满足）。
/// 处理核心 `handleAction` 与 UN 类型解耦，L2 可直接注入替身验证路由。
@MainActor
final class NotificationCoordinator: NSObject {
    static let reminderCategoryID = "reminder"
    static let completeActionID = "complete"
    static let snoozeActionID = "snooze"

    /// 动作回调（由 App 接仓储与面板；uuid 找不到时由回调内部忽略）。
    struct Handlers {
        var complete: (UUID) -> Void = { _ in }
        var snooze: (UUID, Date) -> Void = { _, _ in }
        var openPanel: (UUID) -> Void = { _ in }
        /// 稍后提醒的时长（分钟）：动作发生时读取偏好（03 §11 括号时长随设置变化）。
        var snoozeMinutes: () -> Int = { 10 }
    }

    /// 动作回调（AppEnvironment 在全部属性就绪后配置；openPanelHandler 单独可后置）。
    var handlers: Handlers
    private let scheduling: NotificationScheduling
    /// 点通知本体后的面板打开回调（AppDelegate 在面板创建后接线；AppEnvironment 组装时留空）。
    var openPanelHandler: (UUID) -> Void = { _ in }

    init(scheduling: NotificationScheduling, handlers: Handlers) {
        self.scheduling = scheduling
        self.handlers = handlers
        super.init()
    }

    /// 注册通知类别：稍后提醒按钮的括号时长随偏好变化（03 §11，盲审 F3）——
    /// 偏好变化后需重新注册（3.5 的"提醒设置变化"对账时机挂接）。
    func registerCategory(snoozeMinutes: Int) {
        let complete = UNNotificationAction(
            identifier: Self.completeActionID,
            title: String(localized: .notificationActionComplete),
            options: []
        )
        let snooze = UNNotificationAction(
            identifier: Self.snoozeActionID,
            title: String(localized: .notificationActionSnooze(snoozeMinutes)),
            options: []
        )
        let category = UNNotificationCategory(
            identifier: Self.reminderCategoryID,
            actions: [complete, snooze],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }

    /// 通知文案（03 §11）：标题=待办标题；正文=时间（"今天 15:00"/"全天 · 今天"）。
    static func body(due: TodoDue, now: Date, timeZone: TimeZone) -> String {
        guard due.hasTime else {
            return String(localized: .notificationBodyAllDay(TimeDisplay.dayText(for: due.date, now: now, timeZone: timeZone)))
        }
        return TimeDisplay.text(for: due.date, hasTime: true, now: now, timeZone: timeZone)
    }

    // - MARK: 动作路由（L2 直接验证）

    /// 统一入口：通知点本体（default action）与两个自定义动作。
    func handleAction(identifier: String, todoUUID: UUID?) {
        guard let todoUUID else {
            Log.app.error("通知动作缺少 userInfo.uuid，忽略 identifier=\(identifier, privacy: .public)")
            return
        }
        switch identifier {
        case Self.completeActionID:
            handlers.complete(todoUUID)
        case Self.snoozeActionID:
            let minutes = max(1, handlers.snoozeMinutes())
            handlers.snooze(todoUUID, Date().addingTimeInterval(TimeInterval(minutes * 60)))
        default:
            // 点通知本体：打开面板并定位。
            openPanelHandler(todoUUID)
        }
    }
}

// - MARK: UNUserNotificationCenterDelegate（回调 hop 回主 actor）

extension NotificationCoordinator: UNUserNotificationCenterDelegate {
    /// 前台同样显示横幅（03 §11）。
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { [.banner, .sound] }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.actionIdentifier
        let uuidString = response.notification.request.content.userInfo["uuid"] as? String
        let todoUUID = uuidString.flatMap(UUID.init(uuidString:))
        await MainActor.run {
            handleAction(identifier: identifier, todoUUID: todoUUID)
        }
    }
}
