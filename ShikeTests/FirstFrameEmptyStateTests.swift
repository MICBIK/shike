// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData

/// 主窗口三视图首帧空态闪现（W2）：观察流首帧未到时模型为空数组，
/// 视图不得闪现"还没有便签 / 没有待办 / 回收站为空"——三模型以 isLoaded
/// 承载"首帧已送达（含空数组帧）/ 流已失败收尾"，视图按 `isLoaded && isEmpty` 分流。
@MainActor
struct FirstFrameEmptyStateTests {
    /// 一次性流：先推一帧再结束（帧可为空数组——空数组帧也算首帧）。
    private func oneShot<T: Sendable>(_ items: [T]) -> AsyncThrowingStream<[T], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 立即以读取失败收尾的流（非取消结束同形）。
    private func failing<T>() -> AsyncThrowingStream<[T], any Error> {
        AsyncThrowingStream { $0.finish(throwing: ShikeDataError.readFailed(.ioError)) }
    }

    /// 等待一个挂起流到达指定状态（给流任务让出调度的时间窗）。
    private func settle() async throws {
        try await Task.sleep(for: .milliseconds(80))
    }

    // - MARK: MainNotesModel

    @Test("便签模型：空数组帧即首帧，isLoaded 翻 true")
    func notesLoadedOnFirstFrame() async throws {
        let model = MainNotesModel(observeNotes: { oneShot([]) })
        #expect(!model.isLoaded)
        await model.runNotes(oneShot([NoteListItem]()))
        #expect(model.isLoaded)
    }

    @Test("便签模型：流挂起（首帧未到）期间 isLoaded 保持 false；推帧后翻 true")
    func notesLoadedStaysFalseWhilePending() async throws {
        var continuation: AsyncThrowingStream<[NoteListItem], any Error>.Continuation!
        let stream = AsyncThrowingStream<[NoteListItem], any Error> { continuation = $0 }
        let model = MainNotesModel(observeNotes: { stream })
        let task = Task { await model.runNotes(stream) }
        try await settle()
        #expect(!model.isLoaded)
        continuation.yield([NoteListItem]())
        try await settle()
        #expect(model.isLoaded)
        continuation.finish()
        await task.value
    }

    @Test("便签模型：流失败（读取失败收尾）同样翻转 isLoaded，不停在假空态")
    func notesLoadedFlipsOnFailure() async throws {
        let model = MainNotesModel(observeNotes: { failing() })
        await model.runNotes(failing())
        #expect(model.isLoaded)
    }

    // - MARK: MainTodosModel

    @Test("待办模型：空数组帧即首帧，isLoaded 翻 true")
    func todosLoadedOnFirstFrame() async throws {
        let model = MainTodosModel()
        #expect(!model.isLoaded)
        await model.runTodos(oneShot([Todo]()))
        #expect(model.isLoaded)
    }

    @Test("待办模型：流失败（读取失败收尾）同样翻转 isLoaded")
    func todosLoadedFlipsOnFailure() async throws {
        let model = MainTodosModel()
        await model.runTodos(failing())
        #expect(model.isLoaded)
    }

    // - MARK: TrashModel

    @Test("回收站模型：两个流都交付首帧才置 isLoaded（单流先到仍 false）")
    func trashLoadedNeedsBothFirstFrames() async throws {
        let model = TrashModel()
        var notesContinuation: AsyncThrowingStream<[Note], any Error>.Continuation!
        var todosContinuation: AsyncThrowingStream<[Todo], any Error>.Continuation!
        model.observeNotes = { AsyncThrowingStream { notesContinuation = $0 } }
        model.observeTodos = { AsyncThrowingStream { todosContinuation = $0 } }
        model.start()
        defer { model.stop() }
        try await settle()
        #expect(!model.isLoaded)

        notesContinuation.yield([Note]())
        try await settle()
        #expect(!model.isLoaded) // 待办流未到：仍是未加载

        todosContinuation.yield([Todo]())
        try await settle()
        #expect(model.isLoaded)
    }

    @Test("回收站模型：两个流都失败收尾也翻转 isLoaded（不停在假空态）")
    func trashLoadedFlipsOnFailure() async throws {
        let model = TrashModel()
        model.observeNotes = { failing() }
        model.observeTodos = { failing() }
        model.start()
        defer { model.stop() }
        try await settle()
        #expect(model.isLoaded)
    }
}
