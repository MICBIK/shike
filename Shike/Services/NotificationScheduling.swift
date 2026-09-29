// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import os
import UserNotifications

/// 系统通知的接缝（S2-04，NFR23）：App 层唯一触碰 UserNotifications 的地方之一，
/// L2 用内存替身注入，绝不真实请求权限或发通知。
/// 标识约定：以待办 uuid 的 uuidString 作为通知标识（04 §6.7 对账依据）。
@MainActor
protocol NotificationScheduling: AnyObject {
    /// 当前授权状态（S2-10 提示条与设置页显示用）。
    func authorizationStatus() async -> UNAuthorizationStatus
    /// 请求授权；返回是否获得授权（系统只在首次弹窗，重复调用幂等）。
    /// 注意 false 同时涵盖"用户拒绝"与"请求出错"（盲审 F6）；授权状态的权威口径
    /// 是 `authorizationStatus()`，提示条与设置页一律以它为准。
    func requestAuthorization() async -> Bool
    /// 已排期的通知标识（对账用）。
    func pendingIdentifiers() async -> [String]
    /// 排期一条本地通知。调用方保证 fireDate 晚于当前（实现同样拒绝过期时刻——
    /// 盲审 F4：绝不让过期提醒变成"1 秒后立即响"）。
    func add(identifier: String, title: String, body: String, userInfo: [String: String], fireDate: Date) async
    /// 移除已排期的通知。
    func removePending(identifiers: [String]) async
}

/// UNUserNotificationCenter 的默认实现。
@MainActor
final class SystemNotificationScheduling: NotificationScheduling {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func pendingIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests.map(\.identifier)
    }

    func add(identifier: String, title: String, body: String, userInfo: [String: String], fireDate: Date) async {
        guard fireDate > .now else {
            Log.app.error("通知排期被拒绝：fireDate 已过 identifier=\(identifier, privacy: .public)")
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        content.categoryIdentifier = NotificationCoordinator.reminderCategoryID
        // UNTimeIntervalNotificationTrigger 的 interval 必须为正：防御极小正值。
        let interval = max(0.1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            // 不吞错误但也不打扰用户：写日志（提醒缺失由 3.5 的对账在下次时机补排）。
            Log.app.error("通知排期失败 identifier=\(identifier, privacy: .public): \(error, privacy: .public)")
        }
    }

    func removePending(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}
