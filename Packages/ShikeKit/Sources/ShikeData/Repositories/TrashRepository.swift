// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// 回收站仓储：软删除便签与待办的恢复、永久删除、清空与观察。
/// 恢复与永久删除组合既有仓储的对应方法——同一 SQL 语义与 notFound
/// 约定，避免两处实现漂移；清空回收站是唯一的新写路径：单个事务里硬删除
/// 两个表的已删行，便签的桌面卡片沿用外键 CASCADE（与
/// NoteRepository.permanentlyDelete 的级联语义一致）。
public struct TrashRepository: Sendable {
    private let database: AppDatabase
    private let noteRepository: NoteRepository
    private let todoRepository: TodoRepository

    public init(database: AppDatabase) {
        self.database = database
        self.noteRepository = NoteRepository(database: database)
        self.todoRepository = TodoRepository(database: database)
    }

    /// 恢复便签：deletedAt 置空。行不存在抛 notFound；已恢复的是"目标状态
    /// 已达成"，不报错（与 NoteRepository.restore 一致）。
    public func restoreNote(_ id: Note.ID) async throws {
        try await noteRepository.restore(id)
    }

    /// 恢复待办：deletedAt 置空。行不存在抛 notFound；已恢复的不报错
    /// （与 TodoRepository.restore 一致）。
    public func restoreTodo(_ id: Todo.ID) async throws {
        try await todoRepository.restore(id)
    }

    /// 永久删除便签：删除该行，桌面卡片级联删除（外键 CASCADE）。
    public func permanentlyDeleteNote(_ id: Note.ID) async throws {
        try await noteRepository.permanentlyDelete(id)
    }

    /// 永久删除待办：删除该行。
    public func permanentlyDeleteTodo(_ id: Todo.ID) async throws {
        try await todoRepository.permanentlyDelete(id)
    }

    /// 清空回收站：单个事务里硬删除所有已软删除的便签与待办。回收站已空
    /// 时是无害的 no-op；桌面卡片随外键 CASCADE 一并删除。
    public func emptyTrash() async throws {
        try await database.performWrite { database in
            try database.execute(sql: "DELETE FROM note WHERE deletedAt IS NOT NULL")
            try database.execute(sql: "DELETE FROM todo WHERE deletedAt IS NOT NULL")
        }
    }

    /// 观察回收站中的便签：按 deletedAt 降序（最新删除在前）、id 降序。
    public func observeNotes() -> AsyncThrowingStream<[Note], any Error> {
        noteRepository.observeDeleted()
    }

    /// 观察回收站中的待办：按 deletedAt 降序（最新删除在前）、id 降序。
    public func observeTodos() -> AsyncThrowingStream<[Todo], any Error> {
        todoRepository.observeDeleted()
    }
}
