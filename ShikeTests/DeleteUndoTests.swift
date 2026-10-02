// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.8：删除与撤销（app-shell.md「组件契约」、03 §7、NFR18/19）。
/// 视觉批次（2026-09-29）：反馈条改为删除/恢复双视角（PanelModel.DeletedBarState），
/// 撤销成功必须给出"已恢复「…」"并附剩余可撤销数。
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

    @Test("删除入栈并显示「已删除」反馈条（摘要前 12 字）；撤销后切换为「已恢复」并清点剩余")
    func deleteShowsBarAndUndoRestores() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let long = try await environment.noteRepository.create(content: "这是一条超过十二个字的便签内容用来验证摘要截断")
        _ = try await environment.noteRepository.create(content: "占位便签保证删除后列表非空")
        try await waitUntilList(model, "两条便签") { $0.notes.count == 2 }

        let orderBefore = model.unpinnedNotes.map { $0.note.content }
        await model.deleteNote(long.id)
        #expect(model.deletedStack.count == 1)
        #expect(model.deletedBar == .deleted("这是一条超过十二个字的便…")) // 前 12 字 + 省略号
        try await waitUntilList(model, "恢复便签") { $0.notes.count == 1 }

        // 撤销：恢复且按 updatedAt 回到原排序位（restore 只清 deletedAt，ADR-017）；
        // 反馈条切换为"已恢复"视角（剩余 0 条不显示附注）
        model.undoLastDelete()
        try await waitUntilList(model, "两条便签") { $0.notes.count == 2 }
        #expect(model.deletedStack.isEmpty)
        try await waitUntilList(model) {
            $0.deletedBar == .recovered("这是一条超过十二个字的便…", remaining: 0)
        }
        #expect(model.unpinnedNotes.map { $0.note.content } == orderBefore) // 顺序不变
    }

    @Test("连续删除：反馈条显示最近一条；⌘Z 按删除先后逆序逐条撤销并报剩余数")
    func consecutiveDeletesAndZUndoOrder() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let a = try await environment.noteRepository.create(content: "甲")
        let b = try await environment.todoRepository.create(title: "乙待办", due: nil)
        try await waitUntilList(model, "两组非空") { !$0.notes.isEmpty && !$0.todos.isEmpty }

        await model.deleteNote(a.id)
        await model.deleteTodo(b.id)
        #expect(model.deletedStack.count == 2)
        #expect(model.deletedBar == .deleted("乙待办")) // 最近一条

        // ⌘Z 第一下：恢复待办（最近删的先恢复），反馈条报"还可撤销 1 条"
        #expect(model.undoLastDeleteIfNeeded() == true)
        try await waitUntilList(model, "恢复待办") { $0.todos.count == 1 }
        try await waitUntilList(model) { $0.deletedBar == .recovered("乙待办", remaining: 1) }
        // ⌘Z 第二下：恢复便签，剩余 0
        #expect(model.undoLastDeleteIfNeeded() == true)
        try await waitUntilList(model, "恢复便签") { $0.notes.count == 1 }
        try await waitUntilList(model) { $0.deletedBar == .recovered("甲", remaining: 0) }
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
        try await waitUntilList(model, "便签非空") { !$0.notes.isEmpty }
        await model.deleteNote(note.id)
        #expect(model.deletedStack.count == 1)

        // 编辑态：⌘Z 不消费（交回文字撤销）
        model.editingNoteID = note.id
        #expect(model.undoLastDeleteIfNeeded() == false)
        #expect(model.deletedStack.count == 1) // 栈未动

        // Esc：先结束编辑（再按一次才是撤销删除）
        #expect(model.endEditingIfNeeded() == true)
        #expect(model.undoLastDeleteIfNeeded() == true)
        try await waitUntilList(model, "便签非空") { !$0.notes.isEmpty }
    }

    @Test("编辑清空=删除并入撤销栈（2.6 交接）；撤销后内容不变")
    func clearingEditGoesThroughUndoStack() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "将被清空的便签")
        try await waitUntilList(model, "便签非空") { !$0.notes.isEmpty }

        await model.saveNoteContent(note.id, "  ")
        try await waitUntilList(model) { $0.notes.isEmpty }
        #expect(model.deletedStack.count == 1)
        #expect(model.deletedBar == .deleted("将被清空的便签"))

        model.undoLastDelete()
        try await waitUntilList(model, "便签非空") { !$0.notes.isEmpty }
        #expect(model.notes[0].note.content == "将被清空的便签") // 内容不变
    }

    @Test("定点撤销（条按钮路径）：恢复 kind 指向条目而非栈顶；编辑态不被守卫吞掉；kind 不在栈内静默收条")
    func targetedBarUndoRestoresNamedItem() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "定点撤销的便签")
        let todo = try await environment.todoRepository.create(title: "后删的待办", due: nil)
        try await waitUntilList(model, "两组非空") { !$0.notes.isEmpty && !$0.todos.isEmpty }

        await model.deleteNote(note.id)
        await model.deleteTodo(todo.id)
        #expect(model.deletedStack.count == 2)
        #expect(model.deletedBar == .deleted("后删的待办")) // 栈顶/条面是待办

        // 编辑态中点条按钮：不被 ⌘Z 的守卫吞掉（守卫只仲裁键盘撤销），定点恢复便签
        model.editingNoteID = note.id
        model.undoDeleteFromBar(kind: .note(note.id))
        try await waitUntilList(model, "定点恢复便签") { $0.notes.count == 1 }
        #expect(model.deletedStack.count == 1) // 待办仍在栈内
        try await waitUntilList(model) {
            $0.deletedBar == .recovered("定点撤销的便签", remaining: 1)
        }
        model.editingNoteID = nil

        // kind 已不在栈内（已被恢复）：静默收条语义——不重复恢复、不动剩余栈、不报 notFound
        model.undoDeleteFromBar(kind: .note(note.id))
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.deletedStack.count == 1) // 待办未被动过
        #expect(model.banner == nil) // 无 notFound 横幅

        // 面板条按钮（恒为栈顶）：恢复待办
        model.undoLastDeleteFromBar()
        try await waitUntilList(model, "条按钮恢复待办") { $0.todos.count == 1 }
        try await waitUntilList(model) {
            $0.deletedBar == .recovered("后删的待办", remaining: 0)
        }
    }

    @Test("反馈条计时：延迟注入后到时消失；连续删除重置；撤销先切「已恢复」视角再重启计时")
    func deletedBarTimer() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()
        model.deletedBarHideDelay = .milliseconds(150)

        let note = try await environment.noteRepository.create(content: "计时验证")
        try await waitUntilList(model, "便签非空") { !$0.notes.isEmpty }

        // 删除显示；约 150ms 后自动消失
        await model.deleteNote(note.id)
        #expect(model.deletedBar != nil)
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.deletedBar == nil)

        // 连续删除：显示最近一条；撤销切"已恢复"，随后重启的计时到点消失
        let a = try await environment.noteRepository.create(content: "甲（撤销条）")
        _ = try await environment.todoRepository.create(title: "乙（撤销条）", due: nil)
        try await waitUntilList(model, "两组非空") { !$0.notes.isEmpty && !$0.todos.isEmpty }
        await model.deleteNote(a.id)
        await model.deleteTodo(todoID(model, title: "乙（撤销条）"))
        #expect(model.deletedBar == .deleted("乙（撤销条）"))
        model.undoLastDelete()
        // 注意：更早删除的「计时验证」从未撤销、仍在栈中，剩余应为 2
        try await waitUntilList(model, "恢复视角-乙（计时）") { $0.deletedBar == .recovered("乙（撤销条）", remaining: 2) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.deletedBar == nil) // 重启的计时到点消失
    }

    /// 按标题找待办 id。
    private func todoID(_ model: PanelModel, title: String) -> Todo.ID {
        model.todos.first { $0.title == title }!.id
    }
}
