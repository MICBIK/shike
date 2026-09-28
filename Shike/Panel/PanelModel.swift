// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import Observation
import os
import ShikeData
import ShikeDateParser

/// 面板状态（app-shell.md「组件契约」）：模式、两个列表的数据与提示条。
@MainActor
@Observable
final class PanelModel {
    /// 顶栏分段控件的模式（03 §3）；任何切换都持久化到 `panel.lastMode`（S1-03）。
    enum Mode: String, CaseIterable, Sendable {
        case note
        case todo
    }

    /// 呼出时进入哪个模式（S1-03，03 §9 的设置项）。
    enum OpenMode: String, CaseIterable, Sendable {
        case last
        case note
        case todo
    }

    /// 呼出决策（纯函数）：`last` 用上次的模式，其余总进设定模式（S1-03）。
    static func initialMode(openMode: OpenMode, lastMode: Mode) -> Mode {
        switch openMode {
        case .last: lastMode
        case .note: .note
        case .todo: .todo
        }
    }

    /// 顶栏下方的提示条（03 §3）；重试动作单独保存（闭包不参与相等性）。
    struct BannerState: Equatable {
        enum Kind: Equatable {
            case saveFailed(DataFailureReason)
            case loadFailed(DataFailureReason)
        }

        let kind: Kind

        var message: String {
            switch kind {
            case .saveFailed(let reason):
                String(localized: .bannerSaveFailed(ErrorText.reason(reason)))
            case .loadFailed(let reason):
                String(localized: .bannerLoadFailed(ErrorText.reason(reason)))
            }
        }
    }

    /// 模式切换（分段控件、⌘1/⌘2、Tab 均落到这里）；didSet 持久化 lastMode（S1-03），
    /// 并发出外部变更令牌——输入框在焦点态也要换显示另一模式的草稿（S1-04）。
    var mode: Mode = .note {
        didSet {
            guard mode != oldValue else { return }
            preferences.panelLastMode = mode.rawValue
            draftResetToken = UUID()
            refreshRecognition()
        }
    }
    /// 草稿被"输入框以外"的路径改变（模式切换、提交清空）的信号（S1-04）：
    /// CaptureTextView 据此在焦点态回写视图，绕过"活动编辑器不回写"守卫。
    private(set) var draftResetToken: UUID?

    private(set) var notes: [NoteListItem] = []
    private(set) var todos: [Todo] = []
    private(set) var banner: BannerState?

    // - MARK: 删除与撤销（S1-07，03 §7）

    /// 删除撤销栈的一条记录（会话级，不持久化）。
    struct DeletedItem {
        enum Kind: Equatable {
            case note(Note.ID)
            case todo(Todo.ID)
        }

        let kind: Kind
        let summary: String
    }

    /// 删除撤销栈：按删除先后入栈，⌘Z 逐条弹出（最近删的先恢复）。
    private(set) var deletedStack: [DeletedItem] = []
    /// 底部撤销提示条（03 §7）：显示删除摘要 + "撤销"，5 秒自动消失。
    private(set) var deletedBarSummary: String?
    /// 隐藏延迟（L2 测试注入缩短；默认 5 秒）。
    @ObservationIgnored var deletedBarHideDelay: Duration = .seconds(5)
    /// nonisolated(unsafe) 供 deinit 取消。
    @ObservationIgnored nonisolated(unsafe) private var deletedBarHideTask: Task<Void, Never>?

    /// 面板内 ⌘Z（非编辑态）：逐条撤销最近一次删除；无可撤销时无反应（返回 false 交回默认链）。
    func undoLastDeleteIfNeeded() -> Bool {
        guard !isEditingAny else { return false }
        guard let last = deletedStack.popLast() else { return false }
        Task {
            await restore(last)
            await MainActor.run { self.refreshDeletedBar() }
        }
        return true
    }

    /// 撤销提示条的"撤销"按钮：同 ⌘Z。
    func undoLastDelete() {
        _ = undoLastDeleteIfNeeded()
    }

    /// 是否处于任一编辑态（Esc/⌘Z 的分级依据）。
    var isEditingAny: Bool {
        editingNoteID != nil || editingTodoID != nil
    }

