// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Note/Todo 的 memberwise init 是 internal（包内约定）

/// 主窗口集成接线表（S3.5 集成，MainWindowController.init 的闭包装配）：
/// 便签/待办动作经 PanelModel 同语义落库（清空=删除入撤销栈、完成清提醒）、
/// 回收站写路径接真实 TrashRepository 且失败转 main.trash.failed、
/// 编辑/设置时间呼出面板并沿面板行为。只构造控制器不开窗（init 仅闭包赋值），
/// 环境同既有 L2：内存库 + 独立 UserDefaults suite。
@MainActor
struct MainWindowWiringTests {
    private func makeEnvironment(simulateWriteFailure: Bool = false) throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let database = simulateWriteFailure
            ? try AppDatabase.inMemory(options: AppDatabase.Options(simulateWriteFailure: true))
            : try AppDatabase.inMemory()
        let environment = AppEnvironment(
            database: database,
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-main-wiring-\(UUID().uuidString)", isDirectory: true)
        )
        return (environment, suiteName)
    }

    /// 写操作落库后新建观察流取首帧（首帧即当前全量）。
    private func activeNotes(_ environment: AppEnvironment) async throws -> [NoteListItem] {
        var iterator = environment.noteRepository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func activeTodos(_ environment: AppEnvironment) async throws -> [Todo] {
        var iterator = environment.todoRepository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func deletedNotes(_ environment: AppEnvironment) async throws -> [Note] {
        var iterator = environment.trashRepository.observeNotes().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    private func deletedTodos(_ environment: AppEnvironment) async throws -> [Todo] {
        var iterator = environment.trashRepository.observeTodos().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    /// 一次性流（播种面板快照用）：runNotes 消费完即返回。
    private func oneShotNotes(_ items: [NoteListItem]) -> AsyncThrowingStream<[NoteListItem], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 一次性流（播种面板待办快照用）：runTodos 消费完即返回。
    private func oneShotTodos(_ items: [Todo]) -> AsyncThrowingStream<[Todo], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 轮询直到 async 条件成立或超时（写路径是 fire-and-forget Task，无可等待句柄）。
    private func waitUntil(
        _ label: String,
        timeoutSeconds: Double = 2,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("等待超时：\(label)")
    }

    // - MARK: 回收站接线

    @Test("接线：回收站写路径接真实 TrashRepository——恢复回 active、永久删除消失、反馈为成功文案")
    func trashClosuresHitTrashRepository() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let model = controller.trashModel
        model.statusHideDelay = .seconds(60) // 防 3 秒自清干扰断言
        model.start()
        defer { model.stop() }

        let note = try await environment.noteRepository.create(content: "回收便签")
        let todo = try await environment.todoRepository.create(title: "回收待办", due: nil)
        try await environment.noteRepository.softDelete(note.id)
        try await environment.todoRepository.softDelete(todo.id)
        try await waitUntil("回收站两流就位") {
            !model.deletedNotes.isEmpty && !model.deletedTodos.isEmpty
        }

        // 恢复便签：写路径落库（回收站清空、active 重现）+ 默认成功文案
        await model.requestRestoreNote(note.id)
        try await waitUntil("便签恢复") { model.deletedNotes.isEmpty }
        let activeAfterRestore = try await activeNotes(environment)
        #expect(activeAfterRestore.map(\.id) == [note.id])
        #expect(model.statusMessage == String(localized: .mainTrashRestored("便签")))

        // 永久删除待办：走确认状态机 → 真实仓储
        model.requestDeleteTodo(todo.id)
        await model.confirm()
        try await waitUntil("待办消失") { model.deletedTodos.isEmpty }
        let activeAfterDelete = try await activeTodos(environment)
        #expect(activeAfterDelete.isEmpty)
        #expect(model.statusMessage == String(localized: .mainTrashPermanentlyDeleted("待办")))
    }

    @Test("接线：回收站写路径失败转 main.trash.failed（simulateWriteFailure 与 notFound 两类），默认成功文案不覆盖")
    func trashFailureShowsFailedMessage() async throws {
        let (environment, suiteName) = try makeEnvironment(simulateWriteFailure: true)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let model = controller.trashModel
        model.statusHideDelay = .seconds(60)

        // 写必抛（统一写路径失败）：清空走确认后收到失败文案而非"已清空回收站"
        model.requestEmptyAll()
        await model.confirm()
        #expect(model.statusMessage == String(localized: .mainTrashFailed))
        // 统一反馈条同文案（W3 双通道：分区内部展示照旧 + 底部反馈条）
        #expect(controller.feedback.message == String(localized: .mainTrashFailed))
        #expect(model.confirmTarget == nil)

        // notFound（幽灵 id）同样经 catch 转失败文案
        await model.requestRestoreNote(Note.ID(rawValue: 9999))
        #expect(model.statusMessage == String(localized: .mainTrashFailed))
    }

    // - MARK: 统一反馈（W3）

    @Test("接线：面板写失败旁路主窗口——simulateWriteFailure 路径统一反馈条出现（真机 -ShikeSimulateWriteFailure）")
    func writeFailureBypassShowsMainFeedback() async throws {
        let (environment, suiteName) = try makeEnvironment(simulateWriteFailure: true)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let panelModel = environment.panelModel
        // 开了 simulateWriteFailure 后一切写都抛：种子用 memberwise 直构（不落库——
        // 只需要面板快照里有这一行，saveNoteContent 的未变跳过/清空删除守卫按快照走）。
        let now = Date()
        let seeded = Note(
            id: Note.ID(rawValue: 1),
            uuid: UUID(),
            content: "写失败种子",
            pinnedAt: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: seeded, isPinnedToDesktop: false)]))

        // 经面板语义保存（fire-and-forget Task）→ 写失败 → report 旁路 → 统一反馈条
        controller.notesModel.saveNoteContent(seeded.id, "新内容")
        try await waitUntil("主窗口反馈条出现") {
            controller.feedback.message != nil
        }
        #expect(controller.feedback.message == String(localized: .bannerSaveFailed(ErrorText.reason(.simulated))))
    }

    @Test("接线：读失败回调触发主窗口统一反馈（数据读取失败）")
    func readFailureShowsMainFeedback() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let failing = AsyncThrowingStream<[NoteListItem], any Error> { $0.finish(throwing: ShikeDataError.readFailed(.ioError)) }
        await controller.notesModel.runNotes(failing)
        #expect(controller.feedback.message == String(localized: .mainReadFailed))
    }

    @Test("统一反馈条：3 秒自清（注入缩短），连续 show 重启计时")
    func mainFeedbackAutoClears() async throws {
        let feedback = MainFeedbackModel()
        feedback.hideDelay = .milliseconds(80)
        feedback.show("第一条")
        #expect(feedback.message == "第一条")
        try await Task.sleep(for: .milliseconds(40))
        feedback.show("第二条") // 重启计时
        try await Task.sleep(for: .milliseconds(40))
        #expect(feedback.message == "第二条") // 距第一条 80ms：未被清（计时已重启）
        try await Task.sleep(for: .milliseconds(100))
        #expect(feedback.message == nil)
    }

    // - MARK: 便签接线

    @Test("接线：便签动作接 PanelModel 同语义——保存更新、清空=删除入回收站、置顶/删除直达仓储")
    func notesClosuresHitPanelModelSemantics() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel
        // 播种面板快照：panelModel.saveNoteContent 的未变跳过/清空=删除按 notes.first 守卫
        let seeded = try await environment.noteRepository.create(content: "原文")
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: seeded, isPinnedToDesktop: false)]))

        let controller = MainWindowController(environment: environment)

        // 保存新内容 → panelModel.updateContent 落库
        controller.notesModel.saveNoteContent(seeded.id, "新内容")
        try await waitUntil("内容更新") {
            try await self.activeNotes(environment).first?.note.content == "新内容"
        }

        // 清空=删除（软删除入回收站；撤销语义在面板）
        controller.notesModel.saveNoteContent(seeded.id, "")
        try await waitUntil("清空删除") {
            let active = try await self.activeNotes(environment)
            guard active.isEmpty else { return false }
            return !(try await self.deletedNotes(environment)).isEmpty
        }

        // 置顶/删除直达仓储
        let second = try await environment.noteRepository.create(content: "第二条")
        controller.notesModel.setNotePinned(second.id, true)
        try await waitUntil("置顶") {
            try await self.activeNotes(environment).first(where: { $0.id == second.id })?.note.pinnedAt != nil
        }
        controller.notesModel.deleteNote(second.id)
        try await waitUntil("删除") {
            try await self.activeNotes(environment).allSatisfy { $0.id != second.id }
        }
    }

    // - MARK: 待办接线

    @Test("接线：待办动作接 PanelModel 同语义——完成走三态落库并清 snoozedUntil（ADR-017）、删除入回收站")
    func todosClosuresHitPanelModelSemantics() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        // 勾选接面板三态（1 秒待移入），测试缩短计时窗
        environment.panelModel.completionDelay = .milliseconds(50)
        let todo = try await environment.todoRepository.create(title: "接线待办", due: nil)
        let snoozed = Date().addingTimeInterval(3600)
        _ = try await environment.todoRepository.snooze(uuid: todo.uuid, until: snoozed)

        // 完成：toggleTodoCompletion 待移入到期 → setTodoCompleted 落库 + 清 snoozedUntil
        controller.todosModel.toggleComplete(todo.id, true)
        try await waitUntil("完成清稍后") {
            guard let item = try await self.activeTodos(environment).first(where: { $0.id == todo.id }) else {
                return false
            }
            return item.completedAt != nil && item.snoozedUntil == nil
        }

        // 删除：软删除入回收站
        controller.todosModel.delete(todo.id)
        try await waitUntil("删除") {
            let active = try await self.activeTodos(environment)
            guard active.isEmpty else { return false }
            return !(try await self.deletedTodos(environment)).isEmpty
        }
    }

    @Test("接线：编辑/设置时间呼出面板并沿面板行为（行内编辑/时间弹层/定位高亮）；未知 id 静默忽略")
    func editAndSetTimeOpenPanelWithPanelBehavior() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let todo = try await environment.todoRepository.create(title: "目标待办", due: nil)
        let model = controller.todosModel
        model.observeTodos = { environment.todoRepository.observeActive() }
        model.start()
        defer { model.stop() }
        try await waitUntil("主窗口快照就位") { !model.todos.isEmpty }

        var panelOpened = 0
        controller.openPanelHandler = { panelOpened += 1 }

        // 编辑：呼出面板 + 行内编辑态播种 + 定位高亮
        model.edit(todo.id)
        #expect(panelOpened == 1)
        #expect(environment.panelModel.editingTodoID == todo.id)
        #expect(environment.panelModel.editingTodoText == "目标待办")
        #expect(environment.panelModel.locateTodoID == todo.uuid.uuidString)

        // 设置时间：先收尾编辑态（endEditingIfNeeded），再弹时间层
        model.setTime(todo.id)
        #expect(panelOpened == 2)
        #expect(environment.panelModel.editingTodoID == nil)
        #expect(environment.panelModel.editingTimeTarget?.id == todo.id)

        // 未知 id：不呼出、面板状态不变
        model.edit(Todo.ID(rawValue: 9999))
        #expect(panelOpened == 2)
        #expect(environment.panelModel.editingTimeTarget?.id == todo.id)
    }

    @Test("导出文件名日期：yyyy-MM-dd 按注入时区（en_US_POSIX 固定字段序）")
    func exportFileDateUsesInjectedTimeZone() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 1
        components.hour = 20 // 纽约 10-01 20:00 = UTC 10-02 00:00，钉住时区而非 UTC
        let date = calendar.date(from: components)!

        #expect(MainWindowController.fileDate(date, timeZone: TimeZone(identifier: "America/New_York")!) == "2026-10-01")
        #expect(MainWindowController.fileDate(date, timeZone: TimeZone(identifier: "Asia/Shanghai")!) == "2026-10-02")
    }

    // - MARK: 主窗口删除反馈与撤销（打磨二轮卡B，03 §16.8）

    @Test("删除反馈：主窗口删便签→反馈条出现已删除文案+撤销，撤销恢复落库并收条")
    func noteDeleteShowsFeedbackWithUndoAndRestores() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel
        let controller = MainWindowController(environment: environment)
        // 面板快照播种（deleteNote 的摘要按面板快照取；反馈文案复用撤销条同款截断）
        let note = try await environment.noteRepository.create(content: "主窗口删除反馈")
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        controller.notesModel.deleteNote(note.id)
        try await waitUntil("删除反馈出现") {
            controller.feedback.message == String(localized: .undoBarDeleted("主窗口删除反馈"))
        }
        guard case .undo? = controller.feedback.action else {
            Issue.record("删除反馈应携带撤销动作")
            return
        }

        // 撤销：调面板同一撤销栈，恢复落库，反馈条收起
        controller.feedback.performAction()
        try await waitUntil("撤销恢复") {
            try await self.activeNotes(environment).map(\.id) == [note.id]
        }
        #expect(controller.feedback.message == nil)
        #expect(controller.feedback.action == nil)
    }

    @Test("删除反馈：清空保存=删除同样带撤销（主窗口清空便签不再无感）；普通编辑不出删除反馈")
    func clearToDeleteShowsDeletionFeedbackWithUndo() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel
        let controller = MainWindowController(environment: environment)
        let note = try await environment.noteRepository.create(content: "清空即删除的便签")
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        // 普通编辑（非删除）不得触发删除反馈：先改内容，反馈条应保持为空
        controller.notesModel.saveNoteContent(note.id, "改了内容")
        try await Task.sleep(for: .milliseconds(80))
        #expect(controller.feedback.message == nil)

        // 清空保存=删除：反馈条出现已删除文案（摘要为删除前内容）
        controller.notesModel.saveNoteContent(note.id, "")
        try await waitUntil("清空删除反馈出现") {
            controller.feedback.message == String(localized: .undoBarDeleted("清空即删除的便签"))
        }
        guard case .undo? = controller.feedback.action else {
            Issue.record("清空删除反馈应携带撤销动作")
            return
        }

        controller.feedback.performAction()
        // 恢复的是最后一次落库内容（先改内容再清空，软删除发生在"改了内容"的行上）；
        // 这里只断言回到活跃流（原文完整断言归属 DeleteUndoTests 的面板语义）。
        try await waitUntil("撤销恢复") {
            try await self.activeNotes(environment).map(\.id) == [note.id]
        }
        #expect(controller.feedback.message == nil)
    }

    @Test("删除反馈：撤销定点恢复条上所指条目——5 秒窗口内面板另删别的条目时不再错恢复栈顶（卡C 审查修复）")
    func undoRestoresTheItemTheBarNamesNotStackTop() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel
        let controller = MainWindowController(environment: environment)
        let note = try await environment.noteRepository.create(content: "主窗口删的便签")
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))
        let otherTodo = try await environment.todoRepository.create(title: "面板后删的待办", due: nil)
        await panelModel.runTodos(oneShotTodos([otherTodo]))

        // 主窗口删便签 → 条面"已删除「主窗口删的便签」"
        controller.notesModel.deleteNote(note.id)
        try await waitUntil("删除反馈出现") {
            controller.feedback.message == String(localized: .undoBarDeleted("主窗口删的便签"))
        }
        // 5 秒窗口内面板又删了另一条（栈顶易主）
        await panelModel.deleteTodo(otherTodo.id)
        #expect(panelModel.deletedStack.count == 2)

        // 主窗口条撤销：恢复条上所指的便签，而不是栈顶的待办
        controller.feedback.performAction()
        try await waitUntil("定点恢复便签") {
            try await self.activeNotes(environment).map(\.id) == [note.id]
        }
        let activeTodosAfterUndo = try await activeTodos(environment)
        #expect(activeTodosAfterUndo.isEmpty) // 待办仍在回收站（未被误恢复）
        #expect(controller.feedback.message == nil)
    }

    @Test("删除反馈：面板编辑态中主窗口撤销仍可达（显式点击不受 ⌘Z 键路径守卫约束）")
    func mainWindowUndoReachableWhilePanelEditing() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel
        let controller = MainWindowController(environment: environment)
        let note = try await environment.noteRepository.create(content: "编辑态中删的便签")
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        controller.notesModel.deleteNote(note.id)
        try await waitUntil("删除反馈出现") {
            controller.feedback.message != nil
        }

        // 面板行编辑态 + 快速输入框焦点态：⌘Z 会被守卫让路（既有语义），显式按钮不得
        panelModel.editingNoteID = note.id
        panelModel.isCaptureFocused = true
        #expect(panelModel.undoLastDeleteIfNeeded() == false) // 键盘路径仍被仲裁

        controller.feedback.performAction()
        try await waitUntil("编辑态下定点恢复") {
            try await self.activeNotes(environment).map(\.id) == [note.id]
        }
        #expect(controller.feedback.message == nil)
    }

    @Test("删除反馈：主窗口删待办同样带撤销，撤销后待办回活跃流")
    func todoDeleteShowsFeedbackWithUndoAndRestores() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel
        let controller = MainWindowController(environment: environment)
        let todo = try await environment.todoRepository.create(title: "主窗口删的待办", due: nil)
        await panelModel.runTodos(oneShotTodos([todo]))

        controller.todosModel.delete(todo.id)
        try await waitUntil("待办删除反馈出现") {
            controller.feedback.message == String(localized: .undoBarDeleted("主窗口删的待办"))
        }
        guard case .undo? = controller.feedback.action else {
            Issue.record("待办删除反馈应携带撤销动作")
            return
        }

        controller.feedback.performAction()
        try await waitUntil("待办撤销恢复") {
            try await self.activeTodos(environment).map(\.id) == [todo.id]
        }
        #expect(controller.feedback.message == nil)
    }

    @Test("删除反馈：删除失败不出已删除文案——写失败旁路反馈带重试动作（复用面板重试闭包）")
    func failedDeleteShowsRetryNotDeleted() async throws {
        let (environment, suiteName) = try makeEnvironment(simulateWriteFailure: true)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let controller = MainWindowController(environment: environment)
        let panelModel = environment.panelModel
        // 写必抛：种子 memberwise 直构（只需面板快照里有这一行）
        let now = Date()
        let seeded = Note(
            id: Note.ID(rawValue: 1),
            uuid: UUID(),
            content: "删不掉的便签",
            pinnedAt: nil,
            createdAt: now,
            updatedAt: now,
            deletedAt: nil
        )
        await panelModel.runNotes(oneShotNotes([NoteListItem(note: seeded, isPinnedToDesktop: false)]))

        controller.notesModel.deleteNote(seeded.id)
        try await waitUntil("写失败旁路反馈出现") {
            controller.feedback.message != nil
        }
        #expect(controller.feedback.message == String(localized: .bannerSaveFailed(ErrorText.reason(.simulated))))
        guard case .retry? = controller.feedback.action else {
            Issue.record("写失败反馈应携带重试动作")
            return
        }
        // 撤销栈未变（软删除没成功）：绝不出"已删除"文案与撤销动作
        #expect(panelModel.deletedStack.isEmpty)
    }

    @Test("反馈条动作：撤销用 5 秒窗口、重试用 3 秒窗口（注入缩短区分），perform 收条并执行")
    func feedbackActionDelaysAndPerform() async throws {
        let feedback = MainFeedbackModel()
        feedback.hideDelay = .seconds(2)
        feedback.undoHideDelay = .milliseconds(80)

        var undoCount = 0
        feedback.show("已删除「x」", action: .undo { undoCount += 1 })
        try await Task.sleep(for: .milliseconds(40))
        #expect(feedback.message == "已删除「x」") // 80ms 窗口内仍在
        try await Task.sleep(for: .milliseconds(80))
        #expect(feedback.message == nil) // 走撤销窗口（若误用 2 秒通道此处不成立）
        #expect(feedback.action == nil) // 隐藏时动作一并清除

        // perform：先收条再执行
        var retryCount = 0
        feedback.show("保存失败：x", action: .retry { retryCount += 1 })
        guard case .retry? = feedback.action else {
            Issue.record("应携带重试动作")
            return
        }
        feedback.performAction()
        #expect(retryCount == 1)
        #expect(feedback.message == nil)
        #expect(feedback.action == nil)

        // 纯文案：无动作，perform 空操作
        feedback.show("导出完成")
        #expect(feedback.action == nil)
        feedback.performAction()
        #expect(feedback.message == "导出完成")
    }
}
