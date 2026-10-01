// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Note/Todo 的 memberwise init 是 internal（包内约定）

/// S3.5-05：回收站模型（纯 mock 闭包，无需数据库）。
/// 覆盖：观察流推送、确认弹窗状态机（置目标 → confirm 执行 / cancel 清理）、
/// 恢复与清空的闭包转发、反馈小字条的自动清除与"集成层文案优先"约定。
@MainActor
struct TrashModelTests {
    // - MARK: 造数与工具

    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func note(id: Int64, content: String) -> Note {
        Note(
            id: Note.ID(rawValue: id),
            uuid: UUID(),
            content: content,
            pinnedAt: nil,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: Self.now
        )
    }

    private func todo(id: Int64, title: String) -> Todo {
        Todo(
            id: Todo.ID(rawValue: id),
            uuid: UUID(),
            title: title,
            due: nil,
            snoozedUntil: nil,
            completedAt: nil,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: Self.now
        )
    }

    // 默认成功文案的期望值（与模型同走 xcstrings 键，文案改动不破测试）
    private var restoredNoteMessage: String {
        String(localized: .mainTrashRestored(String(localized: .mainTrashNotes)))
    }
    private var restoredTodoMessage: String {
        String(localized: .mainTrashRestored(String(localized: .mainTrashTodos)))
    }
    private var deletedNoteMessage: String {
        String(localized: .mainTrashPermanentlyDeleted(String(localized: .mainTrashNotes)))
    }
    private var deletedTodoMessage: String {
        String(localized: .mainTrashPermanentlyDeleted(String(localized: .mainTrashTodos)))
    }
    private var emptiedMessage: String {
        String(localized: .mainTrashEmptied)
    }

    /// 手工推进的观察流：返回工厂闭包（注入模型）与 continuation（测试推数据）。
    /// 用类型令牌传 Element（Swift 不允许对泛型方法显式特化 makeStream<Note>()）。
    private func makeStream<Element: Sendable>(of type: Element.Type) -> (
        factory: () -> AsyncThrowingStream<[Element], any Error>,
        continuation: AsyncThrowingStream<[Element], any Error>.Continuation
    ) {
        var continuation: AsyncThrowingStream<[Element], any Error>.Continuation!
        let stream = AsyncThrowingStream<[Element], any Error> { continuation = $0 }
        return ({ stream }, continuation)
    }

    /// 轮询等待条件成立（观察流跨 hop 回流，用短轮询代替时序假设）。
    private func waitUntil(
        timeoutSeconds: Double = 2,
        _ label: String = "",
        _ condition: () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if !condition() {
            Issue.record("等待超时：\(label)")
        }
    }

    // - MARK: 观察流

    @Test("两个观察流推送：deletedNotes/deletedTodos 随流更新且模型不再重排（流序即展示序）")
    func streamsUpdateDeletedItems() async throws {
        let notesStream = makeStream(of: Note.self)
        let todosStream = makeStream(of: Todo.self)
        let model = TrashModel()
        model.observeNotes = notesStream.factory
        model.observeTodos = todosStream.factory
        model.start()
        defer { model.stop() }

        // 数据层按 deletedAt 降序推送；故意按"后删在前"推入，验证模型原样保留不排序。
        notesStream.continuation.yield([note(id: 2, content: "后删的便签"), note(id: 1, content: "先删的便签")])
        todosStream.continuation.yield([todo(id: 4, title: "后删的待办"), todo(id: 3, title: "先删的待办")])

        try await waitUntil("两组已删数据") {
            model.deletedNotes.map(\.content) == ["后删的便签", "先删的便签"]
                && model.deletedTodos.map(\.title) == ["后删的待办", "先删的待办"]
        }

        // 便签流推空只清便签组，待办组不受影响
        notesStream.continuation.yield([])
        try await waitUntil("便签清空") { model.deletedNotes.isEmpty }
        #expect(model.deletedTodos.map(\.title) == ["后删的待办", "先删的待办"])
    }

    // - MARK: 永久删除（确认弹窗状态机）

    @Test("requestDelete 置 confirmTarget；confirm() 执行永久删除闭包并给出反馈、清空确认状态")
    func confirmRunsPermanentDelete() async {
        var deletedNoteIDs: [Note.ID] = []
        var deletedTodoIDs: [Todo.ID] = []
        let model = TrashModel()
        model.permanentlyDeleteNote = { deletedNoteIDs.append($0) }
        model.permanentlyDeleteTodo = { deletedTodoIDs.append($0) }

        model.requestDeleteNote(Note.ID(rawValue: 7))
        #expect(model.confirmTarget == .note(Note.ID(rawValue: 7)))
        await model.confirm()
        #expect(deletedNoteIDs == [Note.ID(rawValue: 7)])
        #expect(model.statusMessage == deletedNoteMessage)
        #expect(model.confirmTarget == nil)

        model.requestDeleteTodo(Todo.ID(rawValue: 8))
        #expect(model.confirmTarget == .todo(Todo.ID(rawValue: 8)))
        await model.confirm()
        #expect(deletedTodoIDs == [Todo.ID(rawValue: 8)])
        #expect(model.statusMessage == deletedTodoMessage)
        #expect(model.confirmTarget == nil)
    }