    /// 恢复一条删除（restore 走数据层；失败走提示条并把条目放回栈顶——撤销入口不能丢）。
    private func restore(_ item: DeletedItem) async {
        do {
            switch item.kind {
            case .note(let id): try await noteRepository.restore(id)
            case .todo(let id): try await todoRepository.restore(id)
            }
        } catch let error as ShikeDataError {
            await MainActor.run {
                self.deletedStack.append(item) // 失败回栈：重试成功前撤销入口保持可达
                self.report(error, retry: { [weak self] in Task { await self?.retryRestore(item) } })
            }
        } catch {
            await MainActor.run {
                self.deletedStack.append(item)
                self.report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.retryRestore(item) } })
            }
        }
    }

    /// 撤销重试：先从栈顶取回条目（与 undoLastDeleteIfNeeded 的弹出对称），成功则刷新提示条。
    private func retryRestore(_ item: DeletedItem) async {
        deletedStack.removeAll { $0.kind == item.kind }
        await restore(item)
        await MainActor.run { self.refreshDeletedBar() }
    }

    /// 删除入栈并显示撤销提示条（5 秒；连续删除重置计时与内容；超长摘要加省略号）。
    fileprivate func recordDeletion(kind: DeletedItem.Kind, summary: String) {
        let truncated = String(summary.prefix(12))
        let display = summary.count > 12 ? truncated + "…" : truncated
        deletedStack.append(DeletedItem(kind: kind, summary: display))
        showDeletedBar(display)
    }

    /// 显示提示条并排 5 秒隐藏任务（连续删除/撤销显示下一条时同样重启计时）。
    private func showDeletedBar(_ summary: String) {
        deletedBarSummary = summary
        deletedBarHideTask?.cancel()
        deletedBarHideTask = Task { [weak self] in
            try? await Task.sleep(for: self?.deletedBarHideDelay ?? .seconds(5))
            guard !Task.isCancelled else { return }
            self?.deletedBarSummary = nil
        }
    }

    /// 撤销后刷新提示条：栈空则收起，否则显示下一条并重启计时（03 §7）。
    private func refreshDeletedBar() {
        if let last = deletedStack.last {
            showDeletedBar(last.summary)
        } else {
            deletedBarSummary = nil
        }
    }

    /// 两份草稿（S1-04，03 §4）：随输入持久化；收起面板、切换模式不清空；提交成功清空。
    var draftNote: String = "" {
        didSet { preferences.panelDraftNote = draftNote }
    }
    var draftTodo: String = "" {
        didSet {
            preferences.panelDraftTodo = draftTodo
            refreshRecognition()
        }
    }
    /// 当前模式的草稿（输入框绑定用）。
    var currentDraft: String {
        get { mode == .note ? draftNote : draftTodo }
        set {
            if mode == .note { draftNote = newValue } else { draftTodo = newValue }
        }
    }

    // - MARK: 时间识别（S2-01，03 §4）

    /// 识别提示状态：nil=无提示（无识别/便签模式/草稿为空）。
    enum RecognitionHintState: Equatable {
        case recognized(RecognitionHint.Content)
        case dismissed
    }

    /// 当前识别结果（nil=未识别）；待办草稿每次非组合态变化时重算。
    private(set) var recognition: DateParseResult?
    /// ✕ 取消本次识别：不再识别，直到草稿被清空（03 §4）；模式往返保留。
    private(set) var recognitionDismissed = false
    /// 识别用"现在"（L2 注入固定值断言；默认系统时间）。
    @ObservationIgnored var parseNow: () -> Date = { Date() }

    /// 当前识别对应的待办时间（识别提示与测试用；提交载荷在 todoSubmission 定格）。
    var recognizedDue: TodoDue? {
        guard let recognition else { return nil }
        return TodoDue(date: recognition.date, hasTime: recognition.hasTime)
    }

    /// 提示条状态（视图渲染用）；草稿为空恒为 nil（识别提示只跟"正在输入的句子"走）。
    var recognitionHintState: RecognitionHintState? {
        guard mode == .todo, !draftTodo.isEmpty else { return nil }
        if recognitionDismissed { return .dismissed }
        guard let recognition else { return nil }
        let nsDraft = draftTodo as NSString
        let matchedText = recognition.matchedRanges
            .filter { $0.location != NSNotFound && NSMaxRange($0) <= nsDraft.length }
            .map { nsDraft.substring(with: $0) }
            .joined()
        let content = RecognitionHint.content(
            matchedText: matchedText,
            due: TodoDue(date: recognition.date, hasTime: recognition.hasTime),
            now: parseNow(),
            timeZone: timeZone
        )
        return .recognized(content)
    }

    /// ✕ 取消本次识别（03 §4）：提示变灰、高亮清除。
    func dismissRecognition() {
        recognitionDismissed = true
        recognition = nil
    }

    /// 重新识别：仅待办模式、未取消时；草稿清空复位取消标记（03 §4）。
    private func refreshRecognition() {
        guard mode == .todo else {
            recognition = nil
            return
        }
        if draftTodo.isEmpty {
            recognitionDismissed = false
            recognition = nil
            return
        }
        guard !recognitionDismissed else { return }
        recognition = ChineseDateParser(timeZone: timeZone).parse(draftTodo, now: parseNow())
    }
    /// 最近创建的条目（S1-04）：列表用它做 1 秒高亮；创建任务在 1 秒后清空。
    private(set) var recentlyCreatedItemID: String?
    /// 呼出聚焦令牌（S1-04/S1-03）：PopoverController.onShow 时刷新，输入框据此获得焦点。
    private(set) var focusToken: UUID?

    private let noteRepository: NoteRepository
    private let todoRepository: TodoRepository
    private let preferences: Preferences
    @ObservationIgnored private var bannerRetry: (() -> Void)?
    /// 只有 start()（重新订阅）之后收到的首批数据才允许清除读取失败提示条；
    /// 否则另一条仍在运行的流的任意更新会把提示条误清掉。
    @ObservationIgnored private var pendingLoadBannerClear = false
    /// @ObservationIgnored + nonisolated(unsafe)（Task 是 Sendable，取消本身 Sendable 安全）
    /// 只为让 deinit 能停止任务；deinit 与 start/stop 不会并发发生（模型释放后不再有订阅）。
    @ObservationIgnored nonisolated(unsafe) private var noteTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var todoTask: Task<Void, Never>?
    /// 新条目高亮的清除任务（S1-04）；连续创建时取消上一个（nonisolated(unsafe) 供 deinit 取消）。
    @ObservationIgnored nonisolated(unsafe) private var highlightClearTask: Task<Void, Never>?

    // - MARK: 面板行为的回调（S1-01，由 App 接到 PopoverController；默认空实现供 L2 直接组装）

    /// 尺寸把手的"当前面板尺寸"。
    @ObservationIgnored var resizeCurrentSize: () -> CGSize = { CGSize(width: 360, height: 520) }
    /// 尺寸把手的拖动回调：proposed 为建议尺寸，isFinal 表示拖动结束（应持久化）。
    @ObservationIgnored var resizeApply: (_ proposed: CGSize, _ isFinal: Bool) -> Void = { _, _ in }
    /// 呼出即打字（S1-04）：输入框就绪时回放呼出期间缓冲的按键；由 App 接到 TypingBuffer。
    @ObservationIgnored var replayBufferedKeys: (NSTextView) -> Void = { _ in }
    /// 输入框是否已就绪可接收输入（S1-04）：呼出即打字的截获判定依据。
    /// 呼出时复位（新空窗开始），输入框就绪时置位（captureDidBecomeReady）。
    private(set) var isCaptureReady = false

    /// 通知权限请求钩子（S2-10）：提交带时间待办时触发；App 接 NotificationScheduling，
    /// L2 留空实现保持零系统调用。
    @ObservationIgnored var notificationPermissionRequester: () -> Void = {}
    /// 待办数据变化钩子（S2-05）：提醒调度器经它做 0.5 秒合并对账；L2 留空。
    @ObservationIgnored var todosChanged: () -> Void = {}
    /// 跨天/唤醒钩子（S2-08）：菜单栏计数等时间口径的界面刷新；与 todosChanged 一样由 App 接线。
    @ObservationIgnored var timeContextChanged: () -> Void = {}
    /// 通知点本体后的定位目标（S2-04）：TodoListView 滚动定位并高亮，1.5 秒后清除。
    private(set) var locateTodoID: String?
    /// 定位高亮的清除任务（nonisolated(unsafe) 供 deinit 取消）。
    @ObservationIgnored nonisolated(unsafe) private var locateClearTask: Task<Void, Never>?

    /// 正在"设置时间…"的待办（S2-07）；弹层经 .popover(item:) 挂载。
    var editingTimeTarget: Todo?
    /// 设置时间的落库路径（S2-07）；失败走保存失败提示条。
    func setDue(_ id: Todo.ID, _ due: TodoDue?) async {
        do {
            try await todoRepository.setDue(id, due)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.setDue(id, due) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.setDue(id, due) } })
        }
    }

    /// 通知点本体：切到待办模式并定位该条（03 §11）；由 App 的 openPanel 回调组合。
    func locateTodo(uuid: UUID) {
        mode = .todo
        locateTodoID = uuid.uuidString
        locateClearTask?.cancel()
        locateClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            self?.locateTodoID = nil
        }
    }

    /// 通知动作"完成"（03 §11）：按 uuid 直达仓储（不依赖界面快照——冷启动时
    /// 观察流首批快照未到也能正确落库，盲审 F1）；待办已删除则忽略（返回 false）。
    func completeTodo(uuid: UUID) async {
        do {
            let handled = try await todoRepository.setCompleted(uuid: uuid, true)
            if !handled {
                Log.data.info("通知动作：待办不存在或已删除，忽略 uuid=\(uuid.uuidString, privacy: .public)")
            }
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.completeTodo(uuid: uuid) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.completeTodo(uuid: uuid) } })
        }
    }

    /// 通知动作"稍后提醒"（03 §11）：按 uuid 写 snoozedUntil；已完成/已删除忽略（盲审 F5）。
    func snoozeTodo(uuid: UUID, until date: Date) async {
        do {
            let handled = try await todoRepository.snooze(uuid: uuid, until: date)
            if !handled {
                Log.data.info("通知动作：待办不存在/已删除/已完成，忽略 uuid=\(uuid.uuidString, privacy: .public)")
            }
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.snoozeTodo(uuid: uuid, until: date) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.snoozeTodo(uuid: uuid, until: date) } })
        }
    }

    /// 输入框就绪（S1-04）：置位并触发缓冲回放；由 CaptureTextView 的 onViewReady 经 App 接入。
    func captureDidBecomeReady(_ textView: NSTextView) {
        isCaptureReady = true
        replayBufferedKeys(textView)
    }

    /// 新的呼出空窗开始（S1-04）：复位就绪标志；由 PopoverController.onShow 经 App 接入。
    func beginCaptureWindow() {
        isCaptureReady = false
    }

    /// 面板收起（S1-04）：复位就绪标志；缓冲的丢弃由 App 接到 TypingBuffer.reset。
    /// 同时关闭"设置时间"弹层（面板级 Esc/热键/点击外部直接收起宿主，弹层
    /// 不会走 item 绑定的置 nil 回写——不清理会幽灵复活，盲审 3.7-F2）。
    func endCaptureWindow() {
        isCaptureReady = false
        editingTimeTarget = nil
    }

    // - MARK: 便签列表与编辑（S1-05，03 §5）

    /// 列表行的显示时区（L2 可注入；阶段 1 恒为 .current——数据库 Options.timeZone
    /// 阶段 1 只有默认值，出现非默认时区的一天候（阶段 2 全天规范化）再接线）。
    /// 变化时识别随之重算（S2-01：解析器的日界/顺延都按此时区）。
    @ObservationIgnored var timeZone: TimeZone = .current {
        didSet { refreshRecognition() }
    }

    /// 正在原位编辑的便签（空则无编辑）；编辑文字实时在模型上（供失焦/Esc/收起面板保存）。
    var editingNoteID: Note.ID?
    var editingNoteText: String = ""

    /// 「置顶」组：按置顶时间降序（03 §5；pinnedAt 为空的行不会出现在本组）。
    var pinnedNotes: [NoteListItem] {
        notes
            .filter { $0.note.pinnedAt != nil }
            .sorted { ($0.note.pinnedAt ?? .distantPast) > ($1.note.pinnedAt ?? .distantPast) }
    }
    /// 「便签」组（未置顶，按最近修改）。
    var unpinnedNotes: [NoteListItem] { notes.filter { $0.note.pinnedAt == nil } }

    /// 原位编辑的自动保存（0.5 秒防抖/失焦/结束编辑三个时机共用）：
    /// 内容未变不写库；清空内容视为删除（03 §5/§7，撤销提示条在 Story 2.8 接入）。
    func saveNoteContent(_ id: Note.ID, _ text: String) async {
        guard let item = notes.first(where: { $0.note.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            if trimmed.isEmpty {
                try await noteRepository.softDelete(id)
                recordDeletion(kind: .note(id), summary: item.note.content)
            } else if item.note.content != text {
                try await noteRepository.updateContent(id, to: text)
            }
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.saveNoteContent(id, text) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.saveNoteContent(id, text) } })
        }
    }

    /// 置顶/取消置顶（03 §5 右键菜单）；失败走提示条。
    func setNotePinned(_ id: Note.ID, _ pinned: Bool) async {
        do {
            try await noteRepository.setPinned(id, pinned)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.setNotePinned(id, pinned) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.setNotePinned(id, pinned) } })
        }
    }

    /// 删除便签（软删除），入撤销栈并显示撤销提示条（S1-07）。
    func deleteNote(_ id: Note.ID) async {
        let summary = notes.first { $0.note.id == id }?.note.content ?? ""
        do {
            try await noteRepository.softDelete(id)
            recordDeletion(kind: .note(id), summary: summary)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.deleteNote(id) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.deleteNote(id) } })
        }
    }

    /// Esc 第一级"结束编辑"（S1-01/S1-05）：非编辑态返回 false（本次 Esc 继续收起面板）；
    /// 编辑态（便签或待办标题）结束编辑并立即保存（无防抖），返回 true。
    func endEditingIfNeeded() -> Bool {
        if let id = editingNoteID {
            editingNoteID = nil
            let text = editingNoteText
            editingNoteText = ""
            Task { await saveNoteContent(id, text) }
            return true
        }
        if let id = editingTodoID {
            editingTodoID = nil
            let text = editingTodoText
            editingTodoText = ""
            Task { await saveTodoTitle(id, text) }
            return true
        }
        return false
    }

    // - MARK: 待办列表与完成（S1-06，03 §6）

    /// 正在原位编辑的待办标题（空则无编辑）。
    var editingTodoID: Todo.ID?
    var editingTodoText: String = ""

    /// 分组时钟（S2-06）：跨天/唤醒时递增，驱动视图重算分组（不标 @ObservationIgnored——
    /// 视图读取 todoGroups 时要建立对它的依赖）。
    private(set) var timeContextTick = 0
    /// 待办五分组（S2-06，03 §6）：逾期/今天/以后/无日期/已完成；纯函数注入 now/时区。
    var todoGroups: TodoGroups {
        _ = timeContextTick
        return TodoGrouping.group(todos: todos, now: Date(), timeZone: timeZone)
    }
    /// 跨天/唤醒：重算分组（S2-06）并通知时间口径的界面（S2-08）。
    func handleTimeContextChanged() {
        timeContextTick += 1
        timeContextChanged()
    }

    /// 待办模式分段按钮的数字角标（S2-08）：与菜单栏计数同口径；nil=不显示。
    var todoBadgeCount: Int? {
        _ = timeContextTick // 跨天/唤醒时角标随分组口径重算（盲审 F3）
        let mode = MenuBarCounter.resolve(preferences.menuBarCounter)
        return MenuBarCounter.count(mode, todos: todos, now: Date(), timeZone: timeZone)
    }

    /// 勾选后处于"1 秒待移入"的待办（03 §6：立即划线变灰、1 秒后移组、期间可勾回）。
    private(set) var pendingCompletionIDs = Set<Todo.ID>()
    /// 完成延迟（L2 测试注入缩短；默认 1 秒）。
    @ObservationIgnored var completionDelay: Duration = .seconds(1)
    /// nonisolated(unsafe) 供 deinit 取消（Task 字典自身只在主线程访问）。
    @ObservationIgnored nonisolated(unsafe) private var completionTimers: [Todo.ID: Task<Void, Never>] = [:]

    /// 圆圈点击的三态：未完成→待移入（可勾回）；待移入→取消；已完成→勾回。
    func toggleTodoCompletion(_ id: Todo.ID) {
        if let timer = completionTimers[id] {
            timer.cancel()
            completionTimers[id] = nil
            pendingCompletionIDs.remove(id)
            return
        }
        let todo = todos.first { $0.id == id }
        if todo?.completedAt != nil {
            Task { await setTodoCompleted(id, false) }
            return
        }
        pendingCompletionIDs.insert(id)
        completionTimers[id] = Task { [weak self] in
            try? await Task.sleep(for: self?.completionDelay ?? .seconds(1))
            guard !Task.isCancelled else { return }
            self?.completionTimers[id] = nil
            await self?.setTodoCompleted(id, true)
            // 落库成功后再移除待移入标记，避免"数据已写、视觉已回退"的闪烁帧。
            self?.pendingCompletionIDs.remove(id)
        }
    }

    /// 设置完成状态（数据层清空 snoozedUntil 等 ADR-017 语义）；失败走提示条。
    func setTodoCompleted(_ id: Todo.ID, _ completed: Bool) async {
        do {
            try await todoRepository.setCompleted(id, completed)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.setTodoCompleted(id, completed) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.setTodoCompleted(id, completed) } })
        }
    }

    /// 待办标题编辑的保存（内容未变不写库；空标题不保存——回退到原标题）。
    func saveTodoTitle(_ id: Todo.ID, _ text: String) async {
        guard let todo = todos.first(where: { $0.id == id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, todo.title != text else { return }
        do {
            try await todoRepository.updateTitle(id, to: text)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.saveTodoTitle(id, text) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.saveTodoTitle(id, text) } })
        }
    }

    /// 删除待办（软删除），入撤销栈并显示撤销提示条（S1-07）。
    func deleteTodo(_ id: Todo.ID) async {
        let summary = todos.first { $0.id == id }?.title ?? ""
        do {
            try await todoRepository.softDelete(id)
            recordDeletion(kind: .todo(id), summary: summary)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.deleteTodo(id) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.deleteTodo(id) } })
        }
    }

    /// 提交的创建动作（默认走仓储；测试可替换以模拟失败/成功，与 runNotes/runTodos 同类接缝）。
    @ObservationIgnored internal var createNote: (String) async throws -> Note
    @ObservationIgnored internal var createTodo: (String, TodoDue?) async throws -> Todo

    init(
        noteRepository: NoteRepository,
        todoRepository: TodoRepository,
        preferences: Preferences,
        timeZone: TimeZone = .current,
        parseNow: @escaping () -> Date = { Date() }
    ) {
        self.noteRepository = noteRepository
        self.todoRepository = todoRepository
        self.preferences = preferences
        self.timeZone = timeZone
        self.parseNow = parseNow
        if let last = Mode(rawValue: preferences.panelLastMode) {
            mode = last
        }
        draftNote = preferences.panelDraftNote
        draftTodo = preferences.panelDraftTodo
        self.createNote = { try await noteRepository.create(content: $0) }
        self.createTodo = { try await todoRepository.create(title: $0, due: $1) }
        // 恢复的草稿立即用注入的 now/时区识别一次（S2-01：呼出后提示条与高亮随草稿出现）。
        refreshRecognition()
    }

    /// 每次呼出面板时应用"呼出时进入"设置（S1-03）；由 PopoverController 的 didShow 触发。
    /// 持久化的 lastMode 先读后写：openMode 为固定模式时呼出会改写 lastMode（03 §9 语义内）。
    /// 末尾无条件重识别：openMode 与当前模式相同时 didSet 短路，隔夜呼出必须重算
    /// "明天/今天"这类相对日（S2-01，盲审 H1）。
    func applyOpenMode() {
        let openMode = OpenMode(rawValue: preferences.panelOpenMode) ?? .last
        let last = Mode(rawValue: preferences.panelLastMode) ?? .note
        mode = Self.initialMode(openMode: openMode, lastMode: last)
        focusToken = UUID()
        refreshRecognition()
    }

    // - MARK: 快速输入（S1-04，03 §4）

    /// 一次提交的载荷（S2-02）：标题与时间在提交时点定格，重试重放同一对，
    /// 不随等待期间识别状态的变化漂移。
    private enum Submission {
        case note(content: String)
        /// originalText 用于成功后比对草稿（重试期间用户改动的新草稿绝不丢）。
        case todo(originalText: String, title: String, due: TodoDue?)
    }

    /// 待办提交物（S2-02，05 §7）：识别中→清理标题+due；识别被取消（✕）→
    /// 仅空白与标点清理、无时间（05 §7 修订的豁免仅限 ✕）；无识别→照常执行
    /// 第 3 步提醒词清理（matchedRanges 为空，"记得还信用卡"→"还信用卡"，盲审 F2）。
    private func todoSubmission(from text: String) -> Submission {
        if !recognitionDismissed, let recognition {
            let title = TitleCleaner.clean(text, removing: recognition.matchedRanges)
            return .todo(originalText: text, title: title, due: TodoDue(date: recognition.date, hasTime: recognition.hasTime))
        }
        if recognitionDismissed {
            return .todo(originalText: text, title: TitleCleaner.stripWhitespaceAndPunctuation(text), due: nil)
        }
        return .todo(originalText: text, title: TitleCleaner.clean(text, removing: []), due: nil)
    }

    /// 提交当前输入（03 §4：↩）。trim 后为空则无反应；成功清空该模式草稿并记录新条目；
    /// 失败保留输入，提示条的"重试"绑定当次载荷（NFR19），重试成功后清除保存失败提示条。
    func submitCurrentDraft() {
        let text = currentDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch mode {
        case .note:
            submit(.note(content: text))
        case .todo:
            let submission = todoSubmission(from: text)
            // 第一次创建带时间的待办时请求通知权限（S2-10；系统对重复调用幂等）。
            if case .todo(_, _, .some) = submission {
                notificationPermissionRequester()
            }
            submit(submission)
        }
    }

    private func submit(_ submission: Submission) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let createdID: String
                switch submission {
                case .note(let content):
                    createdID = try await self.createNote(content).uuid.uuidString
                case .todo(_, let title, let due):
                    createdID = try await self.createTodo(title, due).uuid.uuidString
                }
                self.finishSubmit(submission: submission, createdID: createdID)
            } catch let error as ShikeDataError {
                // 输入保留（不改草稿）；重试重放同一次提交载荷。
                self.report(error, retry: { [weak self] in self?.submit(submission) })
            } catch {
                self.report(.writeFailed(.ioError), retry: { [weak self] in self?.submit(submission) })
            }
        }
    }

    private func finishSubmit(submission: Submission, createdID: String) {
        // 只在草稿仍是提交时的文本时清空——重试期间用户若已改动，新草稿绝不能丢（不丢数据）。
        switch submission {
        case .note(let content): if draftNote == content { draftNote = "" }
        case .todo(let originalText, _, _): if draftTodo == originalText { draftTodo = "" }
        }
        // 若保存失败提示条还在（重试成功的路径），按 NFR19 清除它。
        if case .saveFailed = banner?.kind {
            banner = nil
            bannerRetry = nil
        }
        // 清空可能发生在焦点态（AC：提交后输入框清空且焦点保留）——发令牌让视图回写。
        draftResetToken = UUID()
        markRecentlyCreated(createdID)
    }

    /// 新条目 1 秒高亮（03 §4）：连续创建时重置计时。
    private func markRecentlyCreated(_ id: String) {
        highlightClearTask?.cancel()
        recentlyCreatedItemID = id
        highlightClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.recentlyCreatedItemID = nil
        }
    }

    deinit {
        // Task.cancel 是 nonisolated 的，可在 deinit 调用；释放时停止观察与计时。
        noteTask?.cancel()
        todoTask?.cancel()
        highlightClearTask?.cancel()
        completionTimers.values.forEach { $0.cancel() }
        deletedBarHideTask?.cancel()
        locateClearTask?.cancel()
        timeContextObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// 订阅两类观察流（app-shell.md：start() 订阅便签与待办两个观察）。
    /// 读取失败提示条的"重试"会重新调用本方法，即重新订阅。
    /// 跨天/唤醒观察者（S2-06：自动重新分组）；nonisolated(unsafe) 供 stop 移除。
    @ObservationIgnored nonisolated(unsafe) private var timeContextObservers: [any NSObjectProtocol] = []

    func start() {
        noteTask?.cancel()
        todoTask?.cancel()
        pendingLoadBannerClear = true
        noteTask = Task { [weak self] in await self?.consumeNotes() }
        todoTask = Task { [weak self] in await self?.consumeTodos() }
        startTimeContextObservers()
    }

    /// 订阅跨天与唤醒：分组时钟递增，视图重算"逾期/今天"（S2-06）。
    private func startTimeContextObservers() {
        stopTimeContextObservers()
        let dayChanged = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTimeContextChanged() }
        }
        let wake = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleTimeContextChanged() }
        }
        timeContextObservers = [dayChanged, wake]
    }

    private func stopTimeContextObservers() {
        timeContextObservers.forEach(NotificationCenter.default.removeObserver)
        timeContextObservers = []
    }

    /// 停止消费（applicationWillTerminate 调用）。
    func stop() {
        noteTask?.cancel()
        todoTask?.cancel()
        stopTimeContextObservers()
        noteTask = nil
        todoTask = nil
        pendingLoadBannerClear = false
    }

    private func consumeNotes() async {
        await runNotes(noteRepository.observeActive())
    }

    private func consumeTodos() async {
        await runTodos(todoRepository.observeActive())
    }

    /// 消费一个便签观察流。internal 供 L2 直接驱动真实的失败处理链路。
    func runNotes(_ stream: AsyncThrowingStream<[NoteListItem], any Error>) async {
        do {
            for try await items in stream {
                notes = items
                clearLoadBannerIfNeeded()
            }
            // data-layer.md「观察」：非取消的正常结束是故障信号（仓储层已把它转成
            // readFailed 抛出；这里兜底，防止数据层语义变化后静默失效）。
            reportIfNotCancelled(.readFailed(.ioError))
        } catch {
            handleStreamFailure(error)
        }
    }

    /// 消费一个待办观察流。internal 供 L2 直接驱动真实的失败处理链路。
    func runTodos(_ stream: AsyncThrowingStream<[Todo], any Error>) async {
        do {
            for try await items in stream {
                todos = items
                todosChanged()
                clearLoadBannerIfNeeded()
            }
            reportIfNotCancelled(.readFailed(.ioError))
        } catch {
            handleStreamFailure(error)
        }
    }

    private func reportIfNotCancelled(_ error: ShikeDataError) {
        guard !Task.isCancelled else { return }
        report(error, retry: {})
    }

    /// 观察流以异常结束：取消不算失败；其他错误统一按读取失败上报。
    private func handleStreamFailure(_ error: Error) {
        guard !(error is CancellationError) else { return }
        let dataError = (error as? ShikeDataError) ?? ShikeDataError.readFailed(.ioError)
        report(dataError, retry: {})
    }

    /// 重新订阅成功（收到首批数据）后清除读取失败提示条；保存失败提示条不受数据更新影响。
    private func clearLoadBannerIfNeeded() {
        guard pendingLoadBannerClear, case .loadFailed = banner?.kind else { return }
        pendingLoadBannerClear = false
        banner = nil
    }

    /// 生成提示条（app-shell.md：读取失败时"重试"会重新订阅）。
    func report(_ error: ShikeDataError, retry: @escaping () -> Void) {
        Log.data.info("面板提示条：\(error.classification, privacy: .public)")
        switch error {
        case .readFailed(let reason):
            banner = BannerState(kind: .loadFailed(reason))
            bannerRetry = { [weak self] in self?.start() }
            pendingLoadBannerClear = false
        case .writeFailed(let reason):
            banner = BannerState(kind: .saveFailed(reason))
            bannerRetry = retry
        case .openFailed(let reason), .backupFailed(let reason):
            // 阶段 0 的面板不会收到这两类；按保存失败展示，避免静默。
            banner = BannerState(kind: .saveFailed(reason))
            bannerRetry = retry
        case .notFound:
            banner = BannerState(kind: .saveFailed(.unknown(code: 0)))
            bannerRetry = retry
        }
    }

    /// 提示条上的"重试"按钮。
    func retryBanner() {
        bannerRetry?()
    }
}
