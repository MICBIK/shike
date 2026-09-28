// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 3.2：提交与标题清理（SPEC CAP-2、stage-2-components.md §2、05 §7 含 Issue #2 修订）。
@MainActor
struct TodoSubmissionTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    private static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 28
        components.hour = 10
        return calendar.date(from: components)!
    }()

    /// 模型 + 真实待办仓储（内存库，供接缝替身捕获参数后落库）。
    private func makeModel() throws -> (PanelModel, TodoRepository, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        let model = environment.panelModel
        model.timeZone = Self.timeZone
        model.parseNow = { Self.now }
        return (model, environment.todoRepository, suiteName)
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test("识别中提交：标题按 05 §7 清理，时间入 due（验收项）")
    func submitWithRecognitionCleansTitleAndStoresDue() async throws {
        let (model, repository, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        var capturedTitle: String?
        var capturedDue: TodoDue?
        model.createTodo = { title, due in
            capturedTitle = title
            capturedDue = due
            return try await repository.create(title: title, due: due)
        }

        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        // submit 在非结构化 Task 中执行：等待落库后再断言（盲审 F1）
        try await waitUntil { capturedTitle != nil }
        #expect(capturedTitle == "交报告")
        #expect(capturedDue?.hasTime == true)
        // 成功后草稿清空、识别复位
        #expect(model.draftTodo == "")
        #expect(model.recognition == nil)
    }

    @Test("取消识别后提交：仅空白标点清理、due 为 nil")
    func submitAfterDismissalStripsOnlyWhitespace() async throws {
        let (model, repository, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        var capturedTitle: String?
        var capturedDue: TodoDue?
        model.createTodo = { title, due in
            capturedTitle = title
            capturedDue = due
            return try await repository.create(title: title, due: due)
        }

        model.draftTodo = "明天交报告提醒我。"
        model.dismissRecognition()
        model.submitCurrentDraft()
        try await waitUntil { capturedTitle != nil }
        // 时间词与提醒词都留在标题里（不做第 1、3 步），只有首尾标点被清理
        #expect(capturedTitle == "明天交报告提醒我")
        #expect(capturedDue == nil)
    }

    @Test("无识别提交（无时间词）：提醒词照 05 §7 第 3 步清理，due 为 nil（盲审 F2）")
    func submitWithoutRecognitionStillStripsReminderWords() async throws {
        let (model, repository, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        var capturedTitle: String?
        var capturedDue: TodoDue?
        model.createTodo = { title, due in
            capturedTitle = title
            capturedDue = due
            return try await repository.create(title: title, due: due)
        }

        model.draftTodo = "记得还信用卡"
        #expect(model.recognition == nil) // 无时间词
        model.submitCurrentDraft()
        try await waitUntil { capturedTitle != nil }
        #expect(capturedTitle == "还信用卡")
        #expect(capturedDue == nil)
    }

    @Test("重试成功后清空草稿；重试期间的新草稿绝不丢（盲审 F5）")
    func retryClearsDraftOnlyIfUnchanged() async throws {
        let (model, repository, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        var attempts = 0
        model.createTodo = { title, due in
            attempts += 1
            if attempts == 1 {
                throw ShikeDataError.writeFailed(.diskFull)
            }
            return try await repository.create(title: title, due: due)
        }

        // 第一次提交失败：banner 出现，草稿保留
        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        try await waitUntil { attempts == 1 && model.banner != nil }
        #expect(model.draftTodo == "周五下午三点交报告")

        // 用户在重试前改动了草稿：重试成功后新草稿必须保留（不丢数据）
        model.draftTodo = "新草稿不能丢"
        model.retryBanner()
        try await waitUntil { attempts == 2 }
        #expect(model.draftTodo == "新草稿不能丢")
        #expect(model.banner == nil)

        // 未改动的提交成功：草稿清空（finishSubmit 在载荷返回后同步执行，attempts==3 即已结算）
        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        try await waitUntil { attempts == 3 }
        #expect(model.draftTodo == "")
        #expect(model.banner == nil)
    }

    @Test("重试重放提交时点的载荷：等待期间识别变化不漂移")
    func retryReplaysOriginalPayload() async throws {
        let (model, repository, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        var calls: [(title: String, due: TodoDue?)] = []
        var failNext = true
        model.createTodo = { title, due in
            if failNext {
                failNext = false
                throw ShikeDataError.writeFailed(.diskFull)
            }
            calls.append((title, due))
            return try await repository.create(title: title, due: due)
        }

        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        // 等第一次失败落地（截止时间轮询，防 CI 抖动）
        try await waitUntil { model.banner != nil }
        // 等待期间识别状态变化（模拟用户改动）
        model.dismissRecognition()
        // 点"重试"：应重放清理后的原始载荷，而不是按新状态重算
        model.retryBanner()
        try await waitUntil { !calls.isEmpty }
        #expect(calls.count == 1)
        #expect(calls[0].title == "交报告")
        #expect(calls[0].due?.hasTime == true)
    }

    // 截止时间轮询（仓库约定，防固定 sleep 在 CI 抖动）
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "等待条件在 2 秒内未满足")
    }
}