    @Test("cancel() 清理确认状态（单条删除与清空三个入口；无待确认时无操作）")
    func cancelClearsConfirmTarget() async {
        var emptyAllCount = 0
        var deletedNoteIDs: [Note.ID] = []
        var deletedTodoIDs: [Todo.ID] = []
        let model = TrashModel()
        model.emptyAll = { emptyAllCount += 1 }
        model.permanentlyDeleteNote = { deletedNoteIDs.append($0) }
        model.permanentlyDeleteTodo = { deletedTodoIDs.append($0) }

        model.requestDeleteNote(Note.ID(rawValue: 1))
        model.cancel()
        #expect(model.confirmTarget == nil)

        model.requestDeleteTodo(Todo.ID(rawValue: 2))
        model.cancel()
        #expect(model.confirmTarget == nil)

        model.requestEmptyAll()
        #expect(model.confirmTarget == .all)
        model.cancel()
        #expect(model.confirmTarget == nil)

        // 无待确认目标时 confirm()/cancel() 均无操作；取消不触发任何写
        await model.confirm()
        model.cancel()
        #expect(emptyAllCount == 0)
        #expect(deletedNoteIDs.isEmpty)
        #expect(deletedTodoIDs.isEmpty)
    }

    // - MARK: 恢复与清空的转发

    @Test("恢复直接转发（不走确认）；清空经 requestEmptyAll + confirm 转发")
    func forwardingToClosures() async {
        var restoredNoteIDs: [Note.ID] = []
        var restoredTodoIDs: [Todo.ID] = []
        var emptyAllCount = 0
        let model = TrashModel()
        model.restoreNote = { restoredNoteIDs.append($0) }
        model.restoreTodo = { restoredTodoIDs.append($0) }
        model.emptyAll = { emptyAllCount += 1 }

        await model.requestRestoreNote(Note.ID(rawValue: 3))
        await model.requestRestoreTodo(Todo.ID(rawValue: 4))
        #expect(restoredNoteIDs == [Note.ID(rawValue: 3)])
        #expect(restoredTodoIDs == [Todo.ID(rawValue: 4)])
        #expect(model.confirmTarget == nil) // 恢复不置确认目标
        #expect(model.statusMessage == restoredTodoMessage) // 最近一次动作的反馈
        #expect(emptyAllCount == 0)

        model.requestEmptyAll()
        #expect(model.confirmTarget == .all)
        await model.confirm()
        #expect(emptyAllCount == 1)
        #expect(model.statusMessage == emptiedMessage)
        #expect(model.confirmTarget == nil)
    }

    // - MARK: 反馈小字条

    @Test("statusMessage 自动清除：窗口内保持、连续 showStatus 重启计时、到期归 nil")
    func statusAutoClears() async throws {
        let model = TrashModel()
        model.statusHideDelay = .milliseconds(400)
        #expect(model.statusMessage == nil)

        await model.requestRestoreNote(Note.ID(rawValue: 5))
        #expect(model.statusMessage == restoredNoteMessage)

        // 窗口内不提前清除（余量 250ms）
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.statusMessage == restoredNoteMessage)

        // 二次 showStatus 重启计时：t=500 已过首次的 400ms 期限仍在展示（证明重启），
        // 且未到重启后的 550ms 期限
        model.showStatus("手动文案")
        try await Task.sleep(for: .milliseconds(350))
        #expect(model.statusMessage == "手动文案")

