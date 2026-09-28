// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.7：待办列表与完成（app-shell.md「组件契约」、03 §6）。
@MainActor
struct TodoListTests {
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
        _ condition: (PanelModel) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition(model) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if condition(model) { return }
        let snapshot = model.todos.map { "\($0.title)|done=\($0.completedAt != nil)" }.joined(separator: ", ")
        Issue.record("等待列表条件超时：todos=[\(snapshot)]")
    }

    @Test("分组：待办在前（新建的在上），已完成（N）独立分组")
    func grouping() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let first = try await environment.todoRepository.create(title: "第一条", due: nil)
        _ = try await environment.todoRepository.create(title: "第二条", due: nil)
        try await waitUntilList(model) { $0.todos.count == 2 }

        #expect(model.activeTodos.map { $0.title } == ["第二条", "第一条"]) // 新建的在上
        #expect(model.completedTodos.isEmpty)

        try await environment.todoRepository.setCompleted(first.id, true)
        try await waitUntilList(model) { $0.completedTodos.count == 1 }
        #expect(model.completedTodos.map { $0.title } == ["第一条"])
        #expect(model.activeTodos.map { $0.title } == ["第二条"])
    }

    @Test("勾选三态：立即进入待移入；延迟后落库；期间再点取消（延迟可注入）")
    func completionThreeStatesWithCancellableDelay() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()
        model.completionDelay = .milliseconds(120)

        let todo = try await environment.todoRepository.create(title: "勾我", due: nil)
        try await waitUntilList(model) { !$0.todos.isEmpty }

        // 1) 点击：立即进入"待移入"，数据未变
        model.toggleTodoCompletion(todo.id)
        #expect(model.pendingCompletionIDs.contains(todo.id))
        #expect(todo.completedAt == nil) // 观察流尚未推送（数据层 1 个注入延迟后才写）

        // 2) 期间再点：取消（数据永远未写）
        model.toggleTodoCompletion(todo.id)
        #expect(!model.pendingCompletionIDs.contains(todo.id))
        try await Task.sleep(for: .milliseconds(250))
        #expect(model.activeTodos.count == 1 && model.completedTodos.isEmpty)

        // 3) 再次点击：延迟后落库移组
        model.toggleTodoCompletion(todo.id)
        #expect(model.pendingCompletionIDs.contains(todo.id))
        try await waitUntilList(model) { $0.completedTodos.count == 1 }
        #expect(!model.pendingCompletionIDs.contains(todo.id))

        // 4) 已完成组点击：勾回
        model.toggleTodoCompletion(todo.id)
        try await waitUntilList(model) { $0.activeTodos.count == 1 && $0.completedTodos.isEmpty }
    }

    @Test("标题编辑：endEditing 保存改动；空标题不保存；编辑中 Esc 消费")
    func titleEditing() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let todo = try await environment.todoRepository.create(title: "原标题", due: nil)
        try await waitUntilList(model) { !$0.todos.isEmpty }

        // 有待办标题编辑时，Esc 消费并保存
        model.editingTodoID = todo.id
        model.editingTodoText = "改过的标题"
        #expect(model.endEditingIfNeeded() == true)
        try await waitUntilList(model) { $0.todos[0].title == "改过的标题" }

        // 空标题：不保存（回退）
        model.editingTodoID = todo.id
        model.editingTodoText = "   "
        #expect(model.endEditingIfNeeded() == true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.todos[0].title == "改过的标题")
    }

    @Test("便签与待办编辑互斥：endEditing 先结束便签，再按一次结束待办")
    func editingAcrossModesIsSequential() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "便签")
        let todo = try await environment.todoRepository.create(title: "待办", due: nil)
        try await waitUntilList(model) { !$0.notes.isEmpty && !$0.todos.isEmpty }

        model.editingNoteID = note.id
        model.editingTodoID = todo.id

        #expect(model.endEditingIfNeeded() == true) // 先结束便签
        #expect(model.editingNoteID == nil)
        #expect(model.editingTodoID != nil)
        #expect(model.endEditingIfNeeded() == true) // 再结束待办
        #expect(model.editingTodoID == nil)
        #expect(model.endEditingIfNeeded() == false) // 都结束了
    }
}
