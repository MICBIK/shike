// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 本文件自拾刻前项目 TZMemo 的 TZMemoDateParser 原样迁入（Story 1.15，2026-09-27），
// 随后的行为修正以 05 §9 用例驱动（parser.md「需要修正的行为」差异表）。

import Foundation

/// 中文自然语言日期解析器（05 是唯一行为来源）。
///
/// 固定使用公历、以周一为一周之首；时区只取 `init` 的参数，结果与系统的
/// 区域、日历、"一周的第一天"设置无关（05 §3）。
public struct ChineseDateParser: Sendable {
    private let calendar: Calendar

    public init(timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // 周一
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    // MARK: - 公共入口

    public func parse(_ text: String, now: Date) -> DateParseResult? {
        // 相对时长：只采用相对时长，不再识别其他日期和时刻（05 §4.3）
        if let duration = bestMatch(in: text, using: Self.durationRegexes, kind: .duration) {
            let date = calendar.date(byAdding: .minute, value: resolveDuration(duration), to: now) ?? now
            return DateParseResult(date: date, hasTime: true, matchedRanges: [duration.range])
        }

        var ranges: [NSRange] = []
        var dayResolution: DayResolution?
        let dayMatch = bestMatch(in: text, using: Self.dayRegexes, kind: .day, now: now)
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
        let timeMatch = bestMatch(in: timeSearchText, using: Self.timeRegexes, kind: .time)
        if let timeMatch { ranges.append(timeMatch.range) }
        guard dayResolution != nil || timeMatch != nil else { return nil }

        // 区间按在文本中的位置排序（05 §2）
        let sortedRanges = ranges.sorted { $0.location < $1.location }

        let day = dayResolution ?? DayResolution(date: calendar.startOfDay(for: now), periodHint: nil, rollsFuture: false)
        let time = timeMatch.flatMap { resolveTime($0, dayHint: day.periodHint, daySpecified: dayResolution != nil) }

        var components = calendar.dateComponents([.year, .month, .day], from: day.date)
        var hasTime = time != nil
        if let time {
            components.hour = time.hour
            components.minute = time.minute
            if time.dayShift != 0 {
                components.day = (components.day ?? 0) + time.dayShift
            }
        } else if let hint = day.periodHint {
            // 日期自带时段（今早/明早/今晚/明晚）而无时刻部分：取该时段默认时刻，算作有时刻（05 §2）
            components.hour = hint.defaultHour
            components.minute = 0
            hasTime = true
        } else {
            // 只有日期：全天为当天 00:00（05 §2）
            components.hour = 0
            components.minute = 0
        }

        guard var date = calendar.date(from: components) else { return nil }

        // 05 §5 规则 2：无前缀的「周X」——全天时该日早于今天才顺延（当天不顺延）；带时刻时不晚于现在顺延。
        if day.rollsFuture {
            let shouldRoll = time != nil
                ? date <= now
                : calendar.startOfDay(for: date) < calendar.startOfDay(for: now)
            if shouldRoll {
                date = calendar.date(byAdding: .day, value: 7, to: date) ?? date
            }
        }
        // 05 §5 规则 1：只有时刻没有日期，不晚于现在 → 顺延到明天。
        if dayResolution == nil, date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return DateParseResult(date: date, hasTime: hasTime, matchedRanges: sortedRanges)
    }

    // MARK: - 日期部分

    private enum DayKind {
        case relative(days: Int)                                 // 今天/明天/后天/大后天/明早/明晚/今晚/今早
        case daysLater(days: Int)                                // X天后
        case weekday(weekday: Int, weekOffset: Int, rolls: Bool) // 周X / 下周X / 下下周X / 这周X / 本周X
        case monthDay(year: Int?, month: Int, day: Int)          // X月X号（可选年份）
        case nextMonthDay(day: Int)                              // 下(个)月X号
        case nextWeekMonday                                      // 下周（后面不跟星期）
        case weekend(weekOffset: Int)                            // 周末 / (这|本)周末 / 下周末
    }

    private struct DayResolution {
        let date: Date
        let periodHint: TimePeriod?
        /// true 表示无前缀的「周X」：拼上时刻后若已过去，需按周粒度后移（05 §5 规则 2）。
        let rollsFuture: Bool
    }

    private static let dayRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "今早|明早|明晚|今晚|大后天|后天|明天|明日|今天|今日"),
        try! NSRegularExpression(pattern: "(下下|下|本|这)(周|星期|礼拜)([一二两三四五六日天])"),
        try! NSRegularExpression(pattern: "下(?:个)?周末"),
        try! NSRegularExpression(pattern: "(?<![上下本这])(周|星期|礼拜)([一二两三四五六日天])"),
        try! NSRegularExpression(pattern: "(?<![下])下(?:个)?周(?!([一二两三四五六日天]|周|星期|礼拜))"),
        try! NSRegularExpression(pattern: "(?<![下])(?:本|这)?周末"),
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
            if candidate.text.hasPrefix("今早") || candidate.text.hasPrefix("明早") {
                hint = .morning
            } else if candidate.text.hasPrefix("今晚") || candidate.text.hasPrefix("明晚") {
                hint = .evening
            } else {
                hint = nil
            }
            return DayResolution(date: roll(days), periodHint: hint, rollsFuture: false)

