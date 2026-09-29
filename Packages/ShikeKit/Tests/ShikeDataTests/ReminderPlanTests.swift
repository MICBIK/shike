// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import ShikeData

/// Story 3.3：提醒计划（04 §6.7、SPEC CAP-3）。
/// 全部注入 now 与时区（NFR22）；基准 T0 = 2026-09-28（周一）10:00 Asia/Shanghai。
struct ReminderPlanTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 28
        components.hour = 10
        return calendar.date(from: components)!
    }()

    private func todo(
        title: String = "待办",
        due: TodoDue? = nil,
        snoozedUntil: Date? = nil,
        completed: Bool = false,
        deleted: Bool = false,
        uuid: UUID = UUID()
    ) -> Todo {
        Todo(
            id: Todo.ID(rawValue: 1),
            uuid: uuid,
            title: title,
            due: due,
            snoozedUntil: snoozedUntil,
            completedAt: completed ? Self.now : nil,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: deleted ? Self.now : nil
        )
    }

    private func date(_ daysFromNow: Int, hour: Int, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: Self.now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    @Test("候选过滤：已删除、已完成、无时间的待办不进计划")
    func candidateFiltering() {
        let todos = [
            todo(title: "正常", due: TodoDue(date: date(1, hour: 9), hasTime: true)),
            todo(title: "已删除", due: TodoDue(date: date(1, hour: 9), hasTime: true), deleted: true),
            todo(title: "已完成", due: TodoDue(date: date(1, hour: 9), hasTime: true), completed: true),
            todo(title: "无时间"),
        ]
        let plan = ReminderPlan.plan(todos: todos, now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)
        #expect(plan.map(\.title) == ["正常"])
    }

    @Test("提醒时间：带时刻用 dueAt；全天用当天 00:00 + allDayMinutes")
    func fireDateRules() {
        let timed = todo(title: "带时刻", due: TodoDue(date: date(1, hour: 15, minute: 30), hasTime: true))
        let allDay = todo(title: "全天", due: TodoDue(date: date(1, hour: 0), hasTime: false))

        let plan = ReminderPlan.plan(todos: [timed, allDay], now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)
        #expect(plan.count == 2)
        #expect(plan[0].fireDate == date(1, hour: 9)) // 全天 09:00 排在 15:30 前
        #expect(plan[0].hasTime == false)
        #expect(plan[1].fireDate == date(1, hour: 15, minute: 30))
        #expect(plan[1].hasTime == true)
    }

    @Test("snoozedUntil 优先于 due；已过期的 snooze 被过滤")
    func snoozePriority() {
        let snoozed = todo(
            title: "稍后提醒",
            due: TodoDue(date: date(0, hour: 18), hasTime: true),
            snoozedUntil: date(0, hour: 11)
        )
        let expiredSnooze = todo(
            title: "过期 snooze",
            due: TodoDue(date: date(1, hour: 9), hasTime: true),
            snoozedUntil: date(0, hour: 8)
        )
        let plan = ReminderPlan.plan(todos: [snoozed, expiredSnooze], now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)
        #expect(plan.map(\.title) == ["稍后提醒"])
        #expect(plan[0].fireDate == date(0, hour: 11))
    }

    @Test("只保留晚于当前时刻的；恰为 now 不排（不发通知）")
    func pastAndBoundaryFiltered() {
        let past = todo(title: "已过", due: TodoDue(date: date(0, hour: 9), hasTime: true))
        let exactNow = todo(title: "恰好现在", due: TodoDue(date: Self.now, hasTime: true))
        let future = todo(title: "未来", due: TodoDue(date: date(0, hour: 10, minute: 1), hasTime: true))
        let plan = ReminderPlan.plan(todos: [past, exactNow, future], now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)
        #expect(plan.map(\.title) == ["未来"])
    }

    @Test("升序取前 limit 条：恰好 50 全保留，51 条截断")
    func limitBoundary() {
        let todos = (0...51).map { index in
            todo(
                title: "t\(index)",
                due: TodoDue(date: date(1, hour: 0, minute: index), hasTime: true),
                uuid: UUID()
            )
        }
        let plan = ReminderPlan.plan(todos: todos, now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)
        #expect(plan.count == 50)
        // 升序：最先 fire 的应是 minute=0 那条
        #expect(plan[0].title == "t0")
        #expect(plan[49].title == "t49")
        #expect(!plan.contains { $0.title == "t50" })
    }

    @Test("全天跨天边界：allDayMinutes=1440 排到次日 00:00；今天的全天提醒时刻已过则不排、也不顺延明天（盲审 F3）")
    func allDayCrossDayBoundary() {
        // allDayMinutes=1440：当天 00:00 + 24h = 次日 00:00（契约允许，钳制在调用方）
        let tomorrowAllDay = todo(title: "明天全天", due: TodoDue(date: date(1, hour: 0), hasTime: false))
        let plan = ReminderPlan.plan(todos: [tomorrowAllDay], now: Self.now, timeZone: Self.timeZone, allDayMinutes: 1440)
        #expect(plan.count == 1)
        #expect(plan[0].fireDate == date(2, hour: 0))

        // 全天 due=今天、提醒时刻（09:00）已过：今天不排，也不得顺延到明天重排
        let todayAllDayPast = todo(title: "今天全天已过", due: TodoDue(date: date(0, hour: 0), hasTime: false))
        let plan2 = ReminderPlan.plan(todos: [todayAllDayPast], now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)
        #expect(plan2.isEmpty)
    }

    @Test("limit 防御：负数返回空计划（盲审 F1）")
    func negativeLimitReturnsEmpty() {
        let todos = [todo(title: "正常", due: TodoDue(date: date(1, hour: 9), hasTime: true))]
        #expect(ReminderPlan.plan(todos: todos, now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540, limit: -1).isEmpty)
        #expect(ReminderPlan.plan(todos: todos, now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540, limit: 0).isEmpty)
    }

    @Test("时区注入：同一待办在不同时区的全天计划时刻不同（NFR22）")
    func timeZoneInjection() {
        let allDay = todo(title: "全天", due: TodoDue(date: date(1, hour: 0), hasTime: false))
        let shanghai = ReminderPlan.plan(todos: [allDay], now: Self.now, timeZone: Self.timeZone, allDayMinutes: 540)[0].fireDate
        let tokyo = ReminderPlan.plan(todos: [allDay], now: Self.now, timeZone: TimeZone(identifier: "Asia/Tokyo")!, allDayMinutes: 540)[0].fireDate
        #expect(tokyo == shanghai.addingTimeInterval(-3600)) // 东京 09:00 比上海 09:00 早一小时（绝对时刻）
    }
}
