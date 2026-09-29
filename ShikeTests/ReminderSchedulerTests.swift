// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing
import UserNotifications

@testable import Shike
@testable import ShikeData // Todo 的 memberwise init 是 internal（包内约定）

/// Story 3.5：通知调度对账（SPEC CAP-5、stage-2-components.md §3、NFR20/21）。
@MainActor
struct ReminderSchedulerTests {
    /// 内存替身：维护 pending 字典，验证增删与幂等。
    private final class StubScheduling: NotificationScheduling {
        var status: UNAuthorizationStatus = .authorized
        var requested = 0
        var pending: [String: Date] = [:]
        var removedBatches: [[String]] = []

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async -> Bool {
            requested += 1
            return true
        }
        func pendingIdentifiers() async -> [String] { Array(pending.keys) }
        func add(identifier: String, title: String, body: String, userInfo: [String: String], fireDate: Date) async {
            pending[identifier] = fireDate
        }
        func removePending(identifiers: [String]) async {
            removedBatches.append(identifiers)
            for id in identifiers { pending.removeValue(forKey: id) }
        }
    }

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

    private func todo(title: String, due: TodoDue?, uuid: UUID = UUID()) -> Todo {
        Todo(
            id: Todo.ID(rawValue: 1),
            uuid: uuid,
            title: title,
            due: due,
            snoozedUntil: nil,
            completedAt: nil,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: nil
        )
    }

    private func makeScheduler(
        scheduling: StubScheduling,
        todos: @escaping () -> [Todo],
        allDayMinutes: Int = 540
    ) -> ReminderScheduler {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
        preferences.reminderAllDayMinutes = allDayMinutes
        return ReminderScheduler(
            scheduling: scheduling,
            todosProvider: todos,
            preferences: preferences,
            timeZoneProvider: { Self.timeZone },
            nowProvider: { Self.now }
        )
    }

    @Test("对账：按计划排期；重复对账幂等（无重复通知，NFR20）")
    func reconcileIsIdempotent() async {
        let stub = StubScheduling()
        let uuid = UUID()
        let todos = [todo(title: "周五交报告", due: TodoDue(date: Self.now.addingTimeInterval(3600), hasTime: true), uuid: uuid)]
        let scheduler = makeScheduler(scheduling: stub, todos: { todos })

        await scheduler.reconcile()
        #expect(stub.pending.count == 1)
        #expect(stub.pending[uuid.uuidString] != nil)

        // 相同数据再对账：pending 不变、无重复
        await scheduler.reconcile()
        #expect(stub.pending.count == 1)
        #expect(stub.pending[uuid.uuidString] != nil)
    }

    @Test("对账：完成的待办撤销其通知；改时间重写触发时刻")
    func reconcileRemovesAndRewrites() async {
        let stub = StubScheduling()
        let kept = UUID()
        let done = UUID()
        var todos = [
            todo(title: "保留", due: TodoDue(date: Self.now.addingTimeInterval(3600), hasTime: true), uuid: kept),
            todo(title: "完成", due: TodoDue(date: Self.now.addingTimeInterval(7200), hasTime: true), uuid: done),
        ]
        let scheduler = makeScheduler(scheduling: stub, todos: { todos })
        await scheduler.reconcile()
        #expect(stub.pending.count == 2)

        // 完成"完成"
        todos = [todos[0]]
        await scheduler.reconcile()
        #expect(stub.pending.count == 1)
        #expect(stub.pending[kept.uuidString] != nil)
        #expect(stub.pending[done.uuidString] == nil)
        #expect(stub.removedBatches.contains { $0.contains(done.uuidString) })

        // 改"保留"的时间：同一标识重写为新时刻
        todos = [todo(title: "保留", due: TodoDue(date: Self.now.addingTimeInterval(10800), hasTime: true), uuid: kept)]
        await scheduler.reconcile()
        #expect(stub.pending[kept.uuidString] == Self.now.addingTimeInterval(10800))
    }

    @Test("对账：只排前 50 条（limit 透传 ReminderPlan）")
    func reconcileRespectsLimit() async {
        let stub = StubScheduling()
        var todos = (0...54).map { index in
            todo(
                title: "t\(index)",
                due: TodoDue(date: Self.now.addingTimeInterval(TimeInterval(3600 + index * 60)), hasTime: true),
                uuid: UUID()
            )
        }
        let scheduler = makeScheduler(scheduling: stub, todos: { todos })
        await scheduler.reconcile()
        #expect(stub.pending.count == 50)

        todos.removeLast(5)
        await scheduler.reconcile()
        #expect(stub.pending.count == 50) // 55 → 50 条：全部进计划
        #expect(stub.pending.count == todos.count)
    }

    @Test("数据变化 0.5 秒合并：连续多次 scheduleReconcile 只执行一次（NFR21）")
    func debouncedReconcile() async {
        let stub = StubScheduling()
        let todos = [todo(title: "t", due: TodoDue(date: Self.now.addingTimeInterval(3600), hasTime: true))]
        let scheduler = makeScheduler(scheduling: stub, todos: { todos })

        scheduler.scheduleReconcile()
        scheduler.scheduleReconcile()
        scheduler.scheduleReconcile()

        // 合并窗口 0.5 秒：截止轮询等首次对账（CI 计时抖动安全，盲审 F6）
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline, scheduler.reconcileCount == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(scheduler.reconcileCount == 1)
        // 合并语义：等待窗口过后仍只有 1 次（多出的都被取消）
        try? await Task.sleep(for: .milliseconds(300))
        #expect(scheduler.reconcileCount == 1)
    }

    @Test("跨天与唤醒触发重对账（L2 直调路由）")
    func systemEventHandlersTriggerReconcile() async {
        let stub = StubScheduling()
        let todos = [todo(title: "t", due: TodoDue(date: Self.now.addingTimeInterval(3600), hasTime: true))]
        let scheduler = makeScheduler(scheduling: stub, todos: { todos })

        scheduler.handleDayChanged()
        var deadline = Date().addingTimeInterval(2)
        while Date() < deadline, scheduler.reconcileCount == 0 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(scheduler.reconcileCount == 1)

        scheduler.handleWake()
        deadline = Date().addingTimeInterval(2)
        while Date() < deadline, scheduler.reconcileCount < 2 {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(scheduler.reconcileCount == 2)
    }

    @Test("通知正文经协调器口径：带时刻/全天")
    func bodyMatchesCoordinator() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let fire = calendar.date(byAdding: .minute, value: 30, to: Self.now)!
        #expect(
            NotificationCoordinator.body(due: TodoDue(date: fire, hasTime: true), now: Self.now, timeZone: Self.timeZone)
                == "今天 10:30"
        )
        #expect(
            NotificationCoordinator.body(due: TodoDue(date: calendar.startOfDay(for: Self.now), hasTime: false), now: Self.now, timeZone: Self.timeZone)
                == "全天 · 今天"
        )
    }
}
