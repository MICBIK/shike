// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 相对修改时间（S1-05，03 §5）：刚刚 / N 分钟前 / 今天 HH:mm / 昨天 / M月d日。
/// 纯函数：注入 date、now 与时区，不读系统当前时间（NFR17）；24 小时制（12 小时制是 S5-04）。
enum RelativeTimeFormatter {
    static func format(_ date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return String(localized: .timeJustNow) }
        if minutes < 60 { return String(localized: .timeMinutesAgo(minutes)) }

        if calendar.isDate(date, inSameDayAs: now) {
            let time = formatClock(date, calendar: calendar)
            return String(localized: .timeTodayAt(time))
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return String(localized: .timeYesterday)
        }
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        return String(localized: .timeDate(month, day))
    }

    private static func formatClock(_ date: Date, calendar: Calendar) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return String(format: "%02d:%02d", hour, minute)
    }
}
