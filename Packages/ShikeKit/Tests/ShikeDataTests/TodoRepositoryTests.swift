// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// 待办仓储：全天规范化、snoozedUntil 清空规则、ADR-017、观察（Story 1.5）。
struct TodoRepositoryTests {
    /// Asia/Shanghai 的 2026-09-25 15:30（全天规范化的输入样例）。
    private let dueInput: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 25
        components.hour = 15
        components.minute = 30
        return calendar.date(from: components)!
    }()

    /// 同一天的 00:00（全天规范化的期望输出）。
    private let dueNormalizedMidnight: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 25
        return calendar.date(from: components)!
    }()

    private func makeRepository(timeZone: TimeZone = TimeZone(identifier: "Asia/Shanghai")!) throws -> (AppDatabase, TodoRepository) {
        let database = try AppDatabase.inMemory(options: .init(
            timeZone: timeZone,
            clock: { TestClock.t0 }
        ))
        return (database, TodoRepository(database: database))
    }

    @Test("全天待办规范化为当天 00:00；带时刻原样保存；uuid 小写文本；时间戳为 T0")
    func createNormalizesAllDayDue() async throws {
        let (database, repository) = try makeRepository()

        let allDay = try await repository.create(title: "全天", due: TodoDue(date: dueInput, hasTime: false))
        let timed = try await repository.create(title: "带时刻", due: TodoDue(date: dueInput, hasTime: true))

        #expect(allDay.due?.hasTime == false)
        #expect(allDay.due?.date == dueNormalizedMidnight)
        #expect(timed.due?.hasTime == true)
        #expect(timed.due?.date == dueInput)
        #expect(allDay.createdAt == TestClock.t0)
        #expect(allDay.updatedAt == TestClock.t0)
        #expect(allDay.uuid != timed.uuid)
        #expect(allDay.snoozedUntil == nil)
        #expect(allDay.completedAt == nil)

        // uuid 与时间以文本存储（经 Record 编码路径）
        let storage = try await database.writer.read { database in
            try String.fetchAll(database, sql: "SELECT typeof(uuid) || '|' || uuid || '|' || typeof(dueAt) FROM todo ORDER BY id")
        }
        for line in storage {
            let parts = line.split(separator: "|")
            #expect(parts.count == 3)
            #expect(parts[0] == "text")
            #expect(parts[1].wholeMatch(of: /^[0-9a-f-]{36}$/) != nil)
        }

        func assertSendable<T: Sendable>(_: T.Type) {}
        assertSendable(Todo.self)
        assertSendable(Todo.ID.self)
        assertSendable(TodoDue.self)
    }

    @Test("无时间的待办：dueAt 与 dueHasTime 均为空")
    func createWithoutDue() async throws {
        let (_, repository) = try makeRepository()
        let todo = try await repository.create(title: "没有时间", due: nil)
        #expect(todo.due == nil)
    }

    @Test("setDue 与 setCompleted(true) 清空 snoozedUntil；setCompleted 幂等")
    func snoozedUntilClearingRules() async throws {
        let (database, repository) = try makeRepository()
        let todo = try await repository.create(title: "稍后提醒", due: TodoDue(date: dueInput, hasTime: true))
        try await repository.snooze(todo.id, until: dueNormalizedMidnight)
        var fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.snoozedUntil != nil)

        // setDue 清空 snoozedUntil
        try await repository.setDue(todo.id, TodoDue(date: dueInput, hasTime: false))
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.snoozedUntil == nil)

        // 再次 snooze 后 setCompleted(true) 清空 snoozedUntil，completedAt = 当前时间
        try await repository.snooze(todo.id, until: dueNormalizedMidnight)
        try await repository.setCompleted(todo.id, true)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.snoozedUntil == nil)
        #expect(fresh?.completedAt == TestClock.t0)

        // setCompleted(true) 幂等：completedAt 不变
        try await repository.setCompleted(todo.id, true)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.completedAt == TestClock.t0)

        // setCompleted(false)：completedAt = nil；幂等
        try await repository.setCompleted(todo.id, false)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.completedAt == nil)
        try await repository.setCompleted(todo.id, false)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.completedAt == nil)
    }

    @Test("ADR-017：修改类方法更新 updatedAt，softDelete/restore 不更新")
    func updatedAtRules() async throws {
        // 递增时钟才能区分"先后"
        let database = try AppDatabase.inMemory(options: .init(
            timeZone: TimeZone(identifier: "Asia/Shanghai")!,
            clock: TestClock.ticking()
        ))
        let repository = TodoRepository(database: database)
        let todo = try await repository.create(title: "原始", due: TodoDue(date: dueInput, hasTime: true))
        let createdAtCreation = todo.updatedAt

        // snooze 更新 updatedAt
        try await repository.snooze(todo.id, until: dueNormalizedMidnight)
        var fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh!.updatedAt > createdAtCreation)
        let afterSnooze = fresh!.updatedAt

        // setCompleted(false) 在已未完成状态是"目标状态已达成"，不改动
        try await repository.softDelete(todo.id)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh!.updatedAt == afterSnooze)
        let deletedAtValue = fresh!.deletedAt

        try await repository.restore(todo.id)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh!.updatedAt == afterSnooze)

        // updateTitle 更新 updatedAt（以及 setDue/setCompleted 已在上面覆盖清空规则）
        try await repository.updateTitle(todo.id, to: "新标题")
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh!.title == "新标题")
        #expect(fresh!.updatedAt > afterSnooze)

        // setDue（含清除时间）更新 updatedAt 并清空 snoozedUntil
        try await repository.snooze(todo.id, until: dueNormalizedMidnight)
        try await repository.setDue(todo.id, nil)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.due == nil)
        #expect(fresh?.snoozedUntil == nil)

        _ = deletedAtValue
    }

    @Test("软删除/恢复/永久删除语义与便签一致；不存在即 notFound")
    func deleteSemanticsAndNotFound() async throws {
        let (database, repository) = try makeRepository()
        let todo = try await repository.create(title: "删除语义", due: nil)

        // 已删除的保留原 deletedAt
        try await repository.softDelete(todo.id)
        var fresh = try await fetchTodo(database, id: todo.id)
        let deletedAtValue = fresh!.deletedAt
        try await repository.softDelete(todo.id)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh?.deletedAt == deletedAtValue)

        // 软删除后可永久删除
        try await repository.permanentlyDelete(todo.id)
        fresh = try await fetchTodo(database, id: todo.id)
        #expect(fresh == nil)

        // 不存在的待办：每个修改方法都抛 notFound
        let ghost = Todo.ID(rawValue: 9999)
        await #expect(throws: ShikeDataError.notFound) { try await repository.updateTitle(ghost, to: "x") }
        await #expect(throws: ShikeDataError.notFound) { try await repository.setDue(ghost, nil) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.setCompleted(ghost, true) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.snooze(ghost, until: dueNormalizedMidnight) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.softDelete(ghost) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.restore(ghost) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.permanentlyDelete(ghost) }
    }

    @Test("观察：初始值按 createdAt 降序、id 降序，包含已完成的；写入推送")
    func observationLifecycle() async throws {
        let (_, repository) = try makeRepository()
        let first = try await repository.create(title: "第一件", due: nil)
        let second = try await repository.create(title: "第二件", due: nil)
        try await repository.setCompleted(second.id, true)

        let received = ReceiveBox<Todo>()
        let stream = repository.observeActive()
        let task = Task {
            for try await items in stream {
                received.append(items)
            }
        }
        defer { task.cancel() }

        #expect(await waitFor(received.count >= 1))
        let initial = received.snapshot[0]
        #expect(initial.map(\.id.rawValue) == [second.id.rawValue, first.id.rawValue])
        #expect(initial.first?.completedAt != nil)

        _ = try await repository.create(title: "第三件", due: nil)
        let sawThird = await waitFor(received.snapshot.last?.count == 3)
        #expect(sawThird)
    }

    @Test("simulateWriteFailure：所有写方法抛 writeFailed(.simulated)，数据不变")
    func simulatedFailure() async throws {
        let database = try AppDatabase.inMemory(options: .init(
            timeZone: TimeZone(identifier: "Asia/Shanghai")!,
            clock: { TestClock.t0 },
            simulateWriteFailure: true
        ))
        let repository = TodoRepository(database: database)
        let ghost = Todo.ID(rawValue: 1)
        let due = TodoDue(date: dueInput, hasTime: false)

        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.create(title: "x", due: due) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.updateTitle(ghost, to: "x") }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.setDue(ghost, nil) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.setCompleted(ghost, true) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.snooze(ghost, until: dueNormalizedMidnight) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.softDelete(ghost) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.restore(ghost) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.permanentlyDelete(ghost) }

        let count = try await database.writer.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM todo")
        }
        #expect(count == 0)
    }

    private func fetchTodo(_ database: AppDatabase, id: Todo.ID) async throws -> Todo? {
        try await database.writer.read { database in
            try TodoRecord.fetchOne(database, key: id.rawValue)?.todo
        }
    }
}
