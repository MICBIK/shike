// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.8：删除与撤销（app-shell.md「组件契约」、03 §7、NFR18/19）。
@MainActor
struct DeleteUndoTests {
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
        Issue.record("等待列表条件超时")
    }

    @Test("删除入栈并显示撤销条（摘要前 12 字）；撤销恢复且排序位置不变")
    func deleteShowsBarAndUndoRestores() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let long = try await environment.noteRepository.create(content: "这是一条超过十二个字的便签内容用来验证摘要截断")
        _ = try await environment.noteRepository.create(content: "占位便签保证删除后列表非空")
        try await waitUntilList(model) { $0.notes.count == 2 }

        let orderBefore = model.unpinnedNotes.map { $0.note.content }
        await model.deleteNote(long.id)
        #expect(model.deletedStack.count == 1)
        #expect(model.deletedBarSummary == "这是一条超过十二个字的便…") // 前 12 字 + 省略号
        try await waitUntilList(model) { $0.notes.count == 1 }

        // 撤销：恢复且按 updatedAt 回到原排序位（restore 只清 deletedAt，ADR-017）
        model.undoLastDelete()
        try await waitUntilList(model) { $0.notes.count == 2 }
        #expect(model.deletedStack.isEmpty)
        try await waitUntilList(model) { $0.deletedBarSummary == nil } // 撤销刷新是异步的：栈空收起
        #expect(model.unpinnedNotes.map { $0.note.content } == orderBefore) // 顺序不变
    }

    @Test("连续删除：提示条显示最近一条；⌘Z 按删除先后逆序逐条撤销")
    func consecutiveDeletesAndZUndoOrder() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let a = try await environment.noteRepository.create(content: "甲")
        let b = try await environment.todoRepository.create(title: "乙待办", due: nil)
        try await waitUntilList(model) { !$0.notes.isEmpty && !$0.todos.isEmpty }

        await model.deleteNote(a.id)
        await model.deleteTodo(b.id)
        #expect(model.deletedStack.count == 2)
        #expect(model.deletedBarSummary == "乙待办") // 最近一条

        // ⌘Z 第一下：恢复待办（最近删的先恢复）
        #expect(model.undoLastDeleteIfNeeded() == true)
        try await waitUntilList(model) { $0.todos.count == 1 }
        // ⌘Z 第二下：恢复便签
        #expect(model.undoLastDeleteIfNeeded() == true)
        try await waitUntilList(model) { $0.notes.count == 1 }
        // 栈空：⌘Z 无反应
        #expect(model.undoLastDeleteIfNeeded() == false)
        _ = a
    }

    @Test("编辑态：⌘Z 不做删除撤销（交回文字撤销）；Esc 先结束编辑")
    func editingStateGuardsUndo() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "在编辑")
        try await waitUntilList(model) { !$0.notes.isEmpty }
        await model.deleteNote(note.id)
        #expect(model.deletedStack.count == 1)

        // 编辑态：⌘Z 不消费（交回文字撤销）
        model.editingNoteID = note.id
        #expect(model.undoLastDeleteIfNeeded() == false)
        #expect(model.deletedStack.count == 1) // 栈未动

        // Esc：先结束编辑（再按一次才是撤销删除）
        #expect(model.endEditingIfNeeded() == true)
        #expect(model.undoLastDeleteIfNeeded() == true)
        try await waitUntilList(model) { !$0.notes.isEmpty }
    }

    @Test("编辑清空=删除并入撤销栈（2.6 交接）；撤销后内容不变")
    func clearingEditGoesThroughUndoStack() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "将被清空的便签")
        try await waitUntilList(model) { !$0.notes.isEmpty }

        await model.saveNoteContent(note.id, "  ")
        try await waitUntilList(model) { $0.notes.isEmpty }
        #expect(model.deletedStack.count == 1)
        #expect(model.deletedBarSummary == "将被清空的便签")

        model.undoLastDelete()
        try await waitUntilList(model) { !$0.notes.isEmpty }
        #expect(model.notes[0].note.content == "将被清空的便签") // 内容不变
    }

    @Test("提示条计时：延迟注入后到时消失；连续删除重置；撤销显示下一条")
    func deletedBarTimer() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()
        model.deletedBarHideDelay = .milliseconds(150)

        let note = try await environment.noteRepository.create(content: "计时验证")
        try await waitUntilList(model) { !$0.notes.isEmpty }

        // 删除显示；约 150ms 后自动消失
        await model.deleteNote(note.id)
        #expect(model.deletedBarSummary != nil)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.deletedBarSummary == nil)

        // 连续删除：显示最近一条；撤销后显示下一条并重启计时
        let a = try await environment.noteRepository.create(content: "甲（撤销条）")
        _ = try await environment.todoRepository.create(title: "乙（撤销条）", due: nil)
        try await waitUntilList(model) { !$0.notes.isEmpty && !$0.todos.isEmpty }
        await model.deleteNote(a.id)
        await model.deleteTodo(todoID(model, title: "乙（撤销条）"))
        #expect(model.deletedBarSummary == "乙（撤销条）")
        model.undoLastDelete()
        // 撤销刷新（restore→refresh）是异步的：轮询等待下一条显示
        try await waitUntilList(model) { $0.deletedBarSummary == "甲（撤销条）" }
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.deletedBarSummary == nil) // 重启的计时到点消失
    }

    /// 按标题找待办 id。
    private func todoID(_ model: PanelModel, title: String) -> Todo.ID {
        model.todos.first { $0.title == title }!.id
    }
}
