// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// stickyCard 表的内部记录类型（data-layer.md「结构细节」）。
/// 卡片以所属便签为键：noteId 唯一。
struct StickyCardRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    static let databaseTableName = "stickyCard"

    // 关联：noteId → note.id（级联删除由外键保证）
    // 外键列按 GRDB 约定从目标表名推断：noteId
    static let note = belongsTo(NoteRecord.self)

    var id: Int64?
    var noteId: Int64
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var level: String
    var color: String
    var fontSize: String
    var autoHide: Bool
    var hideDelay: Double
    var hiddenOpacity: Double
    var allSpaces: Bool
    var showOverFullScreen: Bool
    var createdAt: Date
    var updatedAt: Date

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// 转换为公开模型。
    var card: StickyCard {
        precondition(id != nil, "stickyCard 行缺少 id：Record 未经过 insert 或 fetch")
        return StickyCard(
            noteID: Note.ID(rawValue: noteId),
            frame: CardFrame(x: x, y: y, width: width, height: height),
            options: StickyCardOptions(
                level: CardLevel(rawValue: level) ?? .normal,
                color: CardColor(rawValue: color) ?? .yellow,
                fontSize: CardFontSize(rawValue: fontSize) ?? .medium,
                autoHide: autoHide,
                hideDelay: hideDelay,
                hiddenOpacity: hiddenOpacity,
                allSpaces: allSpaces,
                showOverFullScreen: showOverFullScreen
            ),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// 从公开模型构造（不含 id，用于插入）。
    init(from card: StickyCard) {
        self.id = nil
        self.noteId = card.noteID.rawValue
        self.x = card.frame.x
        self.y = card.frame.y
        self.width = card.frame.width
        self.height = card.frame.height
        self.level = card.options.level.rawValue
        self.color = card.options.color.rawValue
        self.fontSize = card.options.fontSize.rawValue
        self.autoHide = card.options.autoHide
        self.hideDelay = card.options.hideDelay
        self.hiddenOpacity = card.options.hiddenOpacity
        self.allSpaces = card.options.allSpaces
        self.showOverFullScreen = card.options.showOverFullScreen
        self.createdAt = card.createdAt
        self.updatedAt = card.updatedAt
    }
}
