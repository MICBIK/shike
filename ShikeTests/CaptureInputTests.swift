// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.4：快速输入框与提交（app-shell.md「组件契约」、03 §4、NFR19）。
@MainActor
struct CaptureInputTests {
    /// 截止时间轮询：在 timeout 内每 20ms 检查一次条件（避免固定 sleep 在 CI 上抖动）。
    private func waitUntil(
        timeoutSeconds: Double = 2,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        // 最后再查一次，让失败时的错误来自条件本身
        if try await condition() { return }
        Issue.record("等待条件超时")
    }

    // - MARK: 高度计算（纯函数）

    @Test("captureHeight：至少一行、随内容增高、钳到 maxLines 行")
    func captureHeightComputation() {
        let lineHeight: CGFloat = 17
        #expect(CaptureTextView.captureHeight(usedHeight: 0, lineHeight: lineHeight, maxLines: 6) == lineHeight)
        #expect(CaptureTextView.captureHeight(usedHeight: 40, lineHeight: lineHeight, maxLines: 6) == 40)
        #expect(CaptureTextView.captureHeight(usedHeight: 500, lineHeight: lineHeight, maxLines: 6) == CGFloat(17 * 6))
        #expect(CaptureTextView.captureHeight(usedHeight: 500, lineHeight: lineHeight, maxLines: 2) == CGFloat(17 * 2))
        #expect(CaptureTextView.captureHeight(usedHeight: 10, lineHeight: lineHeight, maxLines: 0) == lineHeight) // 防御：maxLines 下限 1
    }
    // - MARK: 回车决策（纯函数）

    @Test("newlineDecision：组合态交输入法；⇧↩ 仅换行模式换行；裸回车提交；带修饰键防御放行")
    func newlineDecisions() {
        let shift = NSEvent.ModifierFlags.shift
        // 组合态优先于一切
        #expect(CaptureTextView.newlineDecision(hasMarkedText: true, allowsLineBreaks: true, modifiers: []) == .toInputMethod)
        #expect(CaptureTextView.newlineDecision(hasMarkedText: true, allowsLineBreaks: false, modifiers: shift) == .toInputMethod)
        // 便签模式（允许换行）：⇧↩ 换行、裸回车提交
        #expect(CaptureTextView.newlineDecision(hasMarkedText: false, allowsLineBreaks: true, modifiers: shift) == .insertLineBreak)
        #expect(CaptureTextView.newlineDecision(hasMarkedText: false, allowsLineBreaks: true, modifiers: []) == .submit)
        // 待办模式：⇧↩ 交回 AppKit 默认链，最终由 shouldChangeTextIn 拒绝 "\n"
        #expect(CaptureTextView.newlineDecision(hasMarkedText: false, allowsLineBreaks: false, modifiers: shift) == .passThrough)
        // 裸回车（待办模式）：提交
        #expect(CaptureTextView.newlineDecision(hasMarkedText: false, allowsLineBreaks: false, modifiers: []) == .submit)
        // ⌘↩ 等带修饰键：防御放行
        #expect(CaptureTextView.newlineDecision(hasMarkedText: false, allowsLineBreaks: true, modifiers: [.command]) == .passThrough)
    }

    // - MARK: 草稿与提交（内存库 + 模拟失败）

    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: defaults),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        return (environment, suiteName)
    }

    @Test("草稿：随输入持久化、跨模式隔离、重启恢复、提交成功清空")
    func draftPersistenceAndClear() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel

        model.draftNote = "买牛奶"
        model.draftTodo = "交报告"
        #expect(environment.preferences.panelDraftNote == "买牛奶")
        #expect(environment.preferences.panelDraftTodo == "交报告")
        #expect(model.currentDraft == "买牛奶")
        model.mode = .todo
        #expect(model.currentDraft == "交报告")

        // 重启恢复：用同一 suite 重组装
        let defaults = UserDefaults(suiteName: suiteName)!
        let second = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: defaults),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        #expect(second.panelModel.draftNote == "买牛奶")
        #expect(second.panelModel.draftTodo == "交报告")

        // 提交成功：对应草稿清空并持久化
        second.panelModel.mode = .note
        second.panelModel.draftNote = "再记一条"
        second.panelModel.submitCurrentDraft()
        try await waitUntil { second.panelModel.draftNote == "" }
        #expect(second.panelModel.currentDraft == "")
        #expect(environment.preferences.panelDraftNote == "")
    }

    @Test("提交：便签与待办各自入库；空与全空白无反应；recentlyCreatedID 被记录")
    func submitCreatesAndGuardsEmpty() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start() // 列表断言依赖观察流推送

        // 空内容：无反应
        model.mode = .note
        model.draftNote = "   "
        model.submitCurrentDraft()
        try await Task.sleep(for: .milliseconds(120))
        #expect(model.notes.isEmpty)
        #expect(model.draftNote == "   ") // 输入保留（无反应）

        // 便签提交
        model.draftNote = "买牛奶"
        model.submitCurrentDraft()
        try await waitUntil { model.notes.count == 1 }
        #expect(model.notes[0].note.content == "买牛奶")
        #expect(model.recentlyCreatedItemID == model.notes[0].note.uuid.uuidString)

        // 待办提交（due 为 nil）
        model.mode = .todo
        model.draftTodo = "交报告"
        model.submitCurrentDraft()
        try await waitUntil { model.todos.count == 1 }
        #expect(model.todos[0].title == "交报告")
        #expect(model.todos[0].due == nil)
        #expect(model.draftTodo == "")
    }

    @Test("提交失败：输入保留、提示条出现；重试绑定当次输入，成功后清空提示条与草稿（NFR19）")
    func submitFailureKeepsDraftAndRetrySucceeds() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        // 用接缝注入失败（不触碰数据库），观察重试是否绑定"当次输入"
        model.createNote = { _ in throw ShikeDataError.writeFailed(.diskFull) }
        model.draftNote = "重要内容"

        model.submitCurrentDraft()
        try await waitUntil { model.banner != nil }
        // 输入保留；提示条为保存失败
        #expect(model.draftNote == "重要内容")
        #expect(model.banner?.kind == .saveFailed(.diskFull))

        // 失败后用户改了草稿：重试仍应提交原输入，而不是新草稿
        model.draftNote = "后来改的"
        model.retryBanner()
        try await Task.sleep(for: .milliseconds(200)) // 失败路径同步完成，短暂让出即可
        #expect(model.draftNote == "后来改的") // 仍失败：新草稿保留
        #expect(model.banner?.kind == .saveFailed(.diskFull))
        #expect(model.notes.isEmpty)

        // 恢复真实仓储后重试：提交的是最初捕获的"重要内容"
        model.createNote = { try await environment.noteRepository.create(content: $0) }
        model.retryBanner()
        try await waitUntil { model.notes.count == 1 }
        #expect(model.notes[0].note.content == "重要内容")
        // 成功路径清空的是"当次提交对应模式"的草稿；用户后来改的草稿仍保留
        #expect(model.draftNote == "后来改的")
        #expect(model.banner == nil)
    }
}
