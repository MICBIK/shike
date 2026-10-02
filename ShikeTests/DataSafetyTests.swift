// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // NoteListItem 的 memberwise init 是 internal（包内约定）

/// 夜间缺陷修复（2026-10-03，交接 §2 卡A）：
/// C3 待移入窗内删除取消完成计时器（UI 侧清理 + 仓储 WHERE 守卫双保险）；
/// C4 面板快照缺 id 时兜底直写仓储（宁可报错不能静默丢失）。
/// 快照命中路径的既有语义由 LateDebounceGuardTests 等既有用例守护，本文件不重复。
@MainActor
struct DataSafetyTests {
    private func makeModel() throws -> (PanelModel, NoteRepository, TodoRepository, () -> Void) {
        let database = try AppDatabase.inMemory()
        let noteRepository = NoteRepository(database: database)
        let todoRepository = TodoRepository(database: database)
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
        let model = PanelModel(noteRepository: noteRepository, todoRepository: todoRepository, preferences: preferences)
        return (model, noteRepository, todoRepository, { UserDefaults.standard.removePersistentDomain(forName: suiteName) })
    }

    /// 一次性流（播种模型快照用）：runNotes/runTodos 消费完即返回。
    private func oneShotNotes(_ items: [NoteListItem]) -> AsyncThrowingStream<[NoteListItem], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    private func oneShotTodos(_ items: [Todo]) -> AsyncThrowingStream<[Todo], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 写操作落库后新建观察流取首帧（首帧即当前全量）。
    private func activeTodos(_ repository: TodoRepository) async throws -> [Todo] {
        var iterator = repository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func activeNotes(_ repository: NoteRepository) async throws -> [NoteListItem] {
        var iterator = repository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    /// 轮询直到条件成立或超时（撤销恢复走 fire-and-forget Task）。
    private func waitUntil(
        _ label: String,
        timeoutSeconds: Double = 2,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("等待超时：\(label)")
    }

    // - MARK: C3 待移入窗内删除的计时器清理

    @Test("C3：待移入窗内删除待办，计时器取消——回收站行不被标完成")
    func deleteTodoCancelsCompletionTimer() async throws {
        let (model, _, todoRepository, cleanup) = try makeModel()
        defer { cleanup() }
        model.completionDelay = .milliseconds(120)
        let todo = try await todoRepository.create(title: "一秒内删除的待办", due: nil)
        await model.runTodos(oneShotTodos([todo]))

        model.toggleTodoCompletion(todo.id)
        #expect(model.pendingCompletionIDs.contains(todo.id))
        await model.deleteTodo(todo.id)

        // 删除即清"待移入"标记（计时器已取消，行不再划线变灰——撤销恢复后直接可用）
        #expect(!model.pendingCompletionIDs.contains(todo.id))

        // 越过原计时窗口：回收站行 completedAt 仍为空（UI 取消 + 仓储 deletedAt 守卫双保险）
        try await Task.sleep(for: .milliseconds(300))
        let recycled = try await todoRepository.todo(uuid: todo.uuid)
        #expect(recycled?.deletedAt != nil)
        #expect(recycled?.completedAt == nil)
    }

    @Test("C3：待移入窗内删除再撤销，待办保持未完成（不会自己完成）")
    func deleteThenUndoStaysIncomplete() async throws {
        let (model, _, todoRepository, cleanup) = try makeModel()
        defer { cleanup() }
        model.completionDelay = .milliseconds(120)
        let todo = try await todoRepository.create(title: "删了又恢复的待办", due: nil)
        await model.runTodos(oneShotTodos([todo]))

        model.toggleTodoCompletion(todo.id)
        await model.deleteTodo(todo.id)
        #expect(model.undoLastDeleteIfNeeded())

        // 撤销恢复落库，且越过原计时窗口后 completedAt 仍为空
        try await waitUntil("撤销恢复落库") {
            try await self.activeTodos(todoRepository).contains { $0.id == todo.id }
        }
        try await Task.sleep(for: .milliseconds(300))
        let fresh = try await todoRepository.todo(uuid: todo.uuid)
        #expect(fresh?.deletedAt == nil)
        #expect(fresh?.completedAt == nil)
    }

    @Test("C3：删除其中一条不影响另一条待移入待办照常完成")
    func deletingOneDoesNotDisturbOtherTimer() async throws {
        let (model, _, todoRepository, cleanup) = try makeModel()
        defer { cleanup() }
        model.completionDelay = .milliseconds(120)
        let first = try await todoRepository.create(title: "被删除的一条", due: nil)
        let second = try await todoRepository.create(title: "照常完成的一条", due: nil)
        await model.runTodos(oneShotTodos([first, second]))

        model.toggleTodoCompletion(first.id)
        model.toggleTodoCompletion(second.id)
        await model.deleteTodo(first.id)

        // second 到点正常完成
        try await waitUntil("另一条到点完成") {
            try await self.activeTodos(todoRepository).first(where: { $0.id == second.id })?.completedAt != nil
        }
        // first 在回收站仍未完成
        let recycled = try await todoRepository.todo(uuid: first.uuid)
        #expect(recycled?.deletedAt != nil)
        #expect(recycled?.completedAt == nil)
    }

    // - MARK: C4 面板快照缺 id 的兜底直写

    /// C4 测试的播种口径：空快照一次性流正常结束，按 runNotes 语义即"面板观察流
    /// 已失败"（loadFailed 横幅出现）——这正是缺陷场景。此后直写成功只要求
    /// **不新增** saveFailed/notFound 横幅；读失败横幅仍在属如实状态（W3 连带
    /// 评估：两通道文案不打架，交接 §A-C4）。

    @Test("C4：快照缺 id 时便签编辑兜底直写落库（不静默丢弃）")
    func noteContentSnapshotMissWritesThrough() async throws {
        let (model, noteRepository, _, cleanup) = try makeModel()
        defer { cleanup() }
        let note = try await noteRepository.create(content: "原文")
        await model.runNotes(oneShotNotes([]))
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")

        await model.saveNoteContent(note.id, "主窗口改的新内容")

        let rows = try await activeNotes(noteRepository)
        #expect(rows.first(where: { $0.note.id == note.id })?.note.content == "主窗口改的新内容")
        // 直写成功：无新增保存失败提示，原读失败横幅如实保留
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
    }

    @Test("C4：快照缺 id 时空内容仍走清空即删（软删除落库）")
    func noteContentSnapshotMissEmptySoftDeletes() async throws {
        let (model, noteRepository, _, cleanup) = try makeModel()
        defer { cleanup() }
        let note = try await noteRepository.create(content: "将被清空的便签")
        await model.runNotes(oneShotNotes([]))

        await model.saveNoteContent(note.id, "   ")

        var iterator = noteRepository.observeDeleted().makeAsyncIterator()
        let deleted = try await iterator.next() ?? []
        #expect(deleted.contains { $0.id == note.id })
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
    }

    @Test("C4：快照缺 id 且行已删除时软删除幂等静默（不误报）")
    func noteContentSnapshotMissAlreadyDeletedIsSilent() async throws {
        let (model, noteRepository, _, cleanup) = try makeModel()
        defer { cleanup() }
        let note = try await noteRepository.create(content: "已被别处删除的便签")
        try await noteRepository.softDelete(note.id)
        await model.runNotes(oneShotNotes([]))

        await model.saveNoteContent(note.id, "")

        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
        var iterator = noteRepository.observeDeleted().makeAsyncIterator()
        let deleted = try await iterator.next() ?? []
        #expect(deleted.contains { $0.id == note.id })
    }

    @Test("C4：快照缺 id 且行不存在时 notFound 走提示条（诚实报错）")
    func noteContentSnapshotMissUnknownIDShowsNotFoundBanner() async throws {
        let (model, _, _, cleanup) = try makeModel()
        defer { cleanup() }
        await model.runNotes(oneShotNotes([]))

        await model.saveNoteContent(Note.ID(rawValue: 4242), "无主的内容")

        #expect(model.banner?.message == "内容不存在或已被删除")
    }

    @Test("C4：快照缺 id 时待办标题编辑兜底直写落库（不静默丢弃）")
    func todoTitleSnapshotMissWritesThrough() async throws {
        let (model, _, todoRepository, cleanup) = try makeModel()
        defer { cleanup() }
        let todo = try await todoRepository.create(title: "原标题", due: nil)
        await model.runTodos(oneShotTodos([]))

        await model.saveTodoTitle(todo.id, "主窗口改的新标题")

        let rows = try await activeTodos(todoRepository)
        #expect(rows.first(where: { $0.id == todo.id })?.title == "主窗口改的新标题")
        // 待办流失败的播种口径下同理：无新增保存失败提示
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
    }

    @Test("C4：快照缺 id 时空标题仍回退不保存（与快照命中路径同语义）")
    func todoTitleSnapshotMissEmptySkips() async throws {
        let (model, _, todoRepository, cleanup) = try makeModel()
        defer { cleanup() }
        let todo = try await todoRepository.create(title: "原标题", due: nil)
        await model.runTodos(oneShotTodos([]))

        await model.saveTodoTitle(todo.id, "   ")

        let rows = try await activeTodos(todoRepository)
        #expect(rows.first(where: { $0.id == todo.id })?.title == "原标题")
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
    }

    @Test("C4：快照缺 id 且待办不存在时 notFound 走提示条")
    func todoTitleSnapshotMissUnknownIDShowsNotFoundBanner() async throws {
        let (model, _, _, cleanup) = try makeModel()
        defer { cleanup() }
        await model.runTodos(oneShotTodos([]))

        await model.saveTodoTitle(Todo.ID(rawValue: 4242), "无主的标题")

        #expect(model.banner?.message == "内容不存在或已被删除")
    }
}
