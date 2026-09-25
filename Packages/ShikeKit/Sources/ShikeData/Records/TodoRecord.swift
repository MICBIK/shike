// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// todo 表的内部记录类型：负责与数据库之间的编解码（data-layer.md「结构细节」）。
struct TodoRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "todo"

    var id: Int64?
    var uuid: UUID
    var title: String
    var dueAt: Date?
    var dueHasTime: Bool
    var snoozedUntil: Date?
    var completedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var deletedAt: Date?

    /// uuid 必须以 36 位小写文本存储。必须是静态函数：写成静态属性会被 GRDB
    /// 静默忽略，uuid 变成 16 字节 BLOB（ADR-006 的旧缺陷，已有测试守护）。
    static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy {
        .lowercaseString
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// 转换为公开模型（dueAt + dueHasTime 合成为 TodoDue）。
    var todo: Todo {
        precondition(id != nil, "todo 行缺少 id：Record 未经过 insert 或 fetch")
        let due: TodoDue?
        if let dueAt {
            due = TodoDue(date: dueAt, hasTime: dueHasTime)
        } else {
            due = nil
        }
        return Todo(
            id: Todo.ID(rawValue: id!),
            uuid: uuid,
            title: title,
            due: due,
            snoozedUntil: snoozedUntil,
            completedAt: completedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
