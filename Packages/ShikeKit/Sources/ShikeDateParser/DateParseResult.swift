// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 解析结果：识别到的时刻，以及它在原文中的区间。
///
/// 契约见 parser.md「公开 API」；行为（识别规则）由 Story 1.15/1.16 实现。
public struct DateParseResult: Sendable, Equatable {
    /// 识别到的时刻；全天时为该日 00:00（按解析器的时区）。
    public let date: Date

    /// 05 §2：原文是否包含时刻。
    public let hasTime: Bool

    /// 被识别片段的 UTF-16 区间。解析器（Story 1.15）产出的区间按位置排序、互不重叠；
    /// 本类型是被动持有者，不在构造时排序或校验。
    public let matchedRanges: [NSRange]

    public init(date: Date, hasTime: Bool, matchedRanges: [NSRange]) {
        self.date = date
        self.hasTime = hasTime
        self.matchedRanges = matchedRanges
    }
}
