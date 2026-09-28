// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

// 锁定公开 API 形状（parser.md「公开 API」），故意不用 @testable：
// 若成员意外失去 public，这里应当编译失败。
import ShikeDateParser

/// 契约形状测试：DateParseResult 是纯值类型，可比较、持有区间（parser.md）。
/// 识别行为的全量测试随 Story 1.15/1.16 加入。
struct DateParseResultTests {
    @Test("相等性按契约逐字段比较")
    func equalityComparesAllFields() {
        let date = Date(timeIntervalSince1970: 1_789_999_999)
        let a = DateParseResult(date: date, hasTime: true, matchedRanges: [NSRange(location: 0, length: 4)])
        let b = DateParseResult(date: date, hasTime: true, matchedRanges: [NSRange(location: 0, length: 4)])
        let differentTime = DateParseResult(date: date, hasTime: false, matchedRanges: [NSRange(location: 0, length: 4)])
        let differentRanges = DateParseResult(date: date, hasTime: true, matchedRanges: [])

        #expect(a == b)
        #expect(a != differentTime)
        #expect(a != differentRanges)
    }

    @Test("构造后各字段原样可读；区间排序由解析器保证，类型不重排")
    func fieldsRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let ranges = [NSRange(location: 2, length: 3), NSRange(location: 8, length: 1)]
        let result = DateParseResult(date: date, hasTime: false, matchedRanges: ranges)

        #expect(result.date == date)
        #expect(result.hasTime == false)
        #expect(result.matchedRanges == ranges)
    }
}
