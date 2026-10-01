// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// 回收站仓储：软删除观察流的排序与推送、恢复后消失、永久删除的隔离与
/// 级联、清空回收站的边界、notFound 契约。写语义复用既有仓储方法，这里
/// 验证组合后的对外行为。
struct TrashRepositoryTests {
    /// 订阅观察流只取首帧：流急切启动且先推当前值，写入后新建流即可拿到
    /// 快照；提前返回会经 onTermination 取消底层观察任务。
    private func firstFrame<Value: Sendable & Equatable>(
        of stream: AsyncThrowingStream<[Value], any Error>
    ) async throws -> [Value] {
        for try await frame in stream {
            return frame
        }
        // data-layer.md「观察」：先推当前值后再正常结束不应发生（正常结束已统一
        // 转 readFailed 抛错）——真走到这里说明契约回归，空回收站是伪装，必须响。
        Issue.record("观察流未先推值即正常结束")
        return []
    }

    // - MARK: 观察流

    @Test("observeNotes：软删除两条，首帧按 deletedAt 降序（最新删除在前），未删除的不出现")
    func observeDeletedNotesSortedByDeletedAtDescending() async throws {
        // 步进时钟：三次新建与两次软删除各落在不同时刻，deletedAt 可比较
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let trash = TrashRepository(database: database)
        let notes = NoteRepository(database: database)

        let first = try await notes.create(content: "先删的")
        let second = try await notes.create(content: "后删的")
        _ = try await notes.create(content: "留在原处的")
        try await notes.softDelete(first.id)
        try await notes.softDelete(second.id)

        let deleted = try await firstFrame(of: trash.observeNotes())

        #expect(deleted.map(\.id) == [second.id, first.id])
        #expect(deleted.allSatisfy { $0.deletedAt != nil })
        #expect(deleted[0].deletedAt! > deleted[1].deletedAt!)
    }

    @Test("observeTodos：软删除两条，首帧按 deletedAt 降序（最新删除在前），未删除的不出现")
    func observeDeletedTodosSortedByDeletedAtDescending() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let trash = TrashRepository(database: database)
        let todos = TodoRepository(database: database)

        let first = try await todos.create(title: "先删的", due: nil)
        let second = try await todos.create(title: "后删的", due: nil)
        _ = try await todos.create(title: "留在原处的", due: nil)
        try await todos.softDelete(first.id)
        try await todos.softDelete(second.id)

        let deleted = try await firstFrame(of: trash.observeTodos())

