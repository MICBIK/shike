// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Todo 的 memberwise init 是 internal（包内约定）

/// Story 3.8：菜单栏计数与角标（SPEC CAP-8、stage-2-components.md §6、03 §2/§9）。
@MainActor
struct MenuBarCounterTests {
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

    private func date(_ daysFromNow: Int, hour: Int = 12) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: Self.now))!
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private func todo(title: String, due: TodoDue? = nil, completedAt: Date? = nil) -> Todo {
        Todo(
            id: Todo.ID(rawValue: 1),
            uuid: UUID(),
            title: title,
            due: due,
            snoozedUntil: nil,
            completedAt: completedAt,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: nil
        )
    }

    @Test("三种口径：逾期+今天只算这两组；全部未完成含无日期；none 为 nil")
    func counterModes() {
        let todos = [
            todo(title: "逾期", due: TodoDue(date: date(-1), hasTime: true)),
            todo(title: "今天", due: TodoDue(date: date(0), hasTime: true)),
            todo(title: "以后", due: TodoDue(date: date(3), hasTime: true)),
            todo(title: "无日期"),
            todo(title: "已完成", due: TodoDue(date: date(0), hasTime: true), completedAt: Self.now),
        ]
        #expect(MenuBarCounter.count(.overdueAndToday, todos: todos, now: Self.now, timeZone: Self.timeZone) == 2)
        #expect(MenuBarCounter.count(.allIncomplete, todos: todos, now: Self.now, timeZone: Self.timeZone) == 4)
        #expect(MenuBarCounter.count(.none, todos: todos, now: Self.now, timeZone: Self.timeZone) == nil)
    }

    @Test("零不显示：无待办时两种口径都是 0（显示层隐藏）")
    func zeroCounts() {
        #expect(MenuBarCounter.count(.overdueAndToday, todos: [], now: Self.now, timeZone: Self.timeZone) == 0)
        #expect(MenuBarCounter.count(.allIncomplete, todos: [], now: Self.now, timeZone: Self.timeZone) == 0)
    }

    @Test("存储值非法回落 overdueAndToday")
    func resolveFallback() {
        #expect(MenuBarCounter.resolve("bogus") == .overdueAndToday)
        #expect(MenuBarCounter.resolve("allIncomplete") == .allIncomplete)
    }

    @Test("完成一条后计数立即减少（todosChanged 钩子触发刷新的口径前提）")
    func countDecreasesAfterCompletion() async throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()
        var refreshes = 0
        model.todosChanged = { refreshes += 1 }

        model.mode = .todo
        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        try await waitUntil { !model.todos.isEmpty }
        #expect(refreshes >= 1) // 数据变化 → 计数刷新被调用

        let before = MenuBarCounter.count(.allIncomplete, todos: model.todos, now: Date(), timeZone: Self.timeZone)
        await model.completeTodo(uuid: model.todos[0].uuid)
        try await waitUntil { model.todos.first(where: { $0.id == model.todos.first?.id })?.completedAt != nil || model.todos.isEmpty }
        let after = MenuBarCounter.count(.allIncomplete, todos: model.todos, now: Date(), timeZone: Self.timeZone)
        #expect((before ?? 0) - (after ?? 0) == 1)
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
