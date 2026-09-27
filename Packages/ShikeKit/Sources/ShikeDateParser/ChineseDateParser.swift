// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 本文件自拾刻前项目 TZMemo 的 TZMemoDateParser 原样迁入（Story 1.15，2026-09-27），
// 随后的行为修正以 05 §9 用例驱动，见后续提交。

import Foundation

/// 中文自然语言日期解析器。
///
/// v1 规则范围：相对日（今天/明天/后天/大后天/X天后）、周X（含 下周X/下下周X/这周X 与 星期/礼拜 变体）、
/// X月X号（含年份滚动）、下个月X号、时段+时刻组合（明早八点、周五下午三点、晚上十二点等）。
/// 农历、节日语义、「月底」等模糊语不在 v1 范围。
///
/// 规则与测试用例是移植资产：后续 Flutter/Dart 版本按同一规则表与断言重新实现。
public final class ChineseDateParser {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    // MARK: - 公共入口

    public func parse(_ text: String, now: Date = Date()) -> DateParseResult? {
        var ranges: [NSRange] = []
        var dayResolution: DayResolution?
        let dayMatch = bestMatch(in: text, using: dayRegexes)
        if let dayMatch {
            dayResolution = resolveDay(dayMatch, now: now)
            ranges.append(dayMatch.range)
        }
        // 时刻匹配前把日期命中区遮蔽为等长占位符（索引不变），
        // 避免数字段贪婪跨界吃掉日期词尾部（如「周五三点」匹配出「五三点」）。
        let timeSearchText: String
        if let dayMatch {
            let masked = NSMutableString(string: text)
            masked.replaceCharacters(in: dayMatch.range, with: String(repeating: "_", count: dayMatch.range.length))
            timeSearchText = masked as String
        } else {
            timeSearchText = text
        }
        let timeMatch = bestMatch(in: timeSearchText, using: timeRegexes)
        if let timeMatch { ranges.append(timeMatch.range) }
        guard dayResolution != nil || timeMatch != nil else { return nil }

        let day = dayResolution ?? DayResolution(date: calendar.startOfDay(for: now), periodHint: nil, needsFutureRoll: false)
        let time = timeMatch.map { resolveTime($0, dayHint: day.periodHint) }

        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        var hasExplicitTime = false
        var containsHint = day.periodHint != nil

        if let time {
            components.hour = time.hour
            components.minute = time.minute
            if time.dayShift != 0 {
                components.day = (components.day ?? 0) + time.dayShift
            }
            hasExplicitTime = time.isExplicit
            containsHint = containsHint || time.periodHint != nil
        } else if let hint = day.periodHint {
            components.hour = hint.defaultHour
            components.minute = 0
        } else {
            components.hour = 9
            components.minute = 0
        }

        guard var date = calendar.date(from: components) else { return nil }

        // 「周X」拼上时刻后可能落在过去（如周五 16:00 时说「周五三点」）→ 整体后移一周。
        if day.needsFutureRoll, date <= now {
            date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        }
        // 只有时刻没有日期（「三点开会」）且已过去 → 顺延到明天。
        if dayResolution == nil, date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return DateParseResult(
            date: date,
            hasTime: hasExplicitTime || containsHint,
            matchedRanges: ranges
        )
    }

    // MARK: - 日期部分

    private enum DayKind {
        case relative(days: Int)                        // 今天/明天/后天/大后天/明早/明晚/今晚
        case daysLater(days: Int)                       // X天后
        case weekday(weekday: Int, weekOffset: Int)     // 周X / 下周X / 下下周X
        case monthDay(year: Int?, month: Int, day: Int) // X月X号（可选年份）
        case nextMonthDay(day: Int)                     // 下(个)月X号
    }

    private struct DayResolution {
        let date: Date
        let periodHint: TimePeriod?
        /// true 表示「周X」类目标：拼上时刻后若已过去，需按周粒度后移。
        let needsFutureRoll: Bool
    }

