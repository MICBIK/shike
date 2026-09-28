// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 1.10：PanelModel 消费观察流与提示条（app-shell.md「L2 测试清单」）。
@MainActor
struct PanelModelDataTests {
    private func makeModel(database: AppDatabase) -> (PanelModel, NoteRepository, TodoRepository, () -> Void) {
        let noteRepository = NoteRepository(database: database)
        let todoRepository = TodoRepository(database: database)
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
        let model = PanelModel(noteRepository: noteRepository, todoRepository: todoRepository, preferences: preferences)
        return (model, noteRepository, todoRepository, { UserDefaults.standard.removePersistentDomain(forName: suiteName) })
    }

    /// 轮询等待观察流把变化送到模型（主线程 Task.sleep 让出主执行器）。
    private func waitFor(
        _ condition: @autoclosure () -> Bool,
        timeout: TimeInterval = 2,
        _ message: String = ""
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(condition(), "\(message)（等待超时）")
    }

    @Test("空库：两种列表都为空（02 验收第 4 条）")
    func emptyDatabaseYieldsEmptyLists() async throws {
        let (model, _, _, cleanup) = makeModel(database: try AppDatabase.inMemory())
        defer { cleanup() }
        model.start()
        // 给观察流留出首轮投递时间，确认空库不产生任何条目
        try await Task.sleep(for: .milliseconds(120))
        #expect(model.notes.isEmpty)
        #expect(model.todos.isEmpty)
        model.stop()
    }

    @Test("插入便签后 notes 随之更新（写入到观察链路）")
    func notesUpdateAfterInsert() async throws {
        let (model, noteRepository, _, cleanup) = makeModel(database: try AppDatabase.inMemory())
        defer { cleanup() }
        model.start()

        let note = try await noteRepository.create(content: "面板可见的便签")
        try await waitFor(model.notes.contains { $0.id == note.id }, "插入后 notes 未更新")
        model.stop()
    }

    @Test("writeFailed 提示条：保存失败：磁盘空间不足 + 重试调用传入闭包")
    func writeFailedBannerAndRetry() {
        let (model, _, _, cleanup) = makeModel(database: try! AppDatabase.inMemory())
        defer { cleanup() }
        var retried = false
        model.report(.writeFailed(.diskFull), retry: { retried = true })

        #expect(model.banner?.message == "保存失败：磁盘空间不足")
        model.retryBanner()
        #expect(retried)
    }

    @Test("观察流真实以 readFailed(.ioError) 结束：提示条出现，重试重新订阅并清除")
    func realStreamFailureEndToEnd() async throws {
        let (model, noteRepository, _, cleanup) = makeModel(database: try AppDatabase.inMemory())
        defer { cleanup() }

        // 让一个真实的观察流以 readFailed 结束（走 for try await → handleStreamFailure → report 全链路）
        let failing = AsyncThrowingStream<[NoteListItem], any Error> { $0.finish(throwing: ShikeDataError.readFailed(.ioError)) }
        await model.runNotes(failing)
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")

        // 点"重试"（与提示条按钮相同的入口）= start() 重新订阅真实仓储
        model.retryBanner()
        let note = try await noteRepository.create(content: "重订阅后的便签")
        try await waitFor(model.notes.contains { $0.id == note.id }, "重试后未重新订阅")
        try await waitFor(model.banner == nil, "重新订阅成功后未清除读取失败提示条")
        model.stop()
    }

    @Test("非 ShikeDataError 的流错误按读取失败（ioError）上报")
    func unknownStreamErrorMappedToReadFailed() async {
        let (model, _, _, cleanup) = makeModel(database: try! AppDatabase.inMemory())
        defer { cleanup() }
        struct ForeignError: Error {}
        let failing = AsyncThrowingStream<[NoteListItem], any Error> { $0.finish(throwing: ForeignError()) }
        await model.runNotes(failing)
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
    }

    @Test("另一条流的更新不会误清读取失败提示条（重订阅前）")
    func otherStreamUpdateDoesNotClearLoadBanner() async throws {
        let (model, _, _, cleanup) = makeModel(database: try AppDatabase.inMemory())
        defer { cleanup() }

        let failing = AsyncThrowingStream<[NoteListItem], any Error> { $0.finish(throwing: ShikeDataError.readFailed(.ioError)) }
        await model.runNotes(failing)
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")

        // 待办流仍在运行并投递数据（yield 后不结束），不得清掉便签流的读取失败提示条
        let running = AsyncThrowingStream<[Todo], any Error> { $0.yield([]) }
        let task = Task { await model.runTodos(running) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
        task.cancel()
    }

    @Test("提示条文案与文案表逐字一致")
    func bannerMessageWording() {
        let (model, _, _, cleanup) = makeModel(database: try! AppDatabase.inMemory())
        defer { cleanup() }
        model.report(.writeFailed(.diskFull), retry: {})
        #expect(model.banner?.message == "保存失败：磁盘空间不足")

        model.report(.readFailed(.ioError), retry: {})
        #expect(model.banner?.message == "读取失败：读写数据文件时出错")
    }
}