        // 手动文案到期归 nil（余量 250ms）
        try await Task.sleep(for: .milliseconds(300))
        #expect(model.statusMessage == nil)
    }

    @Test("集成层在动作闭包内经 showStatus 传回的文案优先（默认成功文案不覆盖失败文案）")
    func closureReportedStatusWins() async {
        let model = TrashModel()
        model.restoreNote = { [weak model] _ in
            model?.showStatus("恢复失败：数据库不可用")
        }
        await model.requestRestoreNote(Note.ID(rawValue: 6))
        #expect(model.statusMessage == "恢复失败：数据库不可用")
    }

    @Test("连续动作：后一次动作的默认反馈覆盖前一次（便签/待办文案不同，可区分覆盖与跳过）")
    func consecutiveActionsEachReport() async {
        let model = TrashModel()
        await model.requestRestoreNote(Note.ID(rawValue: 1))
        await model.requestRestoreTodo(Todo.ID(rawValue: 2))
        // 若第二次被跳过，屏上仍是便签文案；断言待办文案即钉住"覆盖"语义
        #expect(model.statusMessage == restoredTodoMessage)
    }

    @Test("清空动作的闭包上报文案优先（.all 分支的默认成功文案不覆盖失败文案）")
    func emptyAllClosureReportedStatusWins() async {
        let model = TrashModel()
        model.emptyAll = { [weak model] in
            model?.showStatus("清空失败：数据库不可用")
        }
        model.requestEmptyAll()
        await model.confirm()
        #expect(model.statusMessage == "清空失败：数据库不可用")
        #expect(model.statusMessage != emptiedMessage)
    }

    // - MARK: 视图竞态路径与生命周期

    @Test("confirm(捕获目标)：confirmTarget 已被收起回调 cancel() 清空仍执行（弹窗收起竞态窗口）")
    func confirmWithCapturedTargetRunsAfterCancel() async {
        var deletedNoteIDs: [Note.ID] = []
        let model = TrashModel()
        model.permanentlyDeleteNote = { deletedNoteIDs.append($0) }

        model.requestDeleteNote(Note.ID(rawValue: 7))
        model.cancel() // 弹窗收起回调先行清空 confirmTarget
        await model.confirm(.note(Note.ID(rawValue: 7))) // 视图捕获的 presented 目标仍执行
        #expect(deletedNoteIDs == [Note.ID(rawValue: 7)])
        #expect(model.statusMessage == deletedNoteMessage)
        #expect(model.confirmTarget == nil)
    }

    @Test("观察流异常收尾：先推快照再 readFailed——不崩且状态保留")
    func streamFailurePreservesState() async throws {
        let model = TrashModel()
        model.observeNotes = {
            AsyncThrowingStream { continuation in
                continuation.yield([note(id: 1, content: "失败前快照")])
                continuation.finish(throwing: ShikeDataError.readFailed(.ioError))
            }
        }
        model.observeTodos = {
            AsyncThrowingStream { $0.finish(throwing: ShikeDataError.readFailed(.ioError)) }
        }
        model.start()
        defer { model.stop() }

        try await waitUntil("快照落地") { !model.deletedNotes.isEmpty }
        try await Task.sleep(for: .milliseconds(100)) // 异常收尾后无变化
        #expect(model.deletedNotes.map(\.id) == [Note.ID(rawValue: 1)])
    }

    @Test("stop 停止消费：停流后再推不改变状态")
    func stopStopsDeliveringUpdates() async throws {
        let notesStream = makeStream(of: Note.self)
        let todosStream = makeStream(of: Todo.self)
        let model = TrashModel()
        model.observeNotes = notesStream.factory
        model.observeTodos = todosStream.factory
        model.start()
        defer { model.stop() }

        notesStream.continuation.yield([note(id: 1, content: "停流前")])
        try await waitUntil("首帧") { !model.deletedNotes.isEmpty }

        model.stop()
        notesStream.continuation.yield([note(id: 2, content: "停流后")])
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.deletedNotes.map(\.id) == [Note.ID(rawValue: 1)])
    }

    /// onTermination 回调跨线程送达的收集器（Termination 非 Equatable，按 case 匹配）。
    private final class TerminationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AsyncThrowingStream<[Note], any Error>.Continuation.Termination] = []

        func append(_ item: AsyncThrowingStream<[Note], any Error>.Continuation.Termination) {
            lock.withLock { items.append(item) }
        }

        var hasCancelled: Bool {
            lock.withLock { items.contains { if case .cancelled = $0 { return true }; return false } }
        }
    }

    @Test("重复 start 幂等：旧订阅被取消（onTermination .cancelled）、旧流迟到推送不改变状态")
    func startTwiceCancelsOldSubscription() async throws {
        let model = TrashModel()
        var factories = 0
        let terminations = TerminationBox()
        var continuations: [AsyncThrowingStream<[Note], any Error>.Continuation] = []
        model.observeNotes = {
            factories += 1
            return AsyncThrowingStream { continuation in
                continuations.append(continuation)
                continuation.onTermination = { terminations.append($0) }
            }
        }
        model.observeTodos = { AsyncThrowingStream { $0.finish() } }
        model.start()
        model.start()
        defer { model.stop() }

        // 工厂在 start() 的两个 Task 内异步调用，等两次订阅都发生
        try await waitUntil("两次订阅发生") { factories == 2 }
        try await Task.sleep(for: .milliseconds(50))
        #expect(terminations.hasCancelled) // 第一次的旧流已被取消

        // 旧流迟到推送不改变状态；新流仍然活着
        continuations[0].yield([note(id: 9, content: "旧流迟到")])
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.deletedNotes.isEmpty)

        continuations[1].yield([note(id: 10, content: "新流到达")])
        try await waitUntil("新流落地") { !model.deletedNotes.isEmpty }
        #expect(model.deletedNotes.map(\.id) == [Note.ID(rawValue: 10)])
    }
}
