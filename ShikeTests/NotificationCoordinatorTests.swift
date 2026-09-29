// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing
import UserNotifications

@testable import Shike

/// Story 3.4：到点通知（SPEC CAP-4、stage-2-components.md §3/§4、NFR23）。
/// 全部经 NotificationScheduling 内存替身，零真实权限与通知调用。
@MainActor
struct NotificationCoordinatorTests {
    /// 内存替身：记录排期与授权状态。
    private final class StubScheduling: NotificationScheduling {
        var status: UNAuthorizationStatus = .notDetermined
        var requested = 0
        var granted = true
        var added: [(identifier: String, title: String, body: String, userInfo: [String: String], fireDate: Date)] = []
        var removed: [[String]] = []

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async -> Bool {
            requested += 1
            return granted
        }
        func pendingIdentifiers() async -> [String] { added.map(\.identifier) }
        func add(identifier: String, title: String, body: String, userInfo: [String: String], fireDate: Date) async {
            added.append((identifier, title, body, userInfo, fireDate))
        }
        func removePending(identifiers: [String]) async { removed.append(identifiers) }
    }

    // 基准 T0 = 2026-09-28 10:00 Asia/Shanghai
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

    private func makeModel(scheduling: StubScheduling) throws -> (PanelModel, AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true),
            notificationScheduling: scheduling
        )
        let model = environment.panelModel
        model.timeZone = Self.timeZone
        model.parseNow = { Self.now }
        model.start() // 订阅观察流：todos 依赖它更新
        return (model, environment, suiteName)
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // - MARK: 动作路由

    @Test("动作路由：完成 / 稍后提醒（按偏好档位）/ 点本体打开面板定位（L2 核心路由）")
    func actionRouting() throws {
        let scheduling = StubScheduling()
        var completed: [UUID] = []
        var snoozed: [(UUID, Date)] = []
        var opened: [UUID] = []
        let coordinator = NotificationCoordinator(
            scheduling: scheduling,
            handlers: .init(
                complete: { completed.append($0) },
                snooze: { snoozed.append(($0, $1)) },
                snoozeMinutes: { 15 }
            )
        )
        coordinator.openPanelHandler = { opened.append($0) }

        let uuid = UUID()
        coordinator.handleAction(identifier: NotificationCoordinator.completeActionID, todoUUID: uuid)
        #expect(completed == [uuid])

        coordinator.handleAction(identifier: NotificationCoordinator.snoozeActionID, todoUUID: uuid)
        #expect(snoozed.count == 1)
        #expect(snoozed[0].0 == uuid)
        // 15 分钟档位：snoozeUntil ≈ now + 15 分钟
        #expect(abs(snoozed[0].1.timeIntervalSinceNow - 15 * 60) < 5)

        coordinator.handleAction(identifier: UNNotificationDefaultActionIdentifier, todoUUID: uuid)
        #expect(opened == [uuid])

        // 缺 uuid：不崩、不动作
        coordinator.handleAction(identifier: NotificationCoordinator.completeActionID, todoUUID: nil)
        #expect(completed.count == 1)
    }

    @Test("通知正文：带时刻用时间文案，全天为「全天 · 今天」")
    func notificationBodyVariants() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let today15 = calendar.date(bySettingHour: 15, minute: 0, second: 0, of: Self.now)!
        #expect(
            NotificationCoordinator.body(due: TodoDue(date: today15, hasTime: true), now: Self.now, timeZone: Self.timeZone)
                == "今天 15:00"
        )
        #expect(
            NotificationCoordinator.body(due: TodoDue(date: calendar.startOfDay(for: Self.now), hasTime: false), now: Self.now, timeZone: Self.timeZone)
                == "全天 · 今天"
        )
    }

    // - MARK: 面板侧：权限请求时机与通知动作落库

    @Test("提交带时间待办触发权限请求；无时间与 ✕ 取消不触发")
    func permissionRequestedOnlyForTimefulSubmissions() async throws {
        let scheduling = StubScheduling()
        let (model, _, suiteName) = try makeModel(scheduling: scheduling)
        defer { cleanup(suiteName) }
        model.mode = .todo

        model.draftTodo = "记得还信用卡" // 无时间词
        model.submitCurrentDraft()
        try await waitUntil { model.draftTodo == "" }
        #expect(scheduling.requested == 0)

        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        try await waitUntil { scheduling.requested == 1 }

        // ✕ 取消识别后提交：无 due，不再触发
        model.draftTodo = "明天交报告"
        try await waitUntil { model.recognition != nil }
        model.dismissRecognition()
        model.submitCurrentDraft()
        try await waitUntil { model.draftTodo == "" } // 提交成功清空
        #expect(scheduling.requested == 1)
    }

    @Test("通知动作落库：完成与稍后提醒写对目标（uuid 定位）")
    func notificationActionsPersistViaRepository() async throws {
        let scheduling = StubScheduling()
        let (model, environment, suiteName) = try makeModel(scheduling: scheduling)
        defer { cleanup(suiteName) }
        model.mode = .todo
        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        try await waitUntil { !model.todos.isEmpty }
        let uuid = model.todos[0].uuid
        // 环境里装配的协调器：handlers 指向同一 panelModel
        let coordinator = environment.notificationCoordinator

        // 稍后提醒：写 snoozedUntil（默认 10 分钟档）
        coordinator.handleAction(identifier: NotificationCoordinator.snoozeActionID, todoUUID: uuid)
        try await waitUntil {
            model.todos.first(where: { $0.uuid == uuid })?.snoozedUntil != nil
        }
        #expect(model.todos.first(where: { $0.uuid == uuid })!.snoozedUntil!.timeIntervalSince(Date()) > 9 * 60)

        // 完成：completedAt 落库
        coordinator.handleAction(identifier: NotificationCoordinator.completeActionID, todoUUID: uuid)
        try await waitUntil {
            model.todos.first(where: { $0.uuid == uuid })?.completedAt != nil
        }

        // 盲审 F5：对已完成待办再点"稍后提醒"，不写脏 snoozedUntil
        coordinator.handleAction(identifier: NotificationCoordinator.snoozeActionID, todoUUID: uuid)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.todos.first(where: { $0.uuid == uuid })?.snoozedUntil == nil)
    }

    @Test("定位：locateTodo 切待办模式并设置 1.5 秒定位目标")
    func locateTodoSetsTargetAndClears() async throws {
        let (model, _, suiteName) = try makeModel(scheduling: StubScheduling())
        defer { cleanup(suiteName) }
        let uuid = UUID()
        model.locateTodo(uuid: uuid)
        #expect(model.mode == .todo)
        #expect(model.locateTodoID == uuid.uuidString)
        // 1.5 秒后清除（截止轮询，上限 3 秒）
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline, model.locateTodoID != nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(model.locateTodoID == nil)
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
