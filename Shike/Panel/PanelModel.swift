// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import Observation
import os
import ShikeData

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
        }
    }
    /// 草稿被"输入框以外"的路径改变（模式切换、提交清空）的信号（S1-04）：
    /// CaptureTextView 据此在焦点态回写视图，绕过"活动编辑器不回写"守卫。
    private(set) var draftResetToken: UUID?

    private(set) var notes: [NoteListItem] = []
    private(set) var todos: [Todo] = []
    private(set) var banner: BannerState?

    /// 两份草稿（S1-04，03 §4）：随输入持久化；收起面板、切换模式不清空；提交成功清空。
    var draftNote: String = "" {
        didSet { preferences.panelDraftNote = draftNote }
    }
    var draftTodo: String = "" {
        didSet { preferences.panelDraftTodo = draftTodo }
    }
    /// 当前模式的草稿（输入框绑定用）。
    var currentDraft: String {
        get { mode == .note ? draftNote : draftTodo }
        set {
            if mode == .note { draftNote = newValue } else { draftTodo = newValue }
        }
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
    func endCaptureWindow() {
        isCaptureReady = false
    }

    // - MARK: 便签列表与编辑（S1-05，03 §5）

    /// 列表行的显示时区（L2 可注入；阶段 1 恒为 .current——数据库 Options.timeZone
    /// 阶段 1 只有默认值，出现非默认时区的一天候（阶段 2 全天规范化）再接线）。
    @ObservationIgnored var timeZone: TimeZone = .current

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

    /// 删除便签（软删除）；撤销提示条与 ⌘Z 撤销在 Story 2.8 接入。
    func deleteNote(_ id: Note.ID) async {
        do {
            try await noteRepository.softDelete(id)
        } catch let error as ShikeDataError {
            report(error, retry: { [weak self] in Task { await self?.deleteNote(id) } })
        } catch {
            report(.writeFailed(.ioError), retry: { [weak self] in Task { await self?.deleteNote(id) } })
        }
    }

    /// Esc 第一级"结束编辑"（S1-01/S1-05）：非编辑态返回 false（本次 Esc 继续收起面板）；
    /// 编辑态结束编辑并立即保存（无防抖），返回 true。
    func endEditingIfNeeded() -> Bool {
        guard let id = editingNoteID else { return false }
        editingNoteID = nil
        let text = editingNoteText
        editingNoteText = ""
        Task { await saveNoteContent(id, text) }
        return true
    }

    /// 提交的创建动作（默认走仓储；测试可替换以模拟失败/成功，与 runNotes/runTodos 同类接缝）。
    @ObservationIgnored internal var createNote: (String) async throws -> Note
    @ObservationIgnored internal var createTodo: (String, TodoDue?) async throws -> Todo

    init(noteRepository: NoteRepository, todoRepository: TodoRepository, preferences: Preferences) {
        self.noteRepository = noteRepository
        self.todoRepository = todoRepository
        self.preferences = preferences
        if let last = Mode(rawValue: preferences.panelLastMode) {
            mode = last
        }
        draftNote = preferences.panelDraftNote
        draftTodo = preferences.panelDraftTodo
        self.createNote = { try await noteRepository.create(content: $0) }
        self.createTodo = { try await todoRepository.create(title: $0, due: $1) }
    }

    /// 每次呼出面板时应用"呼出时进入"设置（S1-03）；由 PopoverController 的 didShow 触发。
    /// 持久化的 lastMode 先读后写：openMode 为固定模式时呼出会改写 lastMode（03 §9 语义内）。
    func applyOpenMode() {
        let openMode = OpenMode(rawValue: preferences.panelOpenMode) ?? .last
        let last = Mode(rawValue: preferences.panelLastMode) ?? .note
        mode = Self.initialMode(openMode: openMode, lastMode: last)
        focusToken = UUID()
    }

    // - MARK: 快速输入（S1-04，03 §4）

    /// 提交当前输入（03 §4：↩）。trim 后为空则无反应；成功清空该模式草稿并记录新条目；
    /// 失败保留输入，提示条的"重试"绑定当次输入（NFR19），重试成功后清除保存失败提示条。
    func submitCurrentDraft() {
        let text = currentDraft
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        submit(text, mode: mode)
    }

    private func submit(_ text: String, mode: Mode) {
        Task { [weak self] in
            guard let self else { return }
            do {
                let createdID: String
                switch mode {
                case .note:
                    createdID = try await self.createNote(text).uuid.uuidString
                case .todo:
                    createdID = try await self.createTodo(text, nil).uuid.uuidString
                }
                self.finishSubmit(text: text, mode: mode, createdID: createdID)
            } catch let error as ShikeDataError {
                // 输入保留（不改草稿）；重试重放同一次提交。
                self.report(error, retry: { [weak self] in self?.submit(text, mode: mode) })
            } catch {
                self.report(.writeFailed(.ioError), retry: { [weak self] in self?.submit(text, mode: mode) })
            }
        }
    }

    private func finishSubmit(text: String, mode: Mode, createdID: String) {
        // 只在草稿仍是提交时的文本时清空——重试期间用户若已改动，新草稿绝不能丢（不丢数据）。
        switch mode {
        case .note: if draftNote == text { draftNote = "" }
        case .todo: if draftTodo == text { draftTodo = "" }
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
        // Task.cancel 是 nonisolated 的，可在 deinit 调用；释放时停止观察。
        noteTask?.cancel()
        todoTask?.cancel()
        highlightClearTask?.cancel()
    }

    /// 订阅两类观察流（app-shell.md：start() 订阅便签与待办两个观察）。
    /// 读取失败提示条的"重试"会重新调用本方法，即重新订阅。
    func start() {
        noteTask?.cancel()
        todoTask?.cancel()
        pendingLoadBannerClear = true
        noteTask = Task { [weak self] in await self?.consumeNotes() }
        todoTask = Task { [weak self] in await self?.consumeTodos() }
    }

    /// 停止消费（applicationWillTerminate 调用）。
    func stop() {
        noteTask?.cancel()
        todoTask?.cancel()
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
