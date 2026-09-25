// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 便签（data-layer.md「公开类型」）。全是值类型；与数据库的编解码由内部
/// Record 类型负责，公开 API 不出现 GRDB 类型。
public struct Note: Sendable, Equatable, Identifiable {
    /// 本地自增主键的类型化包装，避免与其他表的 ID 混用。
    public struct ID: Hashable, Sendable {
        public let rawValue: Int64

        public init(rawValue: Int64) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let uuid: UUID
    public var content: String
    /// 非空即置顶。
    public var pinnedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    /// 非空即在"最近删除"中。
    public var deletedAt: Date?
}

/// 观察流中的列表项：便签本体，附带"是否已钉到桌面"。
public struct NoteListItem: Sendable, Equatable, Identifiable {
    public let note: Note
    public let isPinnedToDesktop: Bool

    public var id: Note.ID { note.id }
}
