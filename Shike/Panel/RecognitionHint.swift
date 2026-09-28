// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 待办行与识别提示共用的时间文案（03 §6）：
/// 今天 15:00 / 明天 / 周五 15:00 / 9月30日 / 2027年3月5日 15:00——
/// 今年以内不显示年份，全天待办不显示时刻。全部注入 now 与时区（NFR22）。
enum TimeDisplay {
    /// 日期部分：今天 / 明天 / 昨天 / 周X（未来 2～6 天）/ M月d日 / yyyy年M月d日。
    static func dayText(for date: Date, now: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: .timeDayToday)
        case 1: return String(localized: .timeDayTomorrow)
        case -1: return String(localized: .timeDayYesterday)
        case 2...6:
            let weekday = calendar.component(.weekday, from: date)
            let names = ["日", "一", "二", "三", "四", "五", "六"]
            return String(localized: .timeDayWeekday(names[weekday - 1]))
        default:
            let year = calendar.component(.year, from: date)
            let month = calendar.component(.month, from: date)
            let day = calendar.component(.day, from: date)
            let nowYear = calendar.component(.year, from: now)
            return year == nowYear
                ? String(localized: .timeDayMonthDay(month, day))
                : String(localized: .timeDayFullDate(year, month, day))
        }
    }

    /// 完整文案：日期部分 +（带时刻时）" HH:mm"。
    static func text(for date: Date, hasTime: Bool, now: Date, timeZone: TimeZone) -> String {
        let day = dayText(for: date, now: now, timeZone: timeZone)
        guard hasTime else { return day }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return day + " " + String(format: "%02d:%02d", hour, minute)
    }
}

/// 识别提示条内容（03 §4）：输入框下方 `🕒 文案（时长后缀） ✕`。
enum RecognitionHint {
    struct Content: Equatable {
        /// 主文案："周五 15:00 提醒"、"周六（全天）"、"今天 09:00（已过）"。
        let headline: String
        /// 相对时长的附加说明，如"30 分钟后"（视图加括号显示）。
        let durationSuffix: String?
        /// 已过时刻（红色显示）。
        let isPast: Bool
    }

    /// 相对时长的原文（"30分钟后""两天之后"）：提示带"（N 分钟后）"后缀（03 §4）。
    /// "之/以"连接的后置写法（05 §9.2 B03/B04）一并命中。
    private static let relativeDurationRegex = try! NSRegularExpression(
        pattern: #"^[0-9０-９一二两三四五六七八九十半]+\s*个?\s*(秒钟|分钟|小时|天)\s*[之以]?\s*后?$"#
    )

    static func isRelativeDuration(_ matchedText: String) -> Bool {
        let range = NSRange(location: 0, length: (matchedText as NSString).length)
        return relativeDurationRegex.firstMatch(in: matchedText, range: range) != nil
    }

    /// 从解析结果生成提示内容。
    static func content(matchedText: String, due: TodoDue, now: Date, timeZone: TimeZone) -> Content {
        let timeText = TimeDisplay.text(for: due.date, hasTime: due.hasTime, now: now, timeZone: timeZone)
        // 已过：仅带时刻且时刻早于现在（全天不存在"已过"样式，05 §2 全天为当天 00:00）。
        if due.hasTime, due.date < now {
            return Content(
                headline: String(localized: .captureRecognitionPast(timeText)),
                durationSuffix: nil,
                isPast: true
            )
        }
        if !due.hasTime {
            return Content(
                headline: String(localized: .captureRecognitionAllDay(timeText)),
                durationSuffix: nil,
                isPast: false
            )
        }
        var suffix: String?
        if isRelativeDuration(matchedText) {
            let remaining = due.date.timeIntervalSince(now)
            suffix = durationSuffix(for: remaining)
        }
        return Content(
            headline: String(localized: .captureRecognitionRemind(timeText)),
            durationSuffix: suffix,
            isPast: false
        )
    }

    private static func durationSuffix(for remaining: TimeInterval) -> String? {
        guard remaining > 0 else { return nil }
        if remaining < 3600 {
            return String(localized: .captureRecognitionMinutesLater(Int(max(1, (remaining / 60).rounded()))))
        }
        // 23.5 小时以上归并到"1 天后"，避免 86399 秒显示成"24 小时后"。
        if remaining < 84_600 {
            return String(localized: .captureRecognitionHoursLater(max(1, Int((remaining / 3600).rounded()))))
        }
        return String(localized: .captureRecognitionDaysLater(max(1, Int((remaining / 86_400).rounded()))))
    }
}
