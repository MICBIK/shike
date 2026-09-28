// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 3.1：时间识别与高亮（SPEC CAP-1、stage-2-components.md §1、03 §4）。
@MainActor
struct CaptureRecognitionTests {
    // 基准：T0 = 2026-09-28（周一）10:00，Asia/Shanghai（自定基准，05 §3 同口径）。
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 28
        components.hour = 10
        components.minute = 0
        return calendar.date(from: components)!
    }()

    private func makeModel() throws -> (PanelModel, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        let model = environment.panelModel
        model.timeZone = Self.timeZone
        model.parseNow = { Self.now }
        return (model, suiteName)
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // - MARK: 识别状态机

    @Test("待办草稿带时间：识别结果与高亮区间随输入更新")
    func recognizesTimeInTodoDraft() throws {
        let (model, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo

        model.draftTodo = "周五下午三点交报告"
        let recognition = try #require(model.recognition)
        // 2026-10-02 是基准那周的周五；15:00 带时刻。高亮区间按 05 §9.12 L05：(0,2)、(2,4)。
        let nsDraft = "周五下午三点交报告" as NSString
        #expect(nsDraft.substring(with: recognition.matchedRanges[0]) == "周五")
        #expect(nsDraft.substring(with: recognition.matchedRanges[1]) == "下午三点")
        #expect(model.recognizedDue?.hasTime == true)

        // 提示条内容：主文案含"周五 15:00 提醒"，无后缀、不红。
        guard case .recognized(let content) = try #require(model.recognitionHintState) else {
            Issue.record("应为 recognized")
            return
        }
        #expect(content.headline == "周五 15:00 提醒")
        #expect(content.durationSuffix == nil)
        #expect(content.isPast == false)
    }

    @Test("歧义规则在界面成立：有两点需要注意不识别，两点开会识别")
    func ambiguityRulesSurfaceInUI() throws {
        let (model, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo

        model.draftTodo = "有两点需要注意"
        #expect(model.recognition == nil)
        #expect(model.recognitionHintState == nil)

        model.draftTodo = "两点开会"
        #expect(model.recognition != nil)
    }

    @Test("✕ 取消：提示变灰、不再识别；清空草稿后复位并恢复识别")
    func dismissalResetsOnEmptyDraft() throws {
        let (model, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        model.draftTodo = "周五交报告"
        #expect(model.recognition != nil)

        model.dismissRecognition()
        #expect(model.recognitionDismissed)
        #expect(model.recognition == nil)
        guard case .dismissed = try #require(model.recognitionHintState) else {
            Issue.record("应为 dismissed")
            return
        }

        // 继续输入不再识别
        model.draftTodo = "周五交报告，再加一条"
        #expect(model.recognition == nil)
        #expect(model.recognitionHintState != nil) // 灰色提示仍在

        // 清空草稿复位；再次输入恢复识别
        model.draftTodo = ""
        #expect(model.recognitionDismissed == false)
        #expect(model.recognitionHintState == nil)
        model.draftTodo = "周五交报告"
        #expect(model.recognition != nil)
    }

    @Test("便签模式不识别；切回待办模式恢复")
    func noteModeSkipsRecognition() throws {
        let (model, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .note
        model.draftNote = "周五下午三点交报告"
        #expect(model.recognition == nil)
        #expect(model.recognitionHintState == nil)

        // 待办模式的草稿在切模式后重新识别
        model.draftTodo = "周五交报告"
        model.mode = .note
        #expect(model.recognition == nil)
        model.mode = .todo
        #expect(model.recognition != nil)
    }

    @Test("恢复的草稿在初始化时用注入的 now/时区识别一次")
    func restoredDraftIsRecognizedOnInit() throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        defaults.set(PanelModel.Mode.todo.rawValue, forKey: Preferences.Key.panelLastMode)
        defaults.set("明天上午十点开会", forKey: Preferences.Key.panelDraftTodo)

        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: defaults),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        // 直接构造：时区与 now 经 init 注入（init 恢复草稿时即用它们解析，盲审 M3b）。
        let model = PanelModel(
            noteRepository: environment.noteRepository,
            todoRepository: environment.todoRepository,
            preferences: Preferences(defaults: defaults),
            timeZone: Self.timeZone,
            parseNow: { Self.now }
        )
        let recognition = try #require(model.recognition)
        #expect(model.recognizedDue?.hasTime == true)
        // "明天上午十点" = 2026-09-29 10:00（基准 T0 = 2026-09-28 10:00）。
        #expect(recognition.date == Self.now.addingTimeInterval(24 * 3600))
    }

    // - MARK: 提示内容（纯函数）

    @Test("提示文案：带时刻 / 全天 / 已过（红）/ 相对时长后缀")
    func hintContentVariants() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone

        func due(_ days: Int, _ hour: Int?, from now: Date = Self.now) -> TodoDue {
            let day = calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: now))!
            guard let hour else { return TodoDue(date: day, hasTime: false) }
            return TodoDue(date: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day)!, hasTime: true)
        }

        // 带时刻（未来）：本周五 15:00 → "周五 15:00 提醒"
        let friday = due(4, 15) // 2026-10-02 周五
        let fridayHint = RecognitionHint.content(matchedText: "周五下午三点", due: friday, now: Self.now, timeZone: Self.timeZone)
        #expect(fridayHint == RecognitionHint.Content(headline: "周五 15:00 提醒", durationSuffix: nil, isPast: false))

        // 全天："周六（全天）"
        let saturday = due(5, nil)
        let saturdayHint = RecognitionHint.content(matchedText: "周六", due: saturday, now: Self.now, timeZone: Self.timeZone)
        #expect(saturdayHint == RecognitionHint.Content(headline: "周六（全天）", durationSuffix: nil, isPast: false))

        // 已过：今天 09:00 → 红色"今天 09:00（已过）"
        let past = due(0, 9)
        let pastHint = RecognitionHint.content(matchedText: "今天九点", due: past, now: Self.now, timeZone: Self.timeZone)
        #expect(pastHint == RecognitionHint.Content(headline: "今天 09:00（已过）", durationSuffix: nil, isPast: true))

        // 相对时长："30分钟后" → 主文案 + "30 分钟后"后缀
        let relative = due(0, 10) // 10:00 + 30 分钟 = 10:30
        let relativeDate = calendar.date(byAdding: .minute, value: 30, to: relative.date)!
        let relativeDue = TodoDue(date: relativeDate, hasTime: true)
        let relativeHint = RecognitionHint.content(matchedText: "30分钟后", due: relativeDue, now: Self.now, timeZone: Self.timeZone)
        #expect(relativeHint.headline == "今天 10:30 提醒")
        #expect(relativeHint.durationSuffix == "30 分钟后")
        #expect(relativeHint.isPast == false)
    }

    @Test("相对时长判定：命中常见写法，放过时刻与日期词")
    func relativeDurationDetection() {
        #expect(RecognitionHint.isRelativeDuration("30分钟后"))
        #expect(RecognitionHint.isRelativeDuration("两小时"))
        #expect(RecognitionHint.isRelativeDuration("半天后"))
        #expect(RecognitionHint.isRelativeDuration("30分钟后见") == false) // 后面还有内容
        #expect(RecognitionHint.isRelativeDuration("周五下午三点") == false)
        #expect(RecognitionHint.isRelativeDuration("今天九点") == false)
    }

    // - MARK: 高亮应用

    @Test("applyHighlight：区间着色、变化重设、越界忽略、清空移除")
    func highlightApplication() {
        let textView = CaptureNSTextView()
        var lastApplied: CaptureTextView.HighlightKey?

        textView.string = "周五下午三点交报告"
        let range = NSRange(location: 0, length: 6)
        CaptureTextView.applyHighlight(ranges: [range], in: textView, lastApplied: &lastApplied)
        let storage = textView.textStorage!
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)
        #expect(storage.attribute(.backgroundColor, at: 6, effectiveRange: nil) == nil)

        // 相同输入不重设（lastApplied 命中时属性保持原样）
        CaptureTextView.applyHighlight(ranges: [range], in: textView, lastApplied: &lastApplied)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) != nil)

        // 清空区间：高亮移除
        CaptureTextView.applyHighlight(ranges: [], in: textView, lastApplied: &lastApplied)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)

        // 越界区间被忽略（不崩溃、不越界着色）
        CaptureTextView.applyHighlight(ranges: [NSRange(location: 100, length: 5)], in: textView, lastApplied: &lastApplied)
        #expect(storage.attribute(.backgroundColor, at: 0, effectiveRange: nil) == nil)
    }
}
