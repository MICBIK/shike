// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // NoteListItem 的 memberwise init 是 internal（包内约定）

/// 退出冲刷（W1 数据安全）：⌘Q 时三面在编辑内容同步落库。
/// 核心断言口径：调同步冲刷后**不等任何 Task** 直接读库断言行已更新；
/// 空内容→软删除、未变跳过（updatedAt 不动）、慢任务短超时不永久阻塞。
@MainActor
struct ExitFlushTests {
    /// 线程安全的递增时钟（模式同 ShikeDataTests.TransactionClockTests）：每次调用
    /// 前进 60 秒——任何真实写入都会产生严格更晚的 updatedAt，「未变跳过」才能用
    /// updatedAt 不动来证明（默认时钟 Date() 带亚毫秒，GRDB 毫秒精度存取截断，
    /// 等值断言不可靠；整秒基点保证存取往返无损）。
    private final class TickingClock: @unchecked Sendable {
        private let lock = NSLock()
        private var base = Date(timeIntervalSince1970: 1_789_999_999)

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            base = base.addingTimeInterval(60)
            return base
        }
    }

    private func makeEnvironment(database: (AppDatabase, String)? = nil) throws -> (AppEnvironment, String) {
        let suiteName = database?.1 ?? "shike-tests-\(UUID().uuidString)"
        let environment = AppEnvironment(
            database: try database?.0 ?? AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-exit-flush-\(UUID().uuidString)", isDirectory: true)
        )
        return (environment, suiteName)
    }

    /// 递增时钟内存库（「未变跳过」用例专用）。
    private func makeTickingEnvironment() throws -> (AppEnvironment, String, TickingClock) {
        let clock = TickingClock()
        let database = try AppDatabase.inMemory(options: .init(clock: { clock.now() }))
        let (environment, suiteName) = try makeEnvironment(database: (database, "shike-tests-\(UUID().uuidString)"))
        return (environment, suiteName, clock)
    }

    /// 一次性流（播种模型快照用）：runNotes/runTodos 消费完即返回。
    private func oneShotNotes(_ items: [NoteListItem]) -> AsyncThrowingStream<[NoteListItem], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    private func oneShotTodos(_ items: [Todo]) -> AsyncThrowingStream<[Todo], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 写操作落库后新建观察流取首帧（首帧即当前全量）。
    private func activeNotes(_ environment: AppEnvironment) async throws -> [NoteListItem] {
        var iterator = environment.noteRepository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func deletedNotes(_ environment: AppEnvironment) async throws -> [Note] {
        var iterator = environment.trashRepository.observeNotes().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func activeTodos(_ environment: AppEnvironment) async throws -> [Todo] {
        var iterator = environment.todoRepository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    // - MARK: SyncFlush 本体

    @Test("SyncFlush：任务在超时内完成后返回即已落库（不等任何 Task 直接断言）")
    func syncFlushWritesBeforeReturning() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "冲刷前")
        let repository = environment.noteRepository

        SyncFlush.perform {
            try? await repository.updateContent(note.id, to: "冲刷后")
        }
        // perform 返回即写完：此处不 await 任何冲刷任务，读库直接断言。
        let rows = try await activeNotes(environment)
        #expect(rows.first?.note.content == "冲刷后")
    }

    @Test("SyncFlush：慢任务短超时放弃等待，不永久阻塞")
    func syncFlushGivesUpOnTimeout() {
        let start = Date()
        SyncFlush.perform(timeout: .milliseconds(100)) {
            try? await Task.sleep(for: .seconds(5))
        }
        let elapsed = Date().timeIntervalSince(start)
        #expect(elapsed < 2)
    }

    @Test("SyncFlush.noteContent：未变跳过（updatedAt 不动）、变化落库（updatedAt 前进）、行不在快照兜底直写（C4 对齐）")
    func noteContentSkipsUnchangedAndMissing() async throws {
        let (environment, suiteName, _) = try makeTickingEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "原文")

        // 未变（快照内容 == 文字）：跳过——updatedAt 严格不动
        SyncFlush.noteContent(note.id, text: "原文", snapshotContent: "原文", repository: environment.noteRepository)
        var rows = try await activeNotes(environment)
        #expect(rows.first?.note.content == "原文")
        #expect(rows.first?.note.updatedAt == note.updatedAt)

        // 变化：落库——updatedAt 前进（证明上一条断言真的能探测写入）
        SyncFlush.noteContent(note.id, text: "换了文字", snapshotContent: "原文", repository: environment.noteRepository)
        rows = try await activeNotes(environment)
        #expect(rows.first?.note.content == "换了文字")
        #expect(rows.first!.note.updatedAt > note.updatedAt)

        // 行不在快照（nil）：兜底直写（打磨 2026-10-03，C4 对齐——在线保存已直写，
        // 冲刷静默跳过=最后一次编辑无声丢失；此前为跳过语义）
        SyncFlush.noteContent(note.id, text: "又改", snapshotContent: nil, repository: environment.noteRepository)
        rows = try await activeNotes(environment)
        #expect(rows.first?.note.content == "又改")
    }

    @Test("SyncFlush.noteContent：行不在快照且空内容→软删除（幂等静默）")
    func noteContentMissingSnapshotEmptySoftDeletes() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "快照外清空")

        // 行健在：软删除落库
        SyncFlush.noteContent(note.id, text: "  ", snapshotContent: nil, repository: environment.noteRepository)
        #expect(try await activeNotes(environment).isEmpty)
        #expect(try await deletedNotes(environment).map(\.id) == [note.id])

        // 行已删除：幂等（softDelete 返回 false 静默，不抛错）
        SyncFlush.noteContent(note.id, text: "", snapshotContent: nil, repository: environment.noteRepository)
        #expect(try await deletedNotes(environment).map(\.id) == [note.id])
    }

    @Test("SyncFlush.noteContent：空内容→软删除入回收站")
    func noteContentEmptySoftDeletes() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "将被清空")

        SyncFlush.noteContent(note.id, text: "   ", snapshotContent: "将被清空", repository: environment.noteRepository)
        #expect(try await activeNotes(environment).isEmpty)
        #expect(try await deletedNotes(environment).map(\.id) == [note.id])
    }

    @Test("SyncFlush.todoTitle：变化落库；空标题不保存（回退原标题）；未变 updatedAt 不动；行不在快照兜底直写")
    func todoTitleFlushSemantics() async throws {
        let (environment, suiteName, _) = try makeTickingEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let todo = try await environment.todoRepository.create(title: "原标题", due: nil)

        // 变化：落库
        SyncFlush.todoTitle(todo.id, text: "新标题", snapshotTitle: "原标题", repository: environment.todoRepository)
        var rows = try await activeTodos(environment)
        #expect(rows.first?.title == "新标题")
        #expect(rows.first!.updatedAt > todo.updatedAt)

        // 空标题（trim 后空）：不保存
        SyncFlush.todoTitle(todo.id, text: "   ", snapshotTitle: "新标题", repository: environment.todoRepository)
        rows = try await activeTodos(environment)
        #expect(rows.first?.title == "新标题")

        // 未变：跳过——updatedAt 严格不动
        let beforeSkip = try await activeTodos(environment).first!.updatedAt
        SyncFlush.todoTitle(todo.id, text: "新标题", snapshotTitle: "新标题", repository: environment.todoRepository)
        rows = try await activeTodos(environment)
        #expect(rows.first?.title == "新标题")
        #expect(rows.first?.updatedAt == beforeSkip)

        // 行不在快照（nil）且非空：兜底直写（C4 对齐）；空标题仍回退不保存
        SyncFlush.todoTitle(todo.id, text: "快照外的新标题", snapshotTitle: nil, repository: environment.todoRepository)
        rows = try await activeTodos(environment)
        #expect(rows.first?.title == "快照外的新标题")
        SyncFlush.todoTitle(todo.id, text: "  ", snapshotTitle: nil, repository: environment.todoRepository)
        rows = try await activeTodos(environment)
        #expect(rows.first?.title == "快照外的新标题")
    }

    // - MARK: 面板（PanelModel）

    @Test("面板退出冲刷：在编辑便签同步落库（返回即已写），编辑态复位")
    func panelFlushWritesNoteImmediately() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let note = try await environment.noteRepository.create(content: "面板原文")
        await model.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        model.editingNoteID = note.id
        model.editingNoteText = "面板改过的文字"
        model.flushPendingEditsSynchronously()

        let rows = try await activeNotes(environment)
        #expect(rows.first?.note.content == "面板改过的文字")
        #expect(model.editingNoteID == nil)
        #expect(model.editingNoteText == "")
    }

    @Test("面板退出冲刷：空内容→软删除入回收站；未变跳过（updatedAt 不动）")
    func panelFlushNoteEmptyAndUnchanged() async throws {
        let (environment, suiteName, _) = try makeTickingEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let note = try await environment.noteRepository.create(content: "清空我")
        await model.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        // 未变：跳过——updatedAt 严格不动
        model.editingNoteID = note.id
        model.editingNoteText = "清空我"
        model.flushPendingEditsSynchronously()
        #expect(try await activeNotes(environment).first?.note.updatedAt == note.updatedAt)

        // 空内容：软删除
        model.editingNoteID = note.id
        model.editingNoteText = "  \n "
        model.flushPendingEditsSynchronously()
        #expect(try await activeNotes(environment).isEmpty)
        #expect(try await deletedNotes(environment).map(\.id) == [note.id])
    }

    @Test("面板退出冲刷：在编辑待办标题同步落库；空标题不保存")
    func panelFlushWritesTodoTitle() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let todo = try await environment.todoRepository.create(title: "面板原标题", due: nil)
        await model.runTodos(oneShotTodos([todo]))

        model.editingTodoID = todo.id
        model.editingTodoText = "面板新标题"
        model.flushPendingEditsSynchronously()
        var rows = try await activeTodos(environment)
        #expect(rows.first?.title == "面板新标题")

        // 空标题：不保存（回退原标题）
        model.editingTodoID = todo.id
        model.editingTodoText = "   "
        model.flushPendingEditsSynchronously()
        rows = try await activeTodos(environment)
        #expect(rows.first?.title == "面板新标题")
    }

    @Test("面板退出冲刷：面板流失败（行不在快照）时兜底直写，编辑不静默丢失（C4 对齐）")
    func panelFlushWritesThroughWhenRowAbsentFromSnapshot() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let note = try await environment.noteRepository.create(content: "面板看不到的便签")
        let todo = try await environment.todoRepository.create(title: "面板看不到的待办", due: nil)
        // 空快照一次性流 = 面板观察流已失败（runNotes 语义）：行健在、面板快照没有
        await model.runNotes(oneShotNotes([]))
        await model.runTodos(oneShotTodos([]))

        // 便签：编辑态可以来自流失败前的残留（beginNoteEditing 不依赖快照）
        model.beginNoteEditing(note.id, content: note.content)
        model.editingNoteText = "流失败期间的最后一次编辑"
        // 待办：直接置编辑态（同面板行编辑的落点）
        model.editingTodoID = todo.id
        model.editingTodoText = "流失败期间的新标题"

        model.flushPendingEditsSynchronously()

        #expect(try await activeNotes(environment).first(where: { $0.note.id == note.id })?.note.content == "流失败期间的最后一次编辑")
        #expect(try await activeTodos(environment).first(where: { $0.id == todo.id })?.title == "流失败期间的新标题")
        #expect(model.editingNoteID == nil)
        #expect(model.editingTodoID == nil)
    }

    // - MARK: 主窗口（MainNotesModel + MainWindowController）

    @Test("主窗口：takePendingEdit 返回快照并复位编辑态；再取为 nil（幂等）")
    func takePendingEditReturnsSnapshotAndResets() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let note = try await environment.noteRepository.create(content: "主窗口原文")
        await controller.notesModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        controller.notesModel.beginEditing(note.id)
        controller.notesModel.editingNoteText = "主窗口改过的文字"

        let edit = controller.notesModel.takePendingEdit()
        #expect(edit?.id == note.id)
        #expect(edit?.text == "主窗口改过的文字")
        #expect(edit?.snapshotContent == "主窗口原文")
        #expect(controller.notesModel.editingNoteID == nil)
        #expect(controller.notesModel.editingNoteText == "")
        // 幂等：编辑态已复位，再取为 nil
        #expect(controller.notesModel.takePendingEdit() == nil)
    }

    @Test("主窗口：endEditingIfNeeded 同步冲刷（返回即已写）；无编辑态零开销")
    func mainWindowEndEditingFlushesSynchronously() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let note = try await environment.noteRepository.create(content: "主窗口原文")
        await controller.notesModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        // 无编辑态：不写不崩
        controller.endEditingIfNeeded()
        #expect(try await activeNotes(environment).first?.note.content == "主窗口原文")

        // 编辑态：返回即已落库
        controller.notesModel.beginEditing(note.id)
        controller.notesModel.editingNoteText = "主窗口新文字"
        controller.endEditingIfNeeded()
        let rows = try await activeNotes(environment)
        #expect(rows.first?.note.content == "主窗口新文字")
        #expect(controller.notesModel.editingNoteID == nil)
    }

    @Test("主窗口：endEditingIfNeeded 空内容→软删除；未变跳过")
    func mainWindowEndEditingEmptyAndUnchanged() async throws {
        let (environment, suiteName, _) = try makeTickingEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let note = try await environment.noteRepository.create(content: "主窗口清空我")
        await controller.notesModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        // 未变：跳过——updatedAt 严格不动
        controller.notesModel.beginEditing(note.id)
        controller.endEditingIfNeeded()
        #expect(try await activeNotes(environment).first?.note.updatedAt == note.updatedAt)

        // 空内容：软删除
        controller.notesModel.beginEditing(note.id)
        controller.notesModel.editingNoteText = ""
        controller.endEditingIfNeeded()
        #expect(try await activeNotes(environment).isEmpty)
        #expect(try await deletedNotes(environment).map(\.id) == [note.id])
    }
}
