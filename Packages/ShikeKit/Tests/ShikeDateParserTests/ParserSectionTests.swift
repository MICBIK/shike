// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import ShikeDateParser

/// Story 1.15：05 §9.1～§9.9 的 98 个用例（每个小节一个参数化测试，parser.md「测试组织」）。
/// 基准时间未注明的一律 T0 = 2026-09-23（周三）12:00，Asia/Shanghai。
struct ParserSectionTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        return calendar.date(from: components)!
    }

    static let t0 = makeDateStatic(2026, 9, 23, 12, 0)

    /// 供其他测试文件取基准时间 T0。
    static func makeT0() -> Date { t0 }

    private static func makeDateStatic(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)!
    }

    enum Expect {
        case allDay(Int, Int, Int)
        case at(Int, Int, Int, Int, Int)
    }

    struct CaseData {
        let id: String
        let input: String
        let now: Date
        let expect: Expect
        let highlights: [String]

        init(_ id: String, _ input: String, now: Date? = nil, _ expect: Expect, _ highlights: [String]) {
            self.id = id
            self.input = input
            self.now = now ?? ParserSectionTests.t0
            self.expect = expect
            self.highlights = highlights
        }
    }

    private func run(_ cases: [CaseData], sourceLocation: SourceLocation = #_sourceLocation) {
        let parser = ChineseDateParser(timeZone: Self.timeZone)
        for caseData in cases {
            let result = parser.parse(caseData.input, now: caseData.now)
            guard let result else {
                Issue.record("[\(caseData.id)] 未识别：\(caseData.input)")
                continue
            }
            switch caseData.expect {
            case .allDay(let y, let m, let d):
                #expect(result.date == Self.makeDateStatic(y, m, d, 0, 0), "[\(caseData.id)] \(caseData.input) → \(result.date)，期望 \(y)-\(m)-\(d) 全天")
                #expect(!result.hasTime, "[\(caseData.id)] 应为全天")
            case .at(let y, let m, let d, let h, let mi):
                #expect(result.date == Self.makeDateStatic(y, m, d, h, mi), "[\(caseData.id)] \(caseData.input) → \(result.date)，期望 \(y)-\(m)-\(d) \(h):\(mi)")
                #expect(result.hasTime, "[\(caseData.id)] 应带时刻")
            }
            #expect(result.matchedRanges == Self.ranges(of: caseData.highlights, in: caseData.input), "[\(caseData.id)] 高亮区间不符：\(result.matchedRanges)")
        }
    }

    /// 把"高亮"列的子串从输入开头依次查找，换算成 UTF-16 NSRange（parser.md「测试组织」）。
    private static func ranges(of highlights: [String], in input: String) -> [NSRange] {
        var result: [NSRange] = []
        var searchStart = input.startIndex
        for highlight in highlights {
            guard let range = input.range(of: highlight, range: searchStart..<input.endIndex) else {
                Issue.record("高亮「\(highlight)」在输入「\(input)」中找不到")
                continue
            }
            let location = input.utf16.distance(from: input.utf16.startIndex, to: range.lowerBound.samePosition(in: input.utf16)!)
            let length = input.utf16.distance(from: range.lowerBound.samePosition(in: input.utf16)!, to: range.upperBound.samePosition(in: input.utf16)!)
            result.append(NSRange(location: location, length: length))
            searchStart = range.upperBound
        }
        return result
    }

    // MARK: - §9.1 相对日（A01～A10）

    @Test("05 §9.1 相对日")
    func section91() {
        run(Self.section91)
    }

    private static let section91: [CaseData] = [
            CaseData("A01", "今天", .allDay(2026, 9, 23), ["今天"]),
            CaseData("A02", "明天交", .allDay(2026, 9, 24), ["明天"]),
            CaseData("A03", "后天", .allDay(2026, 9, 25), ["后天"]),
            CaseData("A04", "大后天", .allDay(2026, 9, 26), ["大后天"]),
            CaseData("A05", "明日", .allDay(2026, 9, 24), ["明日"]),
            CaseData("A06", "今晚", .at(2026, 9, 23, 20, 0), ["今晚"]),
            CaseData("A07", "明早", .at(2026, 9, 24, 8, 0), ["明早"]),
            CaseData("A08", "明晚", .at(2026, 9, 24, 20, 0), ["明晚"]),
            CaseData("A09", "今早八点", .at(2026, 9, 23, 8, 0), ["今早", "八点"]),
            CaseData("A10", "今天上午九点", .at(2026, 9, 23, 9, 0), ["今天", "上午九点"]),
        ]

    // MARK: - §9.2 若干天后（B01～B04）

    @Test("05 §9.2 若干天后")
    func section92() {
        run(Self.section92)
    }

    private static let section92: [CaseData] = [
            CaseData("B01", "三天后", .allDay(2026, 9, 26), ["三天后"]),
            CaseData("B02", "3天后", .allDay(2026, 9, 26), ["3天后"]),
            CaseData("B03", "三十天以后", .allDay(2026, 10, 23), ["三十天以后"]),
            CaseData("B04", "两天之后", .allDay(2026, 9, 25), ["两天之后"]),
        ]

    // MARK: - §9.3 相对时长（C01～C10）

    @Test("05 §9.3 相对时长")
    func section93() {
        run(Self.section93)
    }

    private static let section93: [CaseData] = [
            CaseData("C01", "半小时后", .at(2026, 9, 23, 12, 30), ["半小时后"]),
            CaseData("C02", "半个小时后", .at(2026, 9, 23, 12, 30), ["半个小时后"]),
            CaseData("C03", "10分钟后", .at(2026, 9, 23, 12, 10), ["10分钟后"]),
            CaseData("C04", "十分钟以后", .at(2026, 9, 23, 12, 10), ["十分钟以后"]),
            CaseData("C05", "45分钟后", .at(2026, 9, 23, 12, 45), ["45分钟后"]),
            CaseData("C06", "两小时后", .at(2026, 9, 23, 14, 0), ["两小时后"]),
            CaseData("C07", "2个小时后", .at(2026, 9, 23, 14, 0), ["2个小时后"]),
            CaseData("C08", "一个半小时后", .at(2026, 9, 23, 13, 30), ["一个半小时后"]),
            CaseData("C09", "1.5小时后", .at(2026, 9, 23, 13, 30), ["1.5小时后"]),
            CaseData("C10", "一刻钟后", .at(2026, 9, 23, 12, 15), ["一刻钟后"]),
        ]

    // MARK: - §9.4 星期（D01～D16）

    @Test("05 §9.4 星期")
    func section94() {
        run(Self.section94)
    }

    private static let section94: [CaseData] = [
            CaseData("D01", "周五", .allDay(2026, 9, 25), ["周五"]),
            CaseData("D02", "周一", .allDay(2026, 9, 28), ["周一"]),
            CaseData("D03", "周三", .allDay(2026, 9, 23), ["周三"]),
            CaseData("D04", "周三上午十点", .at(2026, 9, 30, 10, 0), ["周三", "上午十点"]),
            CaseData("D05", "周三下午三点", .at(2026, 9, 23, 15, 0), ["周三", "下午三点"]),
            CaseData("D06", "星期日", .allDay(2026, 9, 27), ["星期日"]),
            CaseData("D07", "礼拜天", .allDay(2026, 9, 27), ["礼拜天"]),
            CaseData("D08", "下周五", .allDay(2026, 10, 2), ["下周五"]),
            CaseData("D09", "下周一下午两点", .at(2026, 9, 28, 14, 0), ["下周一", "下午两点"]),
            CaseData("D10", "下周日早上九点", .at(2026, 10, 4, 9, 0), ["下周日", "早上九点"]),
            CaseData("D11", "下下周二", .allDay(2026, 10, 6), ["下下周二"]),
            CaseData("D12", "这周一", .allDay(2026, 9, 21), ["这周一"]),
            CaseData("D13", "本周五", .allDay(2026, 9, 25), ["本周五"]),
            CaseData("D14", "周五三点", now: Self.makeDateStatic(2026, 9, 25, 16, 0), .at(2026, 10, 2, 15, 0), ["周五", "三点"]),
            CaseData("D15", "周五下午三点交报告", .at(2026, 9, 25, 15, 0), ["周五", "下午三点"]),
            CaseData("D16", "下周日", .allDay(2026, 10, 4), ["下周日"]),
        ]

    // MARK: - §9.5 下周与周末（E01～E06）

    @Test("05 §9.5 下周与周末")
    func section95() {
        run(Self.section95)
    }

    private static let section95: [CaseData] = [
            CaseData("E01", "下周交报告", .allDay(2026, 9, 28), ["下周"]),
            CaseData("E02", "周末大扫除", .allDay(2026, 9, 26), ["周末"]),
            CaseData("E03", "这周末", .allDay(2026, 9, 26), ["这周末"]),
            CaseData("E04", "下周末", .allDay(2026, 10, 3), ["下周末"]),
            CaseData("E05", "周末", now: Self.makeDateStatic(2026, 9, 27, 10, 0), .allDay(2026, 9, 27), ["周末"]),
            CaseData("E06", "周末下午三点", .at(2026, 9, 26, 15, 0), ["周末", "下午三点"]),
        ]

    // MARK: - §9.6 月日（F01～F10）

    @Test("05 §9.6 月日")
    func section96() {
        run(Self.section96)
    }

    private static let section96: [CaseData] = [
            CaseData("F01", "10月1号", .allDay(2026, 10, 1), ["10月1号"]),
            CaseData("F02", "十月一号", .allDay(2026, 10, 1), ["十月一号"]),
            CaseData("F03", "10月1日", .allDay(2026, 10, 1), ["10月1日"]),
            CaseData("F04", "2027年3月5号", .allDay(2027, 3, 5), ["2027年3月5号"]),
            CaseData("F05", "9月1号", .allDay(2027, 9, 1), ["9月1号"]),
            CaseData("F06", "9月23号", .allDay(2026, 9, 23), ["9月23号"]),
            CaseData("F07", "12月30号下午四点半", .at(2026, 12, 30, 16, 30), ["12月30号", "下午四点半"]),
            CaseData("F08", "下个月3号", .allDay(2026, 10, 3), ["下个月3号"]),
            CaseData("F09", "下月31号", .allDay(2026, 10, 31), ["下月31号"]),
            CaseData("F10", "下个月31号", now: Self.makeDateStatic(2026, 1, 15, 12, 0), .allDay(2026, 2, 28), ["下个月31号"]),
        ]

    // MARK: - §9.7 时段与时刻（G01～G21）

    @Test("05 §9.7 时段与时刻")
    func section97() {
        run(Self.section97)
    }

    private static let section97: [CaseData] = [
            CaseData("G01", "明早八点", .at(2026, 9, 24, 8, 0), ["明早", "八点"]),
            CaseData("G02", "明天下午三点", .at(2026, 9, 24, 15, 0), ["明天", "下午三点"]),
            CaseData("G03", "今晚九点", .at(2026, 9, 23, 21, 0), ["今晚", "九点"]),
            CaseData("G04", "晚上八点半", .at(2026, 9, 23, 20, 30), ["晚上八点半"]),
            CaseData("G05", "明天上午十点二十", .at(2026, 9, 24, 10, 20), ["明天", "上午十点二十"]),
            CaseData("G06", "中午十二点", now: Self.makeDateStatic(2026, 9, 23, 10, 0), .at(2026, 9, 23, 12, 0), ["中午十二点"]),
            CaseData("G07", "明晚十二点", .at(2026, 9, 25, 0, 0), ["明晚", "十二点"]),
            CaseData("G08", "今晚十二点", .at(2026, 9, 24, 0, 0), ["今晚", "十二点"]),
            CaseData("G09", "下午", .at(2026, 9, 23, 15, 0), ["下午"]),
            CaseData("G10", "三点", .at(2026, 9, 23, 15, 0), ["三点"]),
            CaseData("G11", "九点", .at(2026, 9, 24, 9, 0), ["九点"]),
            CaseData("G12", "下午三点开会", .at(2026, 9, 23, 15, 0), ["下午三点"]),
            CaseData("G13", "晚上八点", now: Self.makeDateStatic(2026, 9, 23, 21, 0), .at(2026, 9, 24, 20, 0), ["晚上八点"]),
            CaseData("G14", "三点钟", .at(2026, 9, 23, 15, 0), ["三点钟"]),
            CaseData("G15", "十点整", .at(2026, 9, 24, 10, 0), ["十点整"]),
            CaseData("G16", "两点一刻", .at(2026, 9, 23, 14, 15), ["两点一刻"]),
            CaseData("G17", "八点三刻", .at(2026, 9, 24, 8, 45), ["八点三刻"]),
            CaseData("G18", "九点零五", .at(2026, 9, 24, 9, 5), ["九点零五"]),
            CaseData("G19", "9点30分", .at(2026, 9, 24, 9, 30), ["9点30分"]),
            CaseData("G20", "15点", .at(2026, 9, 23, 15, 0), ["15点"]),
            CaseData("G21", "早上", .at(2026, 9, 24, 8, 0), ["早上"]),
        ]

    // MARK: - §9.8 时段换算（H01～H14）

    @Test("05 §9.8 时段换算")
    func section98() {
        run(Self.section98)
    }

    private static let section98: [CaseData] = [
            CaseData("H01", "中午一点吃饭", .at(2026, 9, 23, 13, 0), ["中午一点"]),
            CaseData("H02", "明天中午一点", .at(2026, 9, 24, 13, 0), ["明天", "中午一点"]),
            CaseData("H03", "午后两点", .at(2026, 9, 23, 14, 0), ["午后两点"]),
            CaseData("H04", "晚上一点睡觉", .at(2026, 9, 24, 1, 0), ["晚上一点"]),
            CaseData("H05", "晚上一点", now: Self.makeDateStatic(2026, 9, 24, 0, 30), .at(2026, 9, 24, 1, 0), ["晚上一点"]),
            CaseData("H06", "今晚一点", .at(2026, 9, 24, 1, 0), ["今晚", "一点"]),
            CaseData("H07", "夜里两点", .at(2026, 9, 24, 2, 0), ["夜里两点"]),
            CaseData("H08", "半夜两点", .at(2026, 9, 24, 2, 0), ["半夜两点"]),
            CaseData("H09", "凌晨十二点", .at(2026, 9, 24, 0, 0), ["凌晨十二点"]),
            CaseData("H10", "凌晨三点", .at(2026, 9, 24, 3, 0), ["凌晨三点"]),
            CaseData("H11", "明天凌晨三点", .at(2026, 9, 24, 3, 0), ["明天", "凌晨三点"]),
            CaseData("H12", "上午十二点", now: Self.makeDateStatic(2026, 9, 23, 10, 0), .at(2026, 9, 23, 12, 0), ["上午十二点"]),
            CaseData("H13", "晚上十一点", .at(2026, 9, 23, 23, 0), ["晚上十一点"]),
            CaseData("H14", "晚上五点", .at(2026, 9, 23, 17, 0), ["晚上五点"]),
        ]

    // MARK: - §9.9 冒号时间（I01～I07）

    @Test("05 §9.9 冒号时间")
    func section99() {
        run(Self.section99)
    }

    private static let section99: [CaseData] = [
            CaseData("I01", "15:30开会", .at(2026, 9, 23, 15, 30), ["15:30"]),
            CaseData("I02", "明天 9:30", .at(2026, 9, 24, 9, 30), ["明天", "9:30"]),
            CaseData("I03", "下午3:30", .at(2026, 9, 23, 15, 30), ["下午3:30"]),
            CaseData("I04", "3:30", .at(2026, 9, 23, 15, 30), ["3:30"]),
            CaseData("I05", "8:00", .at(2026, 9, 24, 8, 0), ["8:00"]),
            CaseData("I06", "15：30", .at(2026, 9, 23, 15, 30), ["15：30"]),
            CaseData("I07", "周五 14:00", .at(2026, 9, 25, 14, 0), ["周五", "14:00"]),
        ]

    static var allRegistry: [(id: String, input: String)] {
        [section91, section92, section93, section94, section95, section96, section97, section98, section99]
            .flatMap { $0 }
            .map { (id: $0.id, input: $0.input) }
    }
}
