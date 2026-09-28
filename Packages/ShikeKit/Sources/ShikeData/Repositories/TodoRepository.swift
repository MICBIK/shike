// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// 待办仓储（data-layer.md「仓储」「观察」）。
/// 写语义与便签仓储一致（共用 performWrite）；全天待办的 dueAt 按
/// Options.timeZone 规范化为当天 00:00。
public struct TodoRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// 新建待办：新 uuid；createdAt = updatedAt = 当前时间。
    /// hasTime 为否时 dueAt 存为 timeZone 中该日的 00:00；为是时原样保存。
    public func create(title: String, due: TodoDue?) async throws -> Todo {
        try await database.performWrite { database in
            let now = try database.transactionDate
            var record = TodoRecord(
                id: nil,
                uuid: UUID(),
                title: title,
                dueAt: Self.normalizedDueAt(due, timeZone: self.database.options.timeZone),
                dueHasTime: due?.hasTime ?? false,
                snoozedUntil: nil,
                completedAt: nil,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            try record.insert(database)
            return record.todo
        }
    }

    /// 修改标题。更新 updatedAt。
    public func updateTitle(_ id: Todo.ID, to title: String) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE todo SET title = ?, updatedAt = ? WHERE id = ?",
                arguments: [title, now, id.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 设置时间（传 nil 清除）。snoozedUntil 清空。更新 updatedAt。
    public func setDue(_ id: Todo.ID, _ due: TodoDue?) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE todo SET dueAt = ?, dueHasTime = ?, snoozedUntil = NULL, updatedAt = ? WHERE id = ?",
                arguments: [
                    Self.normalizedDueAt(due, timeZone: self.database.options.timeZone),
                    due?.hasTime ?? false,
                    now,
                    id.rawValue,
                ]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 完成或取消完成：完成时 completedAt = 当前时间、snoozedUntil 清空；
    /// 取消时 completedAt = nil。已是目标状态时不改动。更新 updatedAt（状态变化时）。
    public func setCompleted(_ id: Todo.ID, _ completed: Bool) async throws {
        try await database.performWrite { database in
            if completed {
                let now = try database.transactionDate
                try database.execute(
                    sql: "UPDATE todo SET completedAt = ?, snoozedUntil = NULL WHERE id = ? AND completedAt IS NULL",
                    arguments: [now, id.rawValue]
                )
            } else {
                try database.execute(
                    sql: "UPDATE todo SET completedAt = NULL WHERE id = ? AND completedAt IS NOT NULL",
                    arguments: [id.rawValue]
                )
            }
            if database.changesCount == 0,
                try !AppDatabase.exists("todo", id: id.rawValue, in: database)
            {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 稍后提醒：snoozedUntil 存为传入的时间。更新 updatedAt。
    public func snooze(_ id: Todo.ID, until date: Date) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE todo SET snoozedUntil = ?, updatedAt = ? WHERE id = ?",
                arguments: [date, now, id.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 软删除：deletedAt 设为当前时间；已删除的保留原来的 deletedAt。不更新 updatedAt。
    public func softDelete(_ id: Todo.ID) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE todo SET deletedAt = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [now, id.rawValue]
            )
            if database.changesCount == 0,
                try !AppDatabase.exists("todo", id: id.rawValue, in: database)
            {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 恢复：deletedAt 设为 nil。不更新 updatedAt。
    public func restore(_ id: Todo.ID) async throws {
        try await database.performWrite { database in
            try database.execute(
                sql: "UPDATE todo SET deletedAt = NULL WHERE id = ? AND deletedAt IS NOT NULL",
                arguments: [id.rawValue]
            )
            if database.changesCount == 0,
                try !AppDatabase.exists("todo", id: id.rawValue, in: database)
            {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 永久删除：删除该行。
    public func permanentlyDelete(_ id: Todo.ID) async throws {
        try await database.performWrite { database in
            try database.execute(
                sql: "DELETE FROM todo WHERE id = ?",
                arguments: [id.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 观察未删除的待办（包括已完成的）：按 createdAt 降序、id 降序。
    public func observeActive() -> AsyncThrowingStream<[Todo], any Error> {
        observationStream(reader: database.writer) { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT * FROM todo
                WHERE deletedAt IS NULL
                ORDER BY createdAt DESC, id DESC
                """)
            return try rows.map { row in
                try TodoRecord(row: row).todo
            }
        }
    }

    /// 全天规范化：hasTime 为否时存该日 00:00；为是时原样保存。
    static func normalizedDueAt(_ due: TodoDue?, timeZone: TimeZone) -> Date? {
        guard let due else { return nil }
        guard !due.hasTime else { return due.date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: due.date)
        return calendar.date(from: components)
    }
}
