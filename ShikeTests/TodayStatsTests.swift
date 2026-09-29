// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// 纸感视觉批次（2026-09-29）：底部统计条口径。
/// "今天记了 N 条" = 现存便签中今天创建的（软删除的不算，与列表所见一致）；
/// "待办完成 N 条" = 今天完成的待办（跨天不重算昨天的完成）。
@MainActor
struct TodayStatsTests {
    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        return (environment, suiteName)
    }

    private func waitUntilList(
        _ model: PanelModel,
        timeoutSeconds: Double = 2,
        _ label: String = "",
        _ condition: (PanelModel) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition(model) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if condition(model) { return }
        Issue.record("等待超时：\(label)")
    }

    @Test("空列表：今天记了 0 条、完成 0 条")
    func emptyCountsZero() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start() // 列表断言依赖观察流推送
        #expect(model.todayActivity.notesCreated == 0)
        #expect(model.todayActivity.todosCompleted == 0)
    }

    @Test("今天创建的便签计数；软删除的不算")
    func countsNotesCreatedToday() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start() // 列表断言依赖观察流推送
        let a = try await environment.noteRepository.create(content: "甲")
        _ = try await environment.noteRepository.create(content: "乙")
        try await waitUntilList(model, "两条便签到位") { $0.notes.count == 2 }
        #expect(model.todayActivity.notesCreated == 2)
        // 删除一条后按现存口径计数
        try await environment.noteRepository.softDelete(a.id)
        try await waitUntilList(model, "软删除后剩一条") { $0.notes.count == 1 }
        #expect(model.todayActivity.notesCreated == 1)
    }

    @Test("今天完成的待办计数；勾回后归零")
    func countsTodosCompletedToday() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start() // 列表断言依赖观察流推送
        let a = try await environment.todoRepository.create(title: "甲", due: nil)
        _ = try await environment.todoRepository.create(title: "乙", due: nil)
        try await waitUntilList(model, "两条待办到位") { $0.todos.count == 2 }
        #expect(model.todayActivity.todosCompleted == 0)
        try await environment.todoRepository.setCompleted(a.id, true)
        try await waitUntilList(model, "甲已完成") { $0.todayActivity.todosCompleted == 1 }
        try await environment.todoRepository.setCompleted(a.id, false)
        try await waitUntilList(model, "甲勾回") { $0.todayActivity.todosCompleted == 0 }
    }

    @Test("昨天创建的便签与昨天完成的待办不计入今天（clock 注入到昨天）")
    func ignoresYesterdayActivity() async throws {
        // GRDB 被 internal import 隐藏，"昨天"用 AppDatabase.Options.clock 注入：
        // 昨天库里的所有时间戳都是昨天 —— 便签 createdAt、待办 completedAt 皆然。
        let yesterdayClock: @Sendable () -> Date = {
            Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        }
        let yesterdaySuite = "shike-tests-\(UUID().uuidString)"
        let yesterdayEnvironment = try AppEnvironment(
            database: AppDatabase.inMemory(options: AppDatabase.Options(clock: yesterdayClock)),
            preferences: Preferences(defaults: UserDefaults(suiteName: yesterdaySuite)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        defer { UserDefaults.standard.removePersistentDomain(forName: yesterdaySuite) }
        let yesterdayModel = yesterdayEnvironment.panelModel
        yesterdayModel.start() // 列表断言依赖观察流推送
        let note = try await yesterdayEnvironment.noteRepository.create(content: "昨天记的")
        let todo = try await yesterdayEnvironment.todoRepository.create(title: "昨天完成", due: nil)
        try await yesterdayEnvironment.todoRepository.setCompleted(todo.id, true)
        // 等列表先非空再断言统计为 0（否则"还没到数据"会伪装成通过）
        try await waitUntilList(yesterdayModel, "昨天的数据到位") {
            !$0.notes.isEmpty && !$0.todos.isEmpty
                && $0.todos.first { $0.id == todo.id }?.completedAt != nil
        }
        _ = note
        #expect(yesterdayModel.todayActivity.notesCreated == 0)
        #expect(yesterdayModel.todayActivity.todosCompleted == 0)

        // 对照组：正常时钟下的今天数据照常计数
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start() // 列表断言依赖观察流推送
        _ = try await environment.noteRepository.create(content: "今天记的")
        let todayTodo = try await environment.todoRepository.create(title: "今天完成", due: nil)
        try await environment.todoRepository.setCompleted(todayTodo.id, true)
        try await waitUntilList(model, "今天的数据到位") {
            $0.todayActivity.notesCreated == 1 && $0.todayActivity.todosCompleted == 1
        }
    }
}
