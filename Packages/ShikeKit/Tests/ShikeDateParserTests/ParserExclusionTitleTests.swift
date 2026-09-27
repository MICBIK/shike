// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import ShikeDateParser

/// Story 1.16：不识别（§9.10）、只识别日期部分（§9.11）、高亮区间（§9.12）、
/// 标题清理（§9.13），以及 05 §9 与测试数据的守护测试。
struct ParserExclusionTitleTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let t0 = ParserSectionTests.makeT0()

    @Test("05 §9.10 不识别（J01～J13）")
    func section910() {
        let parser = ChineseDateParser(timeZone: Self.timeZone)
        let cases: [(id: String, input: String)] = [
            ("J01", "买牛奶"), ("J02", "交报告"), ("J03", "有两点需要注意"),
            ("J04", "第一点先改文案"), ("J05", "买3点心"), ("J06", "这两点要改"),
            ("J07", "三点建议"), ("J08", "25:00"), ("J09", "12:75"),
            ("J10", "上周五"), ("J11", "2月30号"), ("J12", "早点回家"), ("J13", "点赞"),
        ]
        for testCase in cases {
            #expect(parser.parse(testCase.input, now: Self.t0) == nil, "[\(testCase.id)] \(testCase.input) 应不识别")
        }
    }

    @Test("05 §9.11 只识别日期部分（K01）")
    func section911() {
        let parser = ChineseDateParser(timeZone: Self.timeZone)
        let result = parser.parse("明天有两点需要注意", now: Self.t0)
        #expect(result?.date == date(2026, 9, 24))
        #expect(result?.hasTime == false)
        #expect(result?.matchedRanges == [NSRange(location: 0, length: 2)])
    }

    @Test("05 §9.12 高亮区间（L01～L05）")
    func section912() {
        let parser = ChineseDateParser(timeZone: Self.timeZone)
        let cases: [(input: String, expected: [NSRange])] = [
            ("买牛奶，明天提醒", [NSRange(location: 4, length: 2)]),
            ("明天下午三点", [NSRange(location: 0, length: 2), NSRange(location: 2, length: 4)]),
            ("半小时后提醒我", [NSRange(location: 0, length: 4)]),
            ("明天 9:30", [NSRange(location: 0, length: 2), NSRange(location: 3, length: 4)]),
            ("周五下午三点交报告", [NSRange(location: 0, length: 2), NSRange(location: 2, length: 4)]),
        ]
        for testCase in cases {
            let result = parser.parse(testCase.input, now: Self.t0)
            #expect(result?.matchedRanges == testCase.expected, "\(testCase.input) → \(String(describing: result?.matchedRanges))")
        }
    }

    @Test("05 §9.13 标题清理（M01～M08）")
    func section913() {
        let parser = ChineseDateParser(timeZone: Self.timeZone)
        let cases: [(id: String, input: String, expected: String)] = [
            ("M01", "周五下午三点交报告", "交报告"),
            ("M02", "明天提醒我买牛奶", "买牛奶"),
            ("M03", "买牛奶，明天提醒", "买牛奶"),
            ("M04", "10分钟后提醒我喝水", "喝水"),
            ("M05", "交报告 周五下午三点", "交报告"),
            ("M06", "周五下午三点，交报告。", "交报告"),
            ("M07", "明天", "明天"),
            ("M08", "记得明天交房租", "交房租"),
        ]
        for testCase in cases {
            let ranges = parser.parse(testCase.input, now: Self.t0)?.matchedRanges ?? []
            let title = TitleCleaner.clean(testCase.input, removing: ranges)
            #expect(title == testCase.expected, "[\(testCase.id)] 清理结果「\(title)」≠「\(testCase.expected)」")
        }
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        return calendar.date(from: components)!
    }
}

/// 守护测试（parser.md「测试组织」）：05 §9 各表的（编号, 输入）与测试数据做对称差，必须为空。
/// 任何一边增、删、改用例而另一边没有同步，测试即失败。
struct ParserGuardTests {
    @Test("守护测试：05 §9 全部 125 个用例与测试数据同步")
    func specCasesMatchTests() throws {
        let specRows = try Self.extractSpecRows()
        let specDict = Dictionary(uniqueKeysWithValues: specRows.map { ($0.id, $0.input) })
        let testRows = Self.testRegistry()

        #expect(specRows.count == 125, "05 §9 用例数应为 125，实际 \(specRows.count)；若规格有意变更，需同一次提交更新测试")
        #expect(testRows.count == 125, "测试数据用例数应为 125，实际 \(testRows.count)")

        var mismatches: [String] = []
        for (id, input) in specRows {
            guard let testInput = testRows[id] else {
                mismatches.append("[\(id)] 测试缺少用例（输入「\(input)」）")
                continue
            }
            if testInput != input {
                mismatches.append("[\(id)] 输入不一致：05「\(input)」 vs 测试「\(testInput)」")
            }
        }
        for id in testRows.keys where specDict[id] == nil {
            mismatches.append("[\(id)] 05 中没有该用例")
        }
        #expect(mismatches.isEmpty, "\(mismatches.joined(separator: "；"))")
    }

    /// 测试侧登记表：§9.1～§9.9（ParserSectionTests）+ §9.10～§9.13（本套件）。
    static func testRegistry() -> [String: String] {
        var registry = Dictionary(uniqueKeysWithValues: ParserSectionTests.allRegistry)
        for (id, input) in [
            ("J01", "买牛奶"), ("J02", "交报告"), ("J03", "有两点需要注意"),
            ("J04", "第一点先改文案"), ("J05", "买3点心"), ("J06", "这两点要改"),
            ("J07", "三点建议"), ("J08", "25:00"), ("J09", "12:75"),
            ("J10", "上周五"), ("J11", "2月30号"), ("J12", "早点回家"), ("J13", "点赞"),
            ("K01", "明天有两点需要注意"),
            ("L01", "买牛奶，明天提醒"), ("L02", "明天下午三点"), ("L03", "半小时后提醒我"),
            ("L04", "明天 9:30"), ("L05", "周五下午三点交报告"),
            ("M01", "周五下午三点交报告"), ("M02", "明天提醒我买牛奶"), ("M03", "买牛奶，明天提醒"),
            ("M04", "10分钟后提醒我喝水"), ("M05", "交报告 周五下午三点"), ("M06", "周五下午三点，交报告。"),
            ("M07", "明天"), ("M08", "记得明天交房租"),
        ] {
            registry[id] = input
        }
        return registry
    }

    /// 从 docs/05 §9 各表中提取（编号, 输入）。
    static func extractSpecRows() throws -> [(id: String, input: String)] {
        let docURL = try Self.locateSpecFile()
        let content = try String(contentsOf: docURL, encoding: .utf8)
        let pattern = try NSRegularExpression(pattern: "\\| ([A-M]\\d{2}) \\| ([^|]+?) \\|")
        let nsContent = content as NSString
        let matches = pattern.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        return matches.map { match in
            (id: nsContent.substring(with: match.range(at: 1)),
             input: nsContent.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces))
        }
    }

    /// 从测试文件路径向上找仓库根（以 docs/05-中文日期解析规格.md 为标志）。
    private static func locateSpecFile() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent("docs/05-中文日期解析规格.md")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        throw CocoaError(.fileNoSuchFile)
    }
}
