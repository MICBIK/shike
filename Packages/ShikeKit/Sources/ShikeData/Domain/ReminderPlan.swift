// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 一条已排期的提醒（04 §6.7）：App 层以 `todoUUID` 作为系统通知的标识做对账。
public struct PlannedReminder: Sendable, Equatable {
    public let todoUUID: UUID
    public let fireDate: Date
    /// 通知正文用：标题与时间文案的口径标记。
    public let title: String
    public let hasTime: Bool

    public init(todoUUID: UUID, fireDate: Date, title: String, hasTime: Bool) {
        self.todoUUID = todoUUID
        self.fireDate = fireDate
        self.title = title
        self.hasTime = hasTime
    }
}

/// 提醒计划（04 §6.7，纯函数；行为唯一来源）：
/// - 候选：未删除、未完成、有 `due` 的待办；
/// - 提醒时间：`snoozedUntil` 优先；否则带时刻用 `dueAt`，全天用当天 00:00 + 全天提醒分钟数；
/// - 只保留晚于当前时刻的，按时间先后取前 `limit` 条（默认 50）。
/// 已经过去的时间照常保存在待办上（逾期），不进计划、不发通知。
/// 契约：`limit` 必须 > 0（负数返回空计划）；`allDayMinutes` 预期为 0...1440
/// （钳制是调用方的责任，负数/超一天会排到前一天/次日的对应时刻）。
public enum ReminderPlan {
    public static let defaultLimit = 50

    public static func plan(
        todos: [Todo],
        now: Date,
        timeZone: TimeZone,
        allDayMinutes: Int,
        limit: Int = ReminderPlan.defaultLimit
    ) -> [PlannedReminder] {
        guard limit > 0 else { return [] }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let reminders = todos.compactMap { todo -> PlannedReminder? in
            guard todo.deletedAt == nil, todo.completedAt == nil, let due = todo.due else {
                return nil
            }
            let fireDate: Date
            if let snoozedUntil = todo.snoozedUntil {
                fireDate = snoozedUntil
            } else if due.hasTime {
                fireDate = due.date
            } else {
                let dayStart = calendar.startOfDay(for: due.date)
                fireDate = dayStart.addingTimeInterval(TimeInterval(allDayMinutes * 60))
            }
            guard fireDate > now else { return nil }
            return PlannedReminder(
                todoUUID: todo.uuid,
                fireDate: fireDate,
                title: todo.title,
                hasTime: due.hasTime
            )
        }
        return Array(reminders.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }
}
