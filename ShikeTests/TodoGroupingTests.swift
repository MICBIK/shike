// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Todo 的 memberwise init 是 internal（包内约定）

/// Story 3.6：待办五分组（SPEC CAP-6、stage-2-components.md §5、03 §6）。
@MainActor
struct TodoGroupingTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    /// 基准：2026-09-28（周一）10:00 Asia/Shanghai。
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

    private func date(_ daysFromNow: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: Self.now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func todo(
        title: String,
        due: TodoDue? = nil,
        completedAt: Date? = nil,
        createdAt: Date = Self.now
    ) -> Todo {
        Todo(
            id: Todo.ID(rawValue: 1),
            uuid: UUID(),
            title: title,
            due: due,
            snoozedUntil: nil,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: createdAt,
            deletedAt: nil
        )
    }

    private func group(_ todos: [Todo], now: Date = Self.now) -> TodoGroups {
        TodoGrouping.group(todos: todos, now: now, timeZone: Self.timeZone)
    }

    @Test("分组界定：昨天=逾期、今天 0 点=今天、明天 0 点=以后、无 due=无日期")
    func groupBoundaries() {
        let todos = [
            todo(title: "逾期", due: TodoDue(date: date(-1, hour: 23, minute: 59), hasTime: true)),
            todo(title: "今天最早", due: TodoDue(date: date(0, hour: 0), hasTime: true)),
            todo(title: "以后", due: TodoDue(date: date(1, hour: 0), hasTime: true)),
            todo(title: "无时间"),
        ]
        let groups = group(todos)
        #expect(groups.overdue.map(\.title) == ["逾期"])
        #expect(groups.today.map(\.title) == ["今天最早"])
        #expect(groups.later.map(\.title) == ["以后"])
        #expect(groups.noDate.map(\.title) == ["无时间"])
        #expect(groups.completed.isEmpty)
    }

    @Test("已完成只进已完成组；全组排序：时间组按 due 升序、无日期按创建降序、已完成按完成时间降序")
    func membershipAndOrdering() {
        let todos = [
            todo(title: "完成早", completedAt: date(0, hour: 9), createdAt: date(-1, hour: 8)),
            todo(title: "完成晚", completedAt: date(0, hour: 11), createdAt: date(-1, hour: 9)),
            todo(title: "后天", due: TodoDue(date: date(2, hour: 8), hasTime: true)),
            todo(title: "明天", due: TodoDue(date: date(1, hour: 8), hasTime: true)),
            todo(title: "无日期旧", createdAt: date(-2, hour: 8)),
            todo(title: "无日期新", createdAt: date(-1, hour: 20)),
        ]
        let groups = group(todos)
        #expect(groups.completed.map(\.title) == ["完成晚", "完成早"])
        #expect(groups.later.map(\.title) == ["明天", "后天"])
        #expect(groups.noDate.map(\.title) == ["无日期新", "无日期旧"]) // 新的在上
        #expect(groups.today.isEmpty)
        #expect(groups.overdue.isEmpty)
    }

    @Test("跨天重排：注入新 now 后，「今天」移入「逾期」（验收项的纯函数部分）")
    func regroupAfterMidnight() {
        let todos = [todo(title: "今天的事", due: TodoDue(date: date(0, hour: 15), hasTime: true))]
        #expect(group(todos).today.map(\.title) == ["今天的事"])

        // 次日同一时刻：该待办变逾期
        let nextDay = Self.now.addingTimeInterval(86_400)
        let groups = group(todos, now: nextDay)
        #expect(groups.overdue.map(\.title) == ["今天的事"])
        #expect(groups.today.isEmpty)
    }

    @Test("逾期判定与行尾时间文案（TimeDisplay 复用）")
    func overdueFlagAndTimeText() {
        let overdue = todo(title: "逾期", due: TodoDue(date: date(-1, hour: 15), hasTime: true))
        let todayTodo = todo(title: "今天", due: TodoDue(date: date(0, hour: 15), hasTime: true))
        let allDay = todo(title: "全天", due: TodoDue(date: date(0, hour: 0), hasTime: false))

        #expect(TodoGrouping.isOverdue(overdue, now: Self.now, timeZone: Self.timeZone))
        #expect(!TodoGrouping.isOverdue(todayTodo, now: Self.now, timeZone: Self.timeZone))
        #expect(!TodoGrouping.isOverdue(allDay, now: Self.now, timeZone: Self.timeZone))
        // 已完成的不算逾期
        #expect(!TodoGrouping.isOverdue(
            todo(title: "完成", due: TodoDue(date: date(-1, hour: 15), hasTime: true), completedAt: Self.now),
            now: Self.now,
            timeZone: Self.timeZone
        ))

        #expect(TodoGrouping.timeText(for: todayTodo, now: Self.now, timeZone: Self.timeZone) == "今天 15:00")
        #expect(TodoGrouping.timeText(for: allDay, now: Self.now, timeZone: Self.timeZone) == "今天")
        #expect(TodoGrouping.timeText(for: todo(title: "无时间"), now: Self.now, timeZone: Self.timeZone) == nil)
        // 今年以内不带年份 / 跨年带年份（03 §6；3.6 盲审 F6③）
        // +9 天 = 2026-10-07（超出周X窗口）
        let thisYearLater = todo(title: "10月7日", due: TodoDue(date: date(9, hour: 0), hasTime: true))
        #expect(TodoGrouping.timeText(for: thisYearLater, now: Self.now, timeZone: Self.timeZone) == "10月7日 00:00")
        // 跨年：2027-03-07 15:00（按 components 构造，避免日运算歧义）
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        var nextYearComponents = DateComponents()
        nextYearComponents.year = 2027
        nextYearComponents.month = 3
        nextYearComponents.day = 7
        nextYearComponents.hour = 15
        let nextYearDate = calendar.date(from: nextYearComponents)!
        let nextYear = todo(title: "跨年", due: TodoDue(date: nextYearDate, hasTime: true))
        #expect(TodoGrouping.timeText(for: nextYear, now: Self.now, timeZone: Self.timeZone) == "2027年3月7日 15:00")
    }

    @Test("snoozedUntil 不影响分组；已完成+有 due 只进已完成组（盲审 F6）")
    func snoozeAndCompletedMembership() {
        let todos = [
            todo(title: "已稍后的逾期", due: TodoDue(date: date(-1, hour: 15), hasTime: true)),
            todo(title: "已完成有 due", due: TodoDue(date: date(0, hour: 15), hasTime: true), completedAt: Self.now),
        ]
        let groups = group(todos)
        // 稍后提醒不改 due：行仍红字躺在「逾期」（components §5 明文，验收对照）
        #expect(groups.overdue.map(\.title) == ["已稍后的逾期"])
        // 先判 completedAt：已完成+有 due 只进已完成组
        #expect(groups.completed.map(\.title) == ["已完成有 due"])
        #expect(groups.today.isEmpty)
    }

    @Test("timeContextTick：跨天/唤醒钩子递增（视图重算分组的依赖）")
    func timeContextTickBumps() throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let before = model.timeContextTick
        model.handleTimeContextChanged()
        #expect(model.timeContextTick == before + 1)
    }
}