        case .daysLater(let days):
            return DayResolution(date: roll(days), periodHint: nil, rollsFuture: false)

        case .weekday(let target, let weekOffset, let rolls):
            // 以周一为一周之首锚定「本周」，叠加周偏移；无前缀的「周X」拼时刻后若已过去按周顺延（05 §5 规则 2）。
            let nowWeekday = calendar.component(.weekday, from: nowDay)
            let daysSinceWeekStart = (nowWeekday - calendar.firstWeekday + 7) % 7
            let startOfWeek = roll(-daysSinceWeekStart)
            let deltaIntoWeek = (target - calendar.firstWeekday + 7) % 7
            let date = roll(deltaIntoWeek + weekOffset * 7, from: startOfWeek)
            return DayResolution(date: date, periodHint: nil, rollsFuture: rolls)

        case .weekend(let weekOffset):
            // 周末 = 本周六；今天是周六或周日则为今天；下周末再后移一周（05 §4.1）。
            let nowWeekday = calendar.component(.weekday, from: nowDay)
            let thisWeekend: Date
            if nowWeekday == 1 || nowWeekday == 7 {
                thisWeekend = nowDay
            } else {
                let daysSinceWeekStart = (nowWeekday - calendar.firstWeekday + 7) % 7
                thisWeekend = roll(5 - daysSinceWeekStart) // 周一为首时周六偏移 5
            }
            return DayResolution(date: roll(weekOffset * 7, from: thisWeekend), periodHint: nil, rollsFuture: false)

        case .nextWeekMonday:
            // 下周（后面不跟星期）→ 下周一（05 §4.1）。
            let nowWeekday = calendar.component(.weekday, from: nowDay)
            let daysSinceWeekStart = (nowWeekday - calendar.firstWeekday + 7) % 7
            let startOfWeek = roll(-daysSinceWeekStart)
            return DayResolution(date: roll(7, from: startOfWeek), periodHint: nil, rollsFuture: false)

        case .nextMonthDay(let day):
            // 下月 1 日 + (day-1) 天；越界（如 31 号遇到小月）则回退到下月最后一天（05 §4.1）。
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
            return DayResolution(date: date, periodHint: nil, rollsFuture: false)

