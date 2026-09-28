// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// 桌面卡片仓储（data-layer.md「仓储」「观察」）。
/// 卡片以所属便签为键：钉出、更新、取消钉住都以 Note.ID 定位。
public struct StickyCardRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    /// 钉出便签：新建卡片，createdAt = updatedAt = 当前时间。
    /// 便签已钉时返回现有卡片，不做任何改动；便签不存在或已软删除时抛 notFound。
    public func pin(
        _ noteID: Note.ID,
        frame: CardFrame,
        options: StickyCardOptions
    ) async throws -> StickyCard {
        try await database.performWrite { database in
            // 便签必须存在且未删除
            let noteExists = try Bool.fetchOne(
                database,
                sql: "SELECT 1 FROM note WHERE id = ? AND deletedAt IS NULL",
                arguments: [noteID.rawValue]
            ) ?? false
            guard noteExists else {
                throw ShikeDataError.notFound
            }

            // 已钉出：返回现有卡片，不做任何改动
            if let existing = try StickyCardRecord
                .filter(Column("noteId") == noteID.rawValue)
                .fetchOne(database)
            {
                return existing.card
            }

            let now = try database.transactionDate
            var record = StickyCardRecord(from: StickyCard(
                noteID: noteID,
                frame: frame,
                options: options,
                createdAt: now,
                updatedAt: now
            ))
            try record.insert(database)
            return record.card
        }
    }

    /// 更新卡片位置。卡片的 updatedAt 更新；卡片不存在时抛 notFound。
    public func updateFrame(_ noteID: Note.ID, frame: CardFrame) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: "UPDATE stickyCard SET x = ?, y = ?, width = ?, height = ?, updatedAt = ? WHERE noteId = ?",
                arguments: [frame.x, frame.y, frame.width, frame.height, now, noteID.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 更新卡片选项。卡片的 updatedAt 更新；卡片不存在时抛 notFound。
    public func updateOptions(_ noteID: Note.ID, options: StickyCardOptions) async throws {
        try await database.performWrite { database in
            let now = try database.transactionDate
            try database.execute(
                sql: """
                UPDATE stickyCard SET level = ?, color = ?, fontSize = ?, autoHide = ?,
                    hideDelay = ?, hiddenOpacity = ?, allSpaces = ?, showOverFullScreen = ?,
                    updatedAt = ?
                WHERE noteId = ?
                """,
                arguments: [
                    options.level.rawValue,
                    options.color.rawValue,
                    options.fontSize.rawValue,
                    options.autoHide,
                    options.hideDelay,
                    options.hiddenOpacity,
                    options.allSpaces,
                    options.showOverFullScreen,
                    now,
                    noteID.rawValue,
                ]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 取消钉住：删除卡片行，便签不变。卡片不存在时抛 notFound。
    public func unpin(_ noteID: Note.ID) async throws {
        try await database.performWrite { database in
            try database.execute(
                sql: "DELETE FROM stickyCard WHERE noteId = ?",
                arguments: [noteID.rawValue]
            )
            if database.changesCount == 0 {
                throw ShikeDataError.notFound
            }
        }
    }

    /// 观察可见卡片：所属便签未删除的卡片，每项附带该便签，
    /// 按卡片 createdAt 升序、id 升序。
    public func observeVisible() -> AsyncThrowingStream<[VisibleCard], any Error> {
        observationStream(reader: database.writer) { database in
            let cards = try StickyCardRecord.fetchAll(database, sql: """
                SELECT stickyCard.* FROM stickyCard
                JOIN note ON note.id = stickyCard.noteId
                WHERE note.deletedAt IS NULL
                ORDER BY stickyCard.createdAt ASC, stickyCard.id ASC
                """)
            let notes = try NoteRecord.fetchAll(database, sql: """
                SELECT * FROM note WHERE deletedAt IS NULL
                """)
            let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id!, $0) })
            return cards.compactMap { cardRecord in
                guard let noteRecord = notesByID[cardRecord.noteId] else { return nil }
                return VisibleCard(card: cardRecord.card, note: noteRecord.note)
            }
        }
    }
}
