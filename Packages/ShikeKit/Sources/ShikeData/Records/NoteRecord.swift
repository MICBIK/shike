// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// note 表的内部记录类型：负责与数据库之间的编解码（data-layer.md「结构细节」）。
/// 公开模型 Note 与本类型互转；公开 API 不暴露本类型。
struct NoteRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "note"

    var id: Int64?
    var uuid: UUID
    var content: String
    var pinnedAt: Date?
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

    /// 转换为公开模型。id 缺失即程序缺陷（insert/fetch 之后必有），不静默兜底。
    var note: Note {
        precondition(id != nil, "note 行缺少 id：Record 未经过 insert 或 fetch")
        return Note(
            id: Note.ID(rawValue: id!),
            uuid: uuid,
            content: content,
            pinnedAt: pinnedAt,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}
