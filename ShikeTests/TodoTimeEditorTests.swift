// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Todo 的 memberwise init 是 internal（包内约定）

/// Story 3.7：编辑时间（SPEC CAP-7、stage-2-components.md、03 §6）。
@MainActor
struct TodoTimeEditorTests {
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

    private func date(_ daysFromNow: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: Self.now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    // - MARK: compose（纯函数）

    @Test("compose：带时刻组合当天 00:00+时分；不含时刻存该日 00:00")
    func composeVariants() throws {
        let day = date(3) // 2026-10-01 00:00
        let time = date(0, hour: 14, minute: 45)

        let withTime = try #require(TodoTimeEditorView.compose(day: day, hasTime: true, timeOfDay: time, timeZone: Self.timeZone))
        #expect(withTime.hasTime == true)
        #expect(withTime.date == date(3, hour: 14, minute: 45))

        let allDay = try #require(TodoTimeEditorView.compose(day: day, hasTime: false, timeOfDay: time, timeZone: Self.timeZone))
        #expect(allDay.hasTime == false)
        #expect(allDay.date == day) // 00:00
    }

    @Test("compose：DST 过渡日的墙上时刻不被偏移（盲审 3.7-F3，America/New_York 春令时）")
    func composeDSTBoundary() throws {
        let newYork = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 8 // 春令时：02:00 → 03:00，当天日长 23 小时
        let day = try #require(calendar.date(from: components))
        let timeOfDay = try #require(calendar.date(bySettingHour: 14, minute: 45, second: 0, of: day))

        let due = try #require(TodoTimeEditorView.compose(day: day, hasTime: true, timeOfDay: timeOfDay, timeZone: newYork))
        // 墙上时刻 14:45 必须原样保留
        #expect(calendar.component(.hour, from: due.date) == 14)
        #expect(calendar.component(.minute, from: due.date) == 45)
    }

    // - MARK: 快捷按钮的日期推算（纯函数）

    @Test("nextMonday：周一顺延一周；周五+3；周日+1（全天 00:00）")
    func nextMondayVariants() throws {
        // 基准日是周一：下周一 = +7
        let fromMonday = try #require(TodoTimeEditorView.nextMonday(after: Self.now, timeZone: Self.timeZone) as Date?)
        #expect(fromMonday == date(7))

        // 周五（+4 天）：下周一 = +3
        let friday = date(4)
        let fromFriday = try #require(TodoTimeEditorView.nextMonday(after: friday, timeZone: Self.timeZone) as Date?)
        #expect(fromFriday == date(7))

        // 周日（+6 天）：下周一 = +1
        let sunday = date(6)
        let fromSunday = try #require(TodoTimeEditorView.nextMonday(after: sunday, timeZone: Self.timeZone) as Date?)
        #expect(fromSunday == date(7))
    }

    @Test("shiftDays：明天 = +1 日历日")
    func shiftDaysTomorrow() throws {
        #expect(TodoTimeEditorView.shiftDays(1, from: Self.now, timeZone: Self.timeZone) == date(1))
    }

    // - MARK: 落库与"编辑标题不重新识别时间"

    @Test("setDue 落库并回流到列表；清除时间置 nil")
    func setDueRoundtrip() async throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()
        model.mode = .todo
        model.draftTodo = "无时间的待办" // 无识别
        model.submitCurrentDraft()
        try await waitUntil { !model.todos.isEmpty }
        let id = model.todos[0].id

        let due = try #require(TodoTimeEditorView.compose(
            day: date(2), hasTime: true, timeOfDay: date(0, hour: 15, minute: 30), timeZone: Self.timeZone
        ))
        await model.setDue(id, due)
        try await waitUntil { model.todos.first(where: { $0.id == id })?.due != nil }
        let stored = model.todos.first(where: { $0.id == id })
        #expect(stored?.due?.hasTime == true)

        await model.setDue(id, nil)
        try await waitUntil { model.todos.first(where: { $0.id == id })?.due == nil }
    }

    @Test("编辑标题不重新识别时间：时间保持不变（03 §6）")
    func titleEditDoesNotTouchDue() async throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()
        let original = try await environment.todoRepository.create(
            title: "带时间的待办",
            due: TodoDue(date: date(1, hour: 9), hasTime: true)
        )
        try await waitUntil { !model.todos.isEmpty }

        model.editingTodoID = original.id
        model.editingTodoText = "改成明天下午三点" // 看似时间词，但标题编辑不识别
        await model.saveTodoTitle(original.id, "改成明天下午三点")
        try await waitUntil { model.todos.first(where: { $0.id == original.id })?.title == "改成明天下午三点" }
        #expect(model.todos.first(where: { $0.id == original.id })?.due?.hasTime == true)
        #expect(model.todos.first(where: { $0.id == original.id })?.due?.date == date(1, hour: 9))
    }

    // 截止时间轮询（仓库约定）
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "等待条件在 3 秒内未满足")
    }
}
