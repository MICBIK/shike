// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// PRAGMA table_info 行的形状；Equatable 以便逐列断言。
private struct ColumnSpec: Equatable {
    let name: String
    let type: String
    let notNull: Int
    let defaultValue: String?

    init(name: String, type: String, notNull: Int, defaultValue: String?) {
        self.name = name
        self.type = type
        self.notNull = notNull
        self.defaultValue = defaultValue
    }

    init(_ row: Row) {
        self.init(
            name: row["name"] as String,
            type: row["type"] as String,
            notNull: row["notNull"] as Int,
            defaultValue: row["dflt_value"] as String?
        )
    }
}

/// Story 1.3：刚迁移完的空库，结构与 04 §5 和 data-layer.md 逐项一致。
struct SchemaTests {
    private let database: AppDatabase

    init() throws {
        database = try AppDatabase.inMemory()
    }

    @Test("note 表的列、类型、可空性与默认值与契约一致")
    func noteColumns() throws {
        let rows = try database.writer.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(note)")
        }
        let columns = rows.map(ColumnSpec.init)
        #expect(columns == [
            ColumnSpec(name: "id", type: "INTEGER", notNull: 0, defaultValue: nil),
            ColumnSpec(name: "uuid", type: "TEXT", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "content", type: "TEXT", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "pinnedAt", type: "DATETIME", notNull: 0, defaultValue: nil),
            ColumnSpec(name: "createdAt", type: "DATETIME", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "updatedAt", type: "DATETIME", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "deletedAt", type: "DATETIME", notNull: 0, defaultValue: nil),
        ])
    }

    @Test("todo 表的列、类型、可空性与默认值与契约一致")
    func todoColumns() throws {
        let rows = try database.writer.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(todo)")
        }
        let columns = rows.map(ColumnSpec.init)
        #expect(columns == [
            ColumnSpec(name: "id", type: "INTEGER", notNull: 0, defaultValue: nil),
            ColumnSpec(name: "uuid", type: "TEXT", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "title", type: "TEXT", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "dueAt", type: "DATETIME", notNull: 0, defaultValue: nil),
            ColumnSpec(name: "dueHasTime", type: "BOOLEAN", notNull: 1, defaultValue: "0"),
            ColumnSpec(name: "snoozedUntil", type: "DATETIME", notNull: 0, defaultValue: nil),
            ColumnSpec(name: "completedAt", type: "DATETIME", notNull: 0, defaultValue: nil),
            ColumnSpec(name: "createdAt", type: "DATETIME", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "updatedAt", type: "DATETIME", notNull: 1, defaultValue: nil),
            ColumnSpec(name: "deletedAt", type: "DATETIME", notNull: 0, defaultValue: nil),
        ])
    }

    @Test("stickyCard 表的列、类型、可空性与契约一致")
    func stickyCardColumns() throws {
        let rows = try database.writer.read { database in
            try Row.fetchAll(database, sql: "PRAGMA table_info(stickyCard)")
        }
        let stickyCardColumns = rows.map(ColumnSpec.init)
        #expect(stickyCardColumns.map(\ .name) == [
            "id", "noteId", "x", "y", "width", "height", "level", "color", "fontSize",
            "autoHide", "hideDelay", "hiddenOpacity", "allSpaces", "showOverFullScreen",
            "createdAt", "updatedAt",
        ])
        #expect(stickyCardColumns.map(\.type) == [
            "INTEGER", "INTEGER", "REAL", "REAL", "REAL", "REAL", "TEXT", "TEXT", "TEXT",
            "BOOLEAN", "REAL", "REAL", "BOOLEAN", "BOOLEAN",
            "DATETIME", "DATETIME",
        ])
        // id 是 rowid 别名（AUTOINCREMENT），PRAGMA 中 notNull 报 0
        #expect(stickyCardColumns.filter { $0.name != "id" }.allSatisfy { $0.notNull == 1 })
    }

    @Test("索引与外键按契约建立")
    func indexesAndForeignKeys() throws {
        try database.writer.read { database in
            let noteIndexes = try Row.fetchAll(database, sql: "PRAGMA index_list(note)")
                .compactMap { $0["name"] as? String }
            #expect(noteIndexes.contains("note_on_deletedAt"))

            let todoIndexes = try Row.fetchAll(database, sql: "PRAGMA index_list(todo)")
                .compactMap { $0["name"] as? String }
            #expect(todoIndexes.contains("todo_on_deletedAt"))
            #expect(todoIndexes.contains("todo_on_completedAt_dueAt"))

            func indexColumns(_ index: String) throws -> [String] {
                try Row.fetchAll(database, sql: "PRAGMA index_info(\(index))")
                    .sorted { ($0["seqno"] as Int) < ($1["seqno"] as Int) }
                    .compactMap { $0["name"] as? String }
            }
            #expect(try indexColumns("note_on_deletedAt") == ["deletedAt"])
            #expect(try indexColumns("todo_on_deletedAt") == ["deletedAt"])
            #expect(try indexColumns("todo_on_completedAt_dueAt") == ["completedAt", "dueAt"])

            let foreignKeys = try Row.fetchAll(database, sql: "PRAGMA foreign_key_list(stickyCard)")
            #expect(foreignKeys.count == 1)
            let foreignKey = foreignKeys[0]
            #expect(foreignKey["table"] as? String == "note")
            #expect(foreignKey["from"] as? String == "noteId")
            #expect(foreignKey["to"] as? String == "id")
            #expect(foreignKey["on_delete"] as? String == "CASCADE")
        }
    }

    @Test("dueHasTime = 1 而 dueAt 为空的待办被 CHECK 拒绝")
    func dueConstraintRejectsInconsistentRow() throws {
        do {
            try database.writer.write { database in
                try database.execute(sql: """
                    INSERT INTO todo (uuid, title, dueHasTime, dueAt, createdAt, updatedAt)
                    VALUES ('b', 't', 1, NULL, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                    """)
            }
            Issue.record("违反 due 约束的行被接受了")
        } catch {
            #expect(mapFailure(error) == .constraintViolation)
        }
    }

    @Test("全天待办与带时刻待办都能成功插入（CHECK 不拦合法行）")
    func dueConstraintAcceptsValidRows() throws {
        try database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO todo (uuid, title, dueHasTime, dueAt, createdAt, updatedAt)
                VALUES ('all-day', '全天', 0, NULL, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
            try database.execute(sql: """
                INSERT INTO todo (uuid, title, dueHasTime, dueAt, createdAt, updatedAt)
                VALUES ('timed', '带时刻', 1, '2026-01-02 09:30:00.000', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
        }
    }

    @Test("同一张便签的第二张卡片被 noteId 唯一约束拒绝")
    func secondCardForSameNoteIsRejected() throws {
        try database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO note (uuid, content, createdAt, updatedAt)
                VALUES ('0b8df3a0-4a1e-4d3e-9f60-000000000001', '', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
            try database.execute(sql: """
                INSERT INTO stickyCard (
                    noteId, x, y, width, height, level, color, fontSize,
                    autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen,
                    createdAt, updatedAt
                ) VALUES (
                    (SELECT id FROM note WHERE uuid = '0b8df3a0-4a1e-4d3e-9f60-000000000001'),
                    0, 0, 100, 100, 'normal', 'yellow', 'medium',
                    0, 0, 0, 0, 0, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
            do {
                try database.execute(sql: """
                    INSERT INTO stickyCard (
                        noteId, x, y, width, height, level, color, fontSize,
                        autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen,
                        createdAt, updatedAt
                    ) VALUES (
                        (SELECT id FROM note WHERE uuid = '0b8df3a0-4a1e-4d3e-9f60-000000000001'),
                        1, 1, 100, 100, 'normal', 'yellow', 'medium',
                        0, 0, 0, 0, 0, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                    """)
                Issue.record("同一便签的第二张卡片被接受了")
            } catch {
                #expect(mapFailure(error) == .constraintViolation)
            }
        }
    }
}