        case .monthDay(let year, let month, let day):
            var components = DateComponents()
            components.year = year ?? calendar.component(.year, from: nowDay)
            components.month = month
            components.day = day
            components.hour = 9
            guard (1...12).contains(month), (1...31).contains(day), let date = calendar.date(from: components),
                  calendar.component(.day, from: date) == day else {
                // 日期不存在（如 2 月 30 号）：不识别（05 §3「合法性」）
                return DayResolution(date: nowDay, periodHint: nil, rollsFuture: false)
            }
            // 05 §5 规则 3：未写年份且该日（按天比较）早于今天 → 顺延到明年；当天不顺延。
            if year == nil {
                let todayStart = calendar.startOfDay(for: now)
                if calendar.startOfDay(for: date) < todayStart {
                    let nextYear = calendar.date(byAdding: .year, value: 1, to: date) ?? date
                    return DayResolution(date: nextYear, periodHint: nil, rollsFuture: false)
                }
            }
            return DayResolution(date: date, periodHint: nil, rollsFuture: false)
        case nil:
            return DayResolution(date: nowDay, periodHint: nil, rollsFuture: false)
        }
    }

    // MARK: - 时刻部分

    private struct TimeResolution {
        let hour: Int
        let minute: Int
        let dayShift: Int
    }

    private static let timeRegexes: [NSRegularExpression] = [
        // 冒号时间：H:MM（也接受全角冒号），H 为 0～23（05 §4.2）
        try! NSRegularExpression(pattern: "(凌晨|清晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里|夜晚|半夜)?\\s*([0-9]{1,2})[:：]([0-5][0-9])"),
        // X点：小时 0～24，可带 半/一刻/三刻/整/钟/X分/X/零X（05 §4.2）
        try! NSRegularExpression(pattern: "(凌晨|清晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里|夜晚|半夜)?\\s*([0-9]{1,2}|[零一二两三四五六七八九十]{1,3})点(半|一刻|三刻|整|钟|\\s*([0-5]?[0-9]|[零一二三四五六七八九十]{1,3})分?)?"),
        // 仅时段词
        try! NSRegularExpression(pattern: "(凌晨|清晨|早上|早晨|上午|中午|午后|下午|傍晚|晚上|夜里|夜晚|半夜)"),
    ]

    private func resolveTime(_ candidate: MatchCandidate, dayHint: TimePeriod?, daySpecified: Bool) -> TimeResolution? {
        guard let info = candidate.timeInfo else { return nil }

        if let hour = info.hour {
            // 显式时刻：优先用时刻自带的时段词，其次借用日期部分的时段提示（如「明早八点」），最后裸推断。
            let period = info.period ?? dayHint
            let adjusted: (hour: Int, dayShift: Int)
            if let period {
                adjusted = period.adjust(hour: hour, daySpecified: daySpecified)
            } else {
                adjusted = TimePeriod.adjustBareHour(hour)
            }
            return TimeResolution(hour: adjusted.hour % 24, minute: info.minute ?? 0, dayShift: adjusted.dayShift + adjusted.hour / 24)
        }

        // 仅时段词：取该时段的默认时刻（05 §4.4）
        let period = info.period ?? .morning
        return TimeResolution(hour: period.defaultHour, minute: 0, dayShift: 0)
    }

    // MARK: - 相对时长（05 §4.3）

    private static let durationRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "([0-9]{1,3}(?:\\.[0-9])?|[零一二两三四五六七八九十]{1,4})个半小时(?:之|以)?后|半(?:个)?小时(?:之|以)?后|([0-9]{1,3}(?:\\.[0-9])?|[零一二两三四五六七八九十]{1,4})个?小时(?:之|以)?后|([0-9]{1,3}|[零一二两三四五六七八九十]{1,4})分钟(?:之|以)?后|[一两三]刻钟(?:之|以)?后"),
    ]

    private func resolveDuration(_ candidate: MatchCandidate) -> Int {
        let text = candidate.text
        // X个半小时（X×90 分钟）
        if let range = text.range(of: "个半小时") {
            let prefix = String(text[..<range.lowerBound])
            let count = Double(ChineseNumber.parse(prefix) ?? 1)
            return Int((count * 90).rounded())
        }
        if text.hasPrefix("半") { return 30 } // 半小时 / 半个小时
        if text.contains("刻钟") {
            switch text.first {
            case "一": return 15
            case "两": return 30
            case "三": return 45
            default: return 15
            }
        }
        if let range = text.range(of: "分钟") {
            let prefix = String(text[..<range.lowerBound])
            return ChineseNumber.parse(prefix) ?? 0
        }
        if let range = text.range(of: "小时") {
            var prefix = String(text[..<range.lowerBound])
            if prefix.hasSuffix("个") { prefix.removeLast() }
            if let value = Double(prefix) {
                return Int((value * 60).rounded())
            }
            return (ChineseNumber.parse(prefix) ?? 0) * 60
        }
        return 0
    }

    // MARK: - 匹配基础设施

    private enum MatchKind {
        case day
        case time
        case duration
    }

    private enum TimeMatchKind {
        case colon
        case xClock
        case periodOnly
    }

    private struct MatchCandidate {
        let range: NSRange
        let text: String
        let dayKind: DayKind?
        let timeKind: TimeMatchKind?
        let timeInfo: (period: TimePeriod?, hour: Int?, minute: Int?)?
        let priority: Int
    }

    private func bestMatch(in text: String, using regexes: [NSRegularExpression], kind: MatchKind, now: Date = Date.distantPast) -> MatchCandidate? {
        let nsText = text as NSString
        var candidates: [MatchCandidate] = []

        for (priority, regex) in regexes.enumerated() {
            guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: nsText.length)) else { continue }
            guard let candidate = buildCandidate(match: match, text: text, nsText: nsText, priority: priority, kind: kind, now: now) else { continue }
            candidates.append(candidate)
        }

        // 取位置最靠前者；同位置取更长匹配；再同则取更高优先级（规则表顺序）。
        return candidates.min { lhs, rhs in
            if lhs.range.location != rhs.range.location { return lhs.range.location < rhs.range.location }
            if lhs.range.length != rhs.range.length { return lhs.range.length > rhs.range.length }
            return lhs.priority < rhs.priority
        }
    }

    /// 分类失败（越界时刻、不存在的日期等）时返回 nil，该候选整体不参与匹配（05 §3「合法性」）。
    private func buildCandidate(match: NSTextCheckingResult, text: String, nsText: NSString, priority: Int, kind: MatchKind, now: Date) -> MatchCandidate? {
        let full = match.range
        let matchedText = nsText.substring(with: full)

        switch kind {
        case .duration:
            return MatchCandidate(range: full, text: matchedText, dayKind: nil, timeKind: nil, timeInfo: nil, priority: priority)
        case .day:
            guard let dayKind = classifyDay(match: match, text: matchedText, nsText: nsText, now: now) else { return nil }
            return MatchCandidate(range: full, text: matchedText, dayKind: dayKind, timeKind: nil, timeInfo: nil, priority: priority)
        case .time:
            var full = match.range
            var matchedText = nsText.substring(with: full)
            while matchedText.first == " " {
                full.location += 1
                full.length -= 1
                matchedText.removeFirst()
            }
            let timeKind: TimeMatchKind
            if matchedText.contains("点") {
                timeKind = .xClock
            } else if matchedText.contains(":") || matchedText.contains("：") {
                timeKind = .colon
            } else {
                timeKind = .periodOnly
            }
            guard let info = classifyTime(match: match, nsText: nsText, kind: timeKind) else { return nil }
            return MatchCandidate(range: full, text: matchedText, dayKind: nil, timeKind: timeKind, timeInfo: info, priority: priority)
        }
    }

    private func classifyDay(match: NSTextCheckingResult, text: String, nsText: NSString, now: Date) -> DayKind? {
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
        case "今天", "今日", "今晚", "今早": return .relative(days: 0)
        case "下周末", "下个周末": return .weekend(weekOffset: 1)
        case "周末", "这周末", "本周末": return .weekend(weekOffset: 0)
        default: break
        }
        if text.hasPrefix("下") && (text.hasSuffix("周") || text.hasSuffix("个周")) { return .nextWeekMonday }

        // (下下|下|本|这)(周|星期|礼拜)X
        if let prefix = group(1), group(2) != nil, let weekdayText = group(3) {
            let offset: Int
            switch prefix {
            case "下下": offset = 2
            case "下": offset = 1
            default: offset = 0
            }
            if let weekday = ChineseNumber.weekday(weekdayText) {
                return .weekday(weekday: weekday, weekOffset: offset, rolls: false)
            }
        }

        // (周|星期|礼拜)X：无前缀，按 05 §5 规则 2 顺延
        if let weekdayText = group(2), let weekday = ChineseNumber.weekday(weekdayText) {
            return .weekday(weekday: weekday, weekOffset: 0, rolls: true)
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
            var components = DateComponents()
            components.year = year ?? calendar.component(.year, from: calendar.startOfDay(for: now))
            components.month = month
            components.day = day
            // 回读年、月、日必须与输入一致，否则不识别（parser.md「实现约束」：不依赖宽松进位）
            guard let probe = calendar.date(from: components),
                  calendar.component(.year, from: probe) == components.year,
                  calendar.component(.month, from: probe) == month,
                  calendar.component(.day, from: probe) == day else { return nil }
            return .monthDay(year: year, month: month, day: day)
        }

        return nil
    }

    private func classifyTime(match: NSTextCheckingResult, nsText: NSString, kind: TimeMatchKind) -> (period: TimePeriod?, hour: Int?, minute: Int?)? {
        func group(_ index: Int) -> String? {
            guard index < match.numberOfRanges else { return nil }
            let range = match.range(at: index)
            guard range.location != NSNotFound, range.length > 0 else { return nil }
            return nsText.substring(with: range)
        }

        let period = group(1).flatMap { TimePeriod(rawValue: $0) }

        switch kind {
        case .colon:
            guard let hourText = group(2), let hour = Int(hourText), (0...23).contains(hour),
                  let minuteText = group(3), let minute = Int(minuteText) else { return nil }
            return (period, hour, minute)
        case .periodOnly:
            guard let period else { return nil }
            return (period, nil, nil)
        case .xClock:
            guard let hourText = group(2), let hour = ChineseNumber.parse(hourText), (0...24).contains(hour) else { return nil }
            var minute: Int?
            switch group(3) {
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            case "整", "钟": minute = 0
            case .some(let value):
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
}

// MARK: - 时段（05 §4.4）

enum TimePeriod: String, Sendable {
    case dawn = "凌晨"
    case earlyMorning = "清晨"
    case morning = "早上"
    case forenoon = "上午"
    case noon = "中午"
    case earlyAfternoon = "午后"
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
        case "中午": self = .noon
        case "午后": self = .earlyAfternoon
        case "下午": self = .afternoon
        case "傍晚": self = .dusk
        case "晚上", "夜里", "夜晚", "晚": self = .evening
        case "半夜": self = .midnight
        default: return nil
        }
    }

    /// 只有时段词时的默认时刻（05 §4.4 表）。
    var defaultHour: Int {
        switch self {
        case .dawn: return 5
        case .earlyMorning: return 6
        case .morning: return 8
        case .forenoon: return 10
        case .noon: return 12
        case .earlyAfternoon: return 14
        case .afternoon: return 15
        case .dusk: return 18
        case .evening: return 20
        case .night: return 22
        case .midnight: return 23
        }
    }

    /// 有具体几点（h）时按 05 §4.4 换算成 24 小时制。
    /// 「次日凌晨」只在该句说明了哪一天时移天；未说明时交给 §5 规则 1 取最近的将来时刻。
    func adjust(hour raw: Int, daySpecified: Bool) -> (hour: Int, dayShift: Int) {
        func nextDawn(_ hour: Int) -> (hour: Int, dayShift: Int) {
            daySpecified ? (hour, 1) : (hour, 0)
        }
        switch self {
        case .dawn:
            return raw == 12 ? (0, 0) : (raw, 0)
        case .earlyMorning:
            return (raw, 0)
        case .morning, .forenoon:
            return (raw, 0) // 上午十二点即中午 12 点
        case .noon:
            return (1...5).contains(raw) ? (raw + 12, 0) : (raw, 0)
        case .earlyAfternoon, .afternoon, .dusk:
            return (raw < 12 ? raw + 12 : raw, 0)
        case .evening, .night:
            if (5...11).contains(raw) { return (raw + 12, 0) }
            if raw == 12 { return nextDawn(0) }
            if (0...4).contains(raw) { return nextDawn(raw) }
            return (raw, 0)
        case .midnight:
            if (7...11).contains(raw) { return (raw + 12, 0) }
            if raw == 12 { return nextDawn(0) }
            if (0...6).contains(raw) { return nextDawn(raw) }
            return (raw, 0)
        }
    }

    /// 无时段词的裸时刻：1～6 点视为下午；7～11 点视为上午；其余不变（24 点经 %24 归 0 后由 §5 规则 1 顺延）。
    static func adjustBareHour(_ hour: Int) -> (hour: Int, dayShift: Int) {
        (1...6).contains(hour) ? (hour + 12, 0) : (hour, 0)
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