        #expect(deleted.map(\.id) == [second.id, first.id])
        #expect(deleted.allSatisfy { $0.deletedAt != nil })
        #expect(deleted[0].deletedAt! > deleted[1].deletedAt!)
    }

    @Test("恢复后便签从观察流消失")
    func restoredNoteDisappearsFromObservation() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let trash = TrashRepository(database: database)
        let notes = NoteRepository(database: database)

        let first = try await notes.create(content: "第一张")
        let second = try await notes.create(content: "第二张")
        try await notes.softDelete(first.id)
        try await notes.softDelete(second.id)

        let received = ReceiveBox<Note>()
        let task = Task {
            for try await items in trash.observeNotes() {
                received.append(items)
            }
        }
        defer { task.cancel() }

        let sawInitial = await waitFor(received.count >= 1)
        #expect(sawInitial)
        #expect(received.snapshot.first?.map(\.id) == [second.id, first.id])

        try await trash.restoreNote(second.id)
        let sawRestore = await waitFor(received.snapshot.last?.map(\.id) == [first.id])
        #expect(sawRestore)
    }

    @Test("恢复后待办从观察流消失")
    func restoredTodoDisappearsFromObservation() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let trash = TrashRepository(database: database)
        let todos = TodoRepository(database: database)

        let first = try await todos.create(title: "第一件", due: nil)
        let second = try await todos.create(title: "第二件", due: nil)
        try await todos.softDelete(first.id)
        try await todos.softDelete(second.id)

        let received = ReceiveBox<Todo>()
        let task = Task {
            for try await items in trash.observeTodos() {
                received.append(items)
            }
        }
        defer { task.cancel() }

        let sawInitial = await waitFor(received.count >= 1)
        #expect(sawInitial)
        #expect(received.snapshot.first?.map(\.id) == [second.id, first.id])

        try await trash.restoreTodo(second.id)
        let sawRestore = await waitFor(received.snapshot.last?.map(\.id) == [first.id])
        #expect(sawRestore)
    }

    @Test("观察流活推送：订阅后新软删除的便签/待办推进各自流（首帧为空）")
    func newSoftDeletesAppearInLiveStreams() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let trash = TrashRepository(database: database)
        let notes = NoteRepository(database: database)
        let todos = TodoRepository(database: database)

        let receivedNotes = ReceiveBox<Note>()
        let receivedTodos = ReceiveBox<Todo>()
        let noteTask = Task {
            for try await items in trash.observeNotes() {
                receivedNotes.append(items)
            }
        }
        let todoTask = Task {
            for try await items in trash.observeTodos() {
                receivedTodos.append(items)
            }
        }
        defer {
            noteTask.cancel()
            todoTask.cancel()
        }

        // 首帧：回收站初始为空
        let sawInitial = await waitFor(receivedNotes.count >= 1 && receivedTodos.count >= 1)
        #expect(sawInitial)
        #expect(receivedNotes.snapshot.first?.isEmpty == true)
        #expect(receivedTodos.snapshot.first?.isEmpty == true)

        // 订阅之后软删除：活推送进各自流
        let note = try await notes.create(content: "订阅后删除的便签")
        let todo = try await todos.create(title: "订阅后删除的待办", due: nil)
        try await notes.softDelete(note.id)
        try await todos.softDelete(todo.id)

        let sawNote = await waitFor(receivedNotes.snapshot.last?.map(\.id) == [note.id])
        let sawTodo = await waitFor(receivedTodos.snapshot.last?.map(\.id) == [todo.id])
        #expect(sawNote)
        #expect(sawTodo)
    }

    @Test("已恢复的便签/待办再次恢复不报错（目标状态已达成），回收站保持为空")
    func restoringAlreadyRestoredItemsIsNoop() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let trash = TrashRepository(database: database)
        let notes = NoteRepository(database: database)
        let todos = TodoRepository(database: database)

        let note = try await notes.create(content: "恢复两次的便签")
        let todo = try await todos.create(title: "恢复两次的待办", due: nil)
        try await notes.softDelete(note.id)
        try await todos.softDelete(todo.id)

        // 第二次恢复对已恢复的行是"目标状态已达成"：不抛 notFound（与仓储文档一致）
        try await trash.restoreNote(note.id)
        try await trash.restoreNote(note.id)
        try await trash.restoreTodo(todo.id)
        try await trash.restoreTodo(todo.id)

        let noteFrame = try await firstFrame(of: trash.observeNotes())
        let todoFrame = try await firstFrame(of: trash.observeTodos())
        #expect(noteFrame.isEmpty)
        #expect(todoFrame.isEmpty)
    }

    // - MARK: 永久删除

    @Test("permanentlyDeleteNote：该行与卡片级联消失，另一条仍在回收站")
    func permanentDeleteNoteRemovesRowCascadesCardKeepsOther() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let trash = TrashRepository(database: database)
        let notes = NoteRepository(database: database)

        let first = try await notes.create(content: "被永久删除的")
        let second = try await notes.create(content: "留下的")
        try await notes.softDelete(first.id)
        try await notes.softDelete(second.id)
        // 已删便签上的桌面卡片：随外键 CASCADE 消失
        try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO stickyCard (noteId, x, y, width, height, level, color, fontSize,
                    autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen, createdAt, updatedAt)
                VALUES (?, 0, 0, 100, 100, 'normal', 'yellow', 'medium', 0, 0, 0, 0, 0,
                    '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """, arguments: [first.id.rawValue])
        }

        try await trash.permanentlyDeleteNote(first.id)

        let counts = try await database.writer.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM stickyCard") ?? -1
            )
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 0)

        let remaining = try await firstFrame(of: trash.observeNotes())
        #expect(remaining.map(\.id) == [second.id])
    }

    @Test("permanentlyDeleteTodo：该行消失，另一条仍在回收站")
    func permanentDeleteTodoRemovesRowKeepsOther() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let trash = TrashRepository(database: database)
        let todos = TodoRepository(database: database)

        let first = try await todos.create(title: "被永久删除的", due: nil)
        let second = try await todos.create(title: "留下的", due: nil)
        try await todos.softDelete(first.id)
        try await todos.softDelete(second.id)

        try await trash.permanentlyDeleteTodo(first.id)

        let count = try await database.writer.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM todo")
        }
        #expect(count == 1)

        let remaining = try await firstFrame(of: trash.observeTodos())
        #expect(remaining.map(\.id) == [second.id])
    }

    // - MARK: 清空回收站

    @Test("emptyTrash：两类已删行全部清空且卡片级联删除，未删除的行不受影响")
    func emptyTrashRemovesOnlySoftDeletedRows() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let trash = TrashRepository(database: database)
        let notes = NoteRepository(database: database)
        let todos = TodoRepository(database: database)

        let deletedNote1 = try await notes.create(content: "回收站便签一")
        let deletedNote2 = try await notes.create(content: "回收站便签二")
        let keptNote = try await notes.create(content: "未删除便签")
        let deletedTodo1 = try await todos.create(title: "回收站待办一", due: nil)
        let deletedTodo2 = try await todos.create(title: "回收站待办二", due: nil)
        let keptTodo = try await todos.create(title: "未删除待办", due: nil)
        try await notes.softDelete(deletedNote1.id)
        try await notes.softDelete(deletedNote2.id)
        try await todos.softDelete(deletedTodo1.id)
        try await todos.softDelete(deletedTodo2.id)
        // 已删便签上的桌面卡片：清空回收站时随外键 CASCADE 一并删除
        try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO stickyCard (noteId, x, y, width, height, level, color, fontSize,
                    autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen, createdAt, updatedAt)
                VALUES (?, 0, 0, 100, 100, 'normal', 'yellow', 'medium', 0, 0, 0, 0, 0,
                    '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """, arguments: [deletedNote1.id.rawValue])
        }

        try await trash.emptyTrash()

        let counts = try await database.writer.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM todo") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM stickyCard") ?? -1
            )
        }
        #expect(counts.0 == 1)
        #expect(counts.1 == 1)
        #expect(counts.2 == 0)

        let noteFrame = try await firstFrame(of: trash.observeNotes())
        let todoFrame = try await firstFrame(of: trash.observeTodos())
        #expect(noteFrame.isEmpty)
        #expect(todoFrame.isEmpty)

        // 未删除的行原样保留（内容未被动过，deletedAt 仍为空）
        let kept = try await database.writer.read { database in
            (
                try NoteRecord.fetchOne(database, key: keptNote.id.rawValue)?.note,
                try TodoRecord.fetchOne(database, key: keptTodo.id.rawValue)?.todo
            )
        }
        #expect(kept.0?.content == "未删除便签")
        #expect(kept.0?.deletedAt == nil)
        #expect(kept.1?.title == "未删除待办")
        #expect(kept.1?.deletedAt == nil)
    }

    // - MARK: 错误契约

    @Test("restore/permanentlyDelete 不存在的 id 抛 notFound；空回收站清空是无害的 no-op")
    func missingIDsThrowNotFoundAndEmptyTrashOnEmptyIsNoop() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let trash = TrashRepository(database: database)
        let ghostNote = Note.ID(rawValue: 9999)
        let ghostTodo = Todo.ID(rawValue: 9999)

        await #expect(throws: ShikeDataError.notFound) { try await trash.restoreNote(ghostNote) }
        await #expect(throws: ShikeDataError.notFound) { try await trash.restoreTodo(ghostTodo) }
        await #expect(throws: ShikeDataError.notFound) { try await trash.permanentlyDeleteNote(ghostNote) }
        await #expect(throws: ShikeDataError.notFound) { try await trash.permanentlyDeleteTodo(ghostTodo) }

        // 空回收站清空：不报错
        try await trash.emptyTrash()
    }

    @Test("simulateWriteFailure：emptyTrash 走统一写路径，抛 writeFailed(.simulated)")
    func emptyTrashFollowsSimulatedFailurePath() async throws {
        let database = try AppDatabase.inMemory(options: .init(
            clock: { TestClock.t0 },
            simulateWriteFailure: true
        ))
        let trash = TrashRepository(database: database)
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await trash.emptyTrash() }
    }
}
