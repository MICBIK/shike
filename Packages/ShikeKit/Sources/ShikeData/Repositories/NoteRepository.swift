// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// 便签仓储（data-layer.md「仓储」「观察」）。
/// 写方法都是 async throws，只抛 ShikeDataError；时间戳经 transactionDate
/// 取自注入时钟；updatedAt 只随内容变化更新（ADR-017）。
public struct NoteRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// 新建便签：新 uuid；createdAt = updatedAt = 当前时间；内容可以为空。
    public func create(content: String) async throws -> Note {
        try await database.performWrite { database in
            let now = try database.transactionDate
            var record = NoteRecord(
                id: nil,
                uuid: UUID(),
                content: content,
                pinnedAt: nil,
                createdAt: now,
                updatedAt: now,
                deletedAt: nil
            )
            try record.insert(database)
            return record.note
        }
    }

    /// 修改内容；已软删除的便签也可以更新（避免自动保存与删除竞态报错）。
    /// 更新 updatedAt。
    public func updateContent(_ id: Note.ID, to content: String) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE note SET content = ?, updatedAt = ? WHERE id = ?",
                arguments: [content, now, id.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 置顶或取消置顶：pinnedAt 设为当前时间或 nil；已是目标状态时不改动。
    /// 不更新 updatedAt（ADR-017）。
    public func setPinned(_ id: Note.ID, _ pinned: Bool) async throws {
        try await database.performWrite { database in
            if pinned {
                let now = try database.transactionDate
                try database.execute(
                    sql: "UPDATE note SET pinnedAt = ? WHERE id = ? AND pinnedAt IS NULL",
                    arguments: [now, id.rawValue]
                )
            } else {
                try database.execute(
                    sql: "UPDATE note SET pinnedAt = NULL WHERE id = ? AND pinnedAt IS NOT NULL",
                    arguments: [id.rawValue]
                )
            }
            if database.changesCount == 0,
                try !AppDatabase.exists("note", id: id.rawValue, in: database)
            {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 软删除：deletedAt 设为当前时间；已删除的保留原来的 deletedAt。
    /// 不更新 updatedAt（ADR-017）。
    public func softDelete(_ id: Note.ID) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE note SET deletedAt = ? WHERE id = ? AND deletedAt IS NULL",
                arguments: [now, id.rawValue]
            )
            if database.changesCount == 0,
                try !AppDatabase.exists("note", id: id.rawValue, in: database)
            {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 恢复：deletedAt 设为 nil。不更新 updatedAt（ADR-017）。
    public func restore(_ id: Note.ID) async throws {
        try await database.performWrite { database in
            try database.execute(
                sql: "UPDATE note SET deletedAt = NULL WHERE id = ? AND deletedAt IS NOT NULL",
                arguments: [id.rawValue]
            )
            if database.changesCount == 0,
                try !AppDatabase.exists("note", id: id.rawValue, in: database)
            {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 永久删除：删除该行；便签的卡片级联删除（外键 CASCADE）。
    public func permanentlyDelete(_ id: Note.ID) async throws {
        try await database.performWrite { database in
            try database.execute(
                sql: "DELETE FROM note WHERE id = ?",
                arguments: [id.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 观察未删除的便签：按 updatedAt 降序、id 降序，附带 isPinnedToDesktop。
    /// 订阅后先推送当前值；读取失败时流以 readFailed(原因) 结束。
    public func observeActive() -> AsyncThrowingStream<[NoteListItem], any Error> {
        observationStream(reader: database.writer) { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT note.*, EXISTS(
                    SELECT 1 FROM stickyCard WHERE stickyCard.noteId = note.id
                ) AS isPinnedToDesktop
                FROM note
                WHERE note.deletedAt IS NULL
                ORDER BY note.updatedAt DESC, note.id DESC
                """)
            return try rows.map { row -> NoteListItem in
                let record = try NoteRecord(row: row)
                return NoteListItem(
                    note: record.note,
                    isPinnedToDesktop: row["isPinnedToDesktop"] as Bool
                )
            }
        }
    }
}
