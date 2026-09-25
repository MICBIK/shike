// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 待办（data-layer.md「公开类型」）。全是值类型；与数据库的编解码由内部
/// Record 类型负责，公开 API 不出现 GRDB 类型。
public struct Todo: Sendable, Equatable, Identifiable {
    /// 本地自增主键的类型化包装，避免与其他表的 ID 混用。
    public struct ID: Hashable, Sendable {
        public let rawValue: Int64

        public init(rawValue: Int64) {
            self.rawValue = rawValue
        }
    }

    public let id: ID
    public let uuid: UUID
    public var title: String
    /// 对应 dueAt + dueHasTime；nil 表示没有时间。
    public var due: TodoDue?
    public var snoozedUntil: Date?
    /// 非空即已完成。
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    /// 非空即在"最近删除"中。
    public var deletedAt: Date?
}

/// 待办时间：具体时刻，或全天（date 为当天 00:00，按 Options.timeZone 规范化）。
public struct TodoDue: Sendable, Equatable {
    public var date: Date
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}