    private lazy var dayRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "大后天|后天|明天|明日|今天|今日|今晚|明早|明晚|当天"),
        try! NSRegularExpression(pattern: "(下下|下|本|这)(周|星期|礼拜)([一二两三四五六日天])"),
        try! NSRegularExpression(pattern: "(?<![上下本这])(周|星期|礼拜)([一二两三四五六日天])"),
        try! NSRegularExpression(pattern: "([0-9]{1,3}|[零一二两三四五六七八九十]{1,4})天(?:之|以)?后"),
        try! NSRegularExpression(pattern: "下(?:个)?月([0-9]{1,2}|[零一二两三四五六七八九十]{1,3})[日号]"),
        try! NSRegularExpression(pattern: "((?:20[0-9]{2})年)?([0-9]{1,2}|[零一二两三四五六七八九十]{1,3})月([0-9]{1,2}|[零一二两三四五六七八九十]{1,3})[日号]"),
    ]

    private func resolveDay(_ candidate: MatchCandidate, now: Date) -> DayResolution {
        let nowDay = calendar.startOfDay(for: now)

        func roll(_ days: Int, from base: Date = nowDay) -> Date {
            calendar.date(byAdding: .day, value: days, to: base) ?? nowDay
        }

        switch candidate.dayKind {
        case .relative(let days):
            let hint: TimePeriod?
            if candidate.text.hasPrefix("明早") {
                hint = .morning
            } else if candidate.text.hasPrefix("明晚") || candidate.text.hasPrefix("今晚") {
                hint = .evening
            } else {
                hint = nil
            }
            return DayResolution(date: roll(days), periodHint: hint, needsFutureRoll: false)

        case .daysLater(let days):
            return DayResolution(date: roll(days), periodHint: nil, needsFutureRoll: false)

        case .weekday(let target, let weekOffset):
            // 以日历设定的每周首日锚定「本周」，叠加周偏移；「周X」拼时刻后若已过去由 needsFutureRoll 顺延一周。
            let nowWeekday = calendar.component(.weekday, from: nowDay)
            let daysSinceWeekStart = (nowWeekday - calendar.firstWeekday + 7) % 7
            let startOfWeek = roll(-daysSinceWeekStart)
            let deltaIntoWeek = (target - calendar.firstWeekday + 7) % 7
            let date = roll(deltaIntoWeek + weekOffset * 7, from: startOfWeek)
            return DayResolution(date: date, periodHint: nil, needsFutureRoll: true)

        case .nextMonthDay(let day):
            // 下月 1 日 + (day-1) 天；越界（如 31 号遇到小月）则回退到下月最后一天。
            var monthStart = DateComponents()
            monthStart.year = calendar.component(.year, from: nowDay)
            monthStart.month = calendar.component(.month, from: nowDay)
            monthStart.day = 1
            monthStart.hour = 9
            let thisMonthFirst = calendar.date(from: monthStart) ?? nowDay
            let nextMonthFirst = calendar.date(byAdding: .month, value: 1, to: thisMonthFirst) ?? nowDay
            let monthAfterNextFirst = calendar.date(byAdding: .month, value: 1, to: nextMonthFirst) ?? nowDay
            let lastDayOfNextMonth = calendar.date(byAdding: .day, value: -1, to: monthAfterNextFirst) ?? nowDay
            let candidate = calendar.date(byAdding: .day, value: day - 1, to: nextMonthFirst) ?? lastDayOfNextMonth
            let date = calendar.startOfDay(for: candidate) > calendar.startOfDay(for: lastDayOfNextMonth) ? lastDayOfNextMonth : candidate
            return DayResolution(date: date, periodHint: nil, needsFutureRoll: false)

        case .monthDay(let year, let month, let day):
            var components = DateComponents()
            components.year = year ?? calendar.component(.year, from: nowDay)
            components.month = month
            components.day = day
            components.hour = 9
            guard let date = calendar.date(from: components) else {
                return DayResolution(date: nowDay, periodHint: nil, needsFutureRoll: false)
            }
            // 未指定年份且日期（按天比较）已过 → 滚到明年；同一天不滚动，交给时刻判断。
            if year == nil {
                let todayStart = calendar.startOfDay(for: now)
                if calendar.startOfDay(for: date) < todayStart {
                    let nextYear = calendar.date(byAdding: .year, value: 1, to: date) ?? date
                    return DayResolution(date: nextYear, periodHint: nil, needsFutureRoll: false)
                }
            }
            return DayResolution(date: date, periodHint: nil, needsFutureRoll: false)

        case .none:
            return DayResolution(date: nowDay, periodHint: nil, needsFutureRoll: false)
        }
    }

    // MARK: - 时刻部分

    private struct TimeResolution {
        let hour: Int
        let minute: Int
        let dayShift: Int
        let isExplicit: Bool
        let periodHint: TimePeriod?
    }

    private lazy var timeRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "(凌晨|清晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里|夜晚|半夜)?\\s*([0-9]{1,2}|[零一二两三四五六七八九十]{1,3})点(半|整|一刻|三刻|\\s*([0-5]?[0-9]|[零一二三四五六七八九十]{1,3})分?)?"),
        try! NSRegularExpression(pattern: "(凌晨|清晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里|夜晚|半夜)"),
    ]

    private func resolveTime(_ candidate: MatchCandidate, dayHint: TimePeriod?) -> TimeResolution {
        let info = candidate.timeInfo

        if let hour = info?.hour {
            // 显式时刻：优先用时刻自带的时段词，其次借用日期部分的时段提示（如「明早八点」），最后裸推断。
            let period = info?.period ?? dayHint
            let adjusted = period.map { $0.adjust(hour: hour) } ?? adjustBareHour(hour)
            return TimeResolution(
                hour: adjusted.hour % 24,
                minute: info?.minute ?? 0,
                dayShift: adjusted.dayShift + adjusted.hour / 24,
                isExplicit: true,
                periodHint: period
            )
        }

        // 仅时段词：取该时段的默认时刻
        let period = info?.period ?? .morning
        return TimeResolution(
            hour: period.defaultHour,
            minute: 0,
            dayShift: 0,
            isExplicit: false,
            periodHint: period
        )
    }

    /// 无时段词的裸时刻（如「三点」）：口语中 1~6 点通常指下午，7~11 点通常指上午，12 点为中午。
    private func adjustBareHour(_ hour: Int) -> (hour: Int, dayShift: Int) {
        (1...6).contains(hour) ? (hour + 12, 0) : (hour, 0)
    }

    // MARK: - 匹配基础设施

    private struct MatchCandidate {
        let range: NSRange
        let text: String
        let dayKind: DayKind?
        let timeInfo: (period: TimePeriod?, hour: Int?, minute: Int?)?
        let priority: Int
    }

    private func bestMatch(in text: String, using regexes: [NSRegularExpression]) -> MatchCandidate? {
        let nsText = text as NSString
        var candidates: [MatchCandidate] = []

        for (priority, regex) in regexes.enumerated() {
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { continue }
            candidates.append(buildCandidate(match: match, text: text, nsText: nsText, priority: priority))
        }

        // 取位置最靠前者；同位置取更长匹配；再同则取更高优先级（规则表顺序）。
        return candidates.min { lhs, rhs in
            if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
            if lhs.range.length != rhs.range.length { return lhs.range.length > rhs.range.length }
            return lhs.priority < rhs.priority
        }
    }

    private func buildCandidate(match: NSTextCheckingResult, text: String, nsText: NSString, priority: Int) -> MatchCandidate {
        let full = match.range
        let matchedText = nsText.substring(with: full)

        if matchedText.contains("点") || TimePeriod(rawValue: matchedText) != nil {
            return MatchCandidate(range: full, text: matchedText, dayKind: nil, timeInfo: classifyTime(match: match, nsText: nsText), priority: priority)
        }
        return MatchCandidate(range: full, text: matchedText, dayKind: classifyDay(match: match, text: matchedText, nsText: nsText), timeInfo: nil, priority: priority)
    }

    private func classifyDay(match: NSTextCheckingResult, text: String, nsText: NSString) -> DayKind? {
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return nsText.substring(with: range)
        }

        switch text {
        case "大后天": return .relative(days: 3)
        case "后天": return .relative(days: 2)
        case "明天", "明日", "明早", "明晚": return .relative(days: 1)
        case "今天", "今日", "今晚", "当天": return .relative(days: 0)
        default: break
        }

        // (下下|下|本|这)(周|星期|礼拜)X
        if let prefix = group(1), group(2) != nil, let weekdayText = group(3) {
            let offset: Int
            switch prefix {
            case "下下": offset = 2
            case "下": offset = 1
            default: offset = 0
            }
            if let weekday = ChineseNumber.weekday(weekdayText) {
                return .weekday(weekday: weekday, weekOffset: offset)
            }
        }

        // (周|星期|礼拜)X
        if let weekdayText = group(2), let weekday = ChineseNumber.weekday(weekdayText) {
            return .weekday(weekday: weekday, weekOffset: 0)
        }

        // X天(之/以)后
        if text.contains("天"), text.contains("后"), let numberText = group(1), let days = ChineseNumber.parse(numberText) {
            return .daysLater(days: days)
        }

        // 下(个)月X号
        if text.contains("下") && text.contains("月"), let dayText = group(1), let day = ChineseNumber.parse(dayText), (1...31).contains(day) {
            return .nextMonthDay(day: day)
        }

        // 年?月X号
        if let monthText = group(2), let dayText = group(3),
           let month = ChineseNumber.parse(monthText), let day = ChineseNumber.parse(dayText),
           (1...12).contains(month), (1...31).contains(day) {
            let year = group(1).flatMap { ChineseNumber.parse($0.replacingOccurrences(of: "年", with: "")) }
            return .monthDay(year: year, month: month, day: day)
        }

        return nil
    }

    private func classifyTime(match: NSTextCheckingResult, nsText: NSString) -> (period: TimePeriod?, hour: Int?, minute: Int?)? {
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return nsText.substring(with: range)
        }

        let period = group(1).flatMap { TimePeriod(rawValue: $0) }

        guard let hourText = group(2), let hour = ChineseNumber.parse(hourText) else {
            guard let period else { return nil }
            return (period, nil, nil)
        }
        guard (0...24).contains(hour) else { return (period, nil, nil) }

        var minute: Int?
        switch group(3) {
        case "半": minute = 30
        case "一刻": minute = 15
        case "三刻": minute = 45
        case .some(let value):
            if value == "整" { break }
            let raw = group(4) ?? value
            if let parsed = ChineseNumber.parse(raw.trimmingCharacters(in: .whitespaces)), (0...59).contains(parsed) {
                minute = parsed
            }
        case .none:
            break
        }
        return (period, hour, minute)
    }
}

