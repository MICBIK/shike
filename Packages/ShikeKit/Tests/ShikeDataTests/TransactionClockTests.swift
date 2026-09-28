// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import ShikeData

/// Story 1.3：时间戳全部取自注入时钟（data-layer.md；conventions.md「测试」：不依赖真实时间）。
struct TransactionClockTests {
    /// 线程安全的递增时钟：每次调用返回一个比上一次更晚的时间。
    private final class TickingClock: @unchecked Sendable {
        private let lock = NSLock()
        private var base: Date

        init(base: Date) {
            self.base = base
        }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            base = base.addingTimeInterval(60)
            return base
        }
    }

    @Test("固定时钟：同一事务内的当前时间相同且等于注入值")
    func fixedClockGivesSameDateWithinTransaction() throws {
        let fixed = Date(timeIntervalSince1970: 1_789_999_999)
        let database = try AppDatabase.inMemory(options: .init(clock: { fixed }))

        try database.writer.write { database in
            let first = try database.transactionDate
            let second = try database.transactionDate
            #expect(first == second)
            #expect(first == fixed)
        }
    }

    @Test("递增时钟：同一写入内时间相同，两次独立写入时间不同")
    func tickingClockSeparatesWrites() throws {
        let clock = TickingClock(base: Date(timeIntervalSince1970: 1_789_999_999))
        let database = try AppDatabase.inMemory(options: .init(clock: { clock.now() }))

        var firstWriteDates: [Date] = []
        var secondWriteDates: [Date] = []

        try database.writer.write { database in
            firstWriteDates = [try database.transactionDate, try database.transactionDate]
        }
        try database.writer.write { database in
            secondWriteDates = [try database.transactionDate, try database.transactionDate]
        }

        #expect(firstWriteDates[0] == firstWriteDates[1])
        #expect(secondWriteDates[0] == secondWriteDates[1])
        #expect(firstWriteDates[0] < secondWriteDates[0])
    }
}