// MARK: - 时段

enum TimePeriod: String {
    case dawn = "凌晨"
    case earlyMorning = "清晨"
    case morning = "早上"
    case forenoon = "上午"
    case noon = "中午"
    case afternoon = "下午"
    case dusk = "傍晚"
    case evening = "晚上"
    case night = "夜里"
    case midnight = "半夜"

    init?(rawValue: String) {
        switch rawValue {
        case "凌晨": self = .dawn
        case "清晨": self = .earlyMorning
        case "早上", "早晨", "早": self = .morning
        case "上午": self = .forenoon
        case "中午", "午后": self = .noon
        case "下午": self = .afternoon
        case "傍晚": self = .dusk
        case "晚上", "夜里", "夜晚", "晚": self = .evening
        case "半夜": self = .midnight
        default: return nil
        }
    }

    /// 仅时段词（无明确时刻）时的默认时刻。
    var defaultHour: Int {
        switch self {
        case .dawn: return 1
        case .earlyMorning: return 6
        case .morning: return 9
        case .forenoon: return 10
        case .noon: return 12
        case .afternoon: return 15
        case .dusk: return 18
        case .evening, .night: return 20
        case .midnight: return 23
        }
    }

    /// 按时段修正小时，返回 (修正后小时, 天数偏移)。例如「晚上十二点」= 次日 00:00。
    func adjust(hour raw: Int) -> (hour: Int, dayShift: Int) {
        switch self {
        case .dawn, .earlyMorning:
            return (raw % 24, 0)
        case .morning, .forenoon:
            return (raw == 12 ? 0 : raw, 0)
        case .noon:
            return (raw, 0)
        case .afternoon, .dusk:
            return (raw < 12 ? raw + 12 : raw, 0)
        case .evening, .night:
            if raw == 12 { return (0, 1) }
            return (raw < 12 ? raw + 12 : raw, 0)
        case .midnight:
            if raw == 12 { return (0, 1) }
            return (raw, 0)
        }
    }
}

extension ChineseNumber {
    /// 周 X 的数字部分 → Calendar.weekday（周日=1，周一=2 … 周六=7）。
    static func weekday(_ text: String) -> Int? {
        switch text {
        case "一": return 2
        case "二": return 3
        case "三": return 4
        case "四": return 5
        case "五": return 6
        case "六": return 7
        case "日", "天": return 1
        default: return nil
        }
    }
}
