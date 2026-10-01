// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Observation
import os
import ShikeData
import SwiftUI

/// 回收站确认弹窗的待执行目标（S3.5-05）：单条永久删除（便签/待办）或清空全部。
enum ConfirmTarget: Equatable {
    case note(Note.ID)
    case todo(Todo.ID)
    case all
}

/// 回收站状态（S3.5-05，03 §16）：消费 TrashRepository 的两个观察流（deletedAt 降序，
/// 流序即展示序，模型不再排序），提供恢复 / 永久删除 / 清空三类动作，以及确认弹窗
/// 状态与操作反馈小字条。
///
/// 闭包接缝（MainTodosModel/MainNotesModel 同款）：全部 @ObservationIgnored var +
/// 默认空实现，L2 测试传 mock 闭包（无需数据库），集成层接 TrashRepository 与
/// 主窗口其余入口同一观察流。写路径闭包均为非抛出 `async -> Void`——失败场景由
/// 集成层把错误转成文案、经 showStatus(_:) 传回，模型只负责展示（默认成功文案
/// 不会覆盖集成层已传回的文案，见 showDefaultStatusIfUnreported）。
///
/// 确认设计：恢复是可逆操作（用户随时可再删），直接转发、不走确认；
/// 永久删除与清空不可逆，先置 confirmTarget 弹确认框，confirm() 才执行。
@MainActor
@Observable
final class TrashModel {
    /// 确认弹窗的待执行目标；nil = 无待确认。
    var confirmTarget: ConfirmTarget?

    /// 操作反馈（视图顶部小字条），3 秒后自动清除。默认成功文案走
    /// main.trash.restored/permanentlyDeleted/emptied 键（docs/06：界面文案集中在
    /// xcstrings）；集成层传入的失败文案原样展示。
    private(set) var statusMessage: String?
    /// 反馈清除延迟（L2 测试注入缩短；默认 3 秒）。
    @ObservationIgnored var statusHideDelay: Duration = .seconds(3)
    /// 行删除时间的显示时区（同 PanelModel.timeZone 口径；集成层注入，阶段 1 恒 .current）。
    @ObservationIgnored var timeZone: TimeZone = .current

    /// 已删除的便签（流已按 deletedAt 降序，模型不再排序）。
    private(set) var deletedNotes: [Note] = []
    /// 已删除的待办（流已按 deletedAt 降序，模型不再排序）。
    private(set) var deletedTodos: [Todo] = []

    /// 首帧加载状态（W2）：两个观察流各交付首帧（含空数组帧）后置 true——此前的
    /// "两组皆空"只是未加载，不能显示"回收站是空的"（首帧空态闪现）。任一流失败/
    /// 非取消结束时同样置 true（失败由反馈通道承接，不停在假空态）。
    private(set) var isLoaded = false
    @ObservationIgnored private var notesFirstFrameArrived = false
    @ObservationIgnored private var todosFirstFrameArrived = false

    /// 记一个流的首帧（或失败收尾）：两个流都到齐即翻 isLoaded。
    private func markFirstFrame(notes: Bool) {
        if notes {
            notesFirstFrameArrived = true
        } else {
            todosFirstFrameArrived = true
        }
        if notesFirstFrameArrived && todosFirstFrameArrived {
            isLoaded = true
        }
    }

    // - MARK: 注入接缝（@ObservationIgnored：闭包不参与观察；默认空实现零副作用）

    /// 便签观察流工厂：集成接 `trashRepository.observeNotes()`。
    @ObservationIgnored var observeNotes: () -> AsyncThrowingStream<[Note], any Error> = {
        AsyncThrowingStream<[Note], any Error> { $0.finish() }
    }
    /// 待办观察流工厂：集成接 `trashRepository.observeTodos()`。
    @ObservationIgnored var observeTodos: () -> AsyncThrowingStream<[Todo], any Error> = {
        AsyncThrowingStream<[Todo], any Error> { $0.finish() }
    }
    /// 恢复便签：集成接 `trashRepository.restoreNote(_:)`（失败经 showStatus 传回文案）。
    @ObservationIgnored var restoreNote: (Note.ID) async -> Void = { _ in }
    /// 恢复待办：集成接 `trashRepository.restoreTodo(_:)`。
    @ObservationIgnored var restoreTodo: (Todo.ID) async -> Void = { _ in }
    /// 永久删除便签：集成接 `trashRepository.permanentlyDeleteNote(_:)`。
    @ObservationIgnored var permanentlyDeleteNote: (Note.ID) async -> Void = { _ in }
    /// 永久删除待办：集成接 `trashRepository.permanentlyDeleteTodo(_:)`。
    @ObservationIgnored var permanentlyDeleteTodo: (Todo.ID) async -> Void = { _ in }
    /// 清空回收站：集成接 `trashRepository.emptyTrash()`。
    @ObservationIgnored var emptyAll: () async -> Void = {}

    /// 观察消费与反馈清除任务（nonisolated(unsafe) 供 deinit 取消；deinit 与
    /// start/stop 不会并发发生，PanelModel 同款）。
    @ObservationIgnored nonisolated(unsafe) private var noteTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var todoTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var statusHideTask: Task<Void, Never>?

    deinit {
        // Task.cancel 是 nonisolated 的，可在 deinit 调用；释放时停止观察与计时。
        noteTask?.cancel()
        todoTask?.cancel()
        statusHideTask?.cancel()
    }

    // - MARK: 生命周期（CardManager 的流消费模式）

    /// 订阅回收站两个观察流（便签/待办，均按 deletedAt 降序推送；重复调用先取消旧订阅）。
    func start() {
        noteTask?.cancel()
        todoTask?.cancel()
        noteTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await notes in self.observeNotes() {
                    guard !Task.isCancelled else { return }
                    self.deletedNotes = notes
                    self.markFirstFrame(notes: true)
                }
                // data-layer.md「观察」：非取消的正常结束是故障信号——兜底记日志，
                // 防止数据层语义变化后静默失效（MainNotesModel/MainTodosModel 同款）。
                guard !Task.isCancelled else { return }
                self.markFirstFrame(notes: true)
                Log.app.error("回收站便签观察流非取消结束（应为故障信号）")
            } catch is CancellationError {
                // 取消不算故障
            } catch {
                // 观察流异常结束：与卡片观察流同一策略——记日志，不静默吞掉；
                // 同时翻转加载状态，视图不停在假空态（W2）。
                self.markFirstFrame(notes: true)
                Log.app.error("回收站便签观察流异常结束：\(String(describing: error), privacy: .public)")
            }
        }
        todoTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await todos in self.observeTodos() {
                    guard !Task.isCancelled else { return }
                    self.deletedTodos = todos
                    self.markFirstFrame(notes: false)
                }
                guard !Task.isCancelled else { return }
                self.markFirstFrame(notes: false)
                Log.app.error("回收站待办观察流非取消结束（应为故障信号）")
            } catch is CancellationError {
                // 取消不算故障
            } catch {
                self.markFirstFrame(notes: false)
                Log.app.error("回收站待办观察流异常结束：\(String(describing: error), privacy: .public)")
            }
        }
    }

    /// 停止消费（applicationWillTerminate 等场景由集成层调用；切换左栏入口不断流，
    /// 与面板/主窗口其余入口的常驻订阅同口径）。
    func stop() {
        noteTask?.cancel()
        noteTask = nil
        todoTask?.cancel()
        todoTask = nil
    }

    // - MARK: 恢复（可逆，直接转发）

    /// 恢复便签：直接转发（恢复可逆，不走确认弹窗），随后给出反馈。
    func requestRestoreNote(_ id: Note.ID) async {
        let reportedToken = statusToken
        await restoreNote(id)
        showDefaultStatusIfUnreported(String(localized: .mainTrashRestored(String(localized: .mainTrashNotes))), since: reportedToken)
    }

    /// 恢复待办：直接转发，随后给出反馈。
    func requestRestoreTodo(_ id: Todo.ID) async {
        let reportedToken = statusToken
        await restoreTodo(id)
        showDefaultStatusIfUnreported(String(localized: .mainTrashRestored(String(localized: .mainTrashTodos))), since: reportedToken)
    }

    // - MARK: 永久删除与清空（不可逆，确认后执行）

    /// 请求永久删除便签：置确认目标，弹窗确认后经 confirm() 执行。
    func requestDeleteNote(_ id: Note.ID) {
        confirmTarget = .note(id)
    }

    /// 请求永久删除待办：置确认目标。
    func requestDeleteTodo(_ id: Todo.ID) {
        confirmTarget = .todo(id)
    }

    /// 请求清空回收站：置确认目标。
    func requestEmptyAll() {
        confirmTarget = .all
    }

    /// 确认弹窗的确认按钮：执行 confirmTarget 对应动作并反馈；无待确认目标时无操作。
    func confirm() async {
        guard let target = confirmTarget else { return }
        await confirm(target)
    }

    /// 带目标的确认（视图用）：弹窗收起回调会先经 cancel() 清空 confirmTarget，
    /// 按钮动作须捕获 presented 目标再执行，避免竞态丢失。执行后清空确认状态。
    func confirm(_ target: ConfirmTarget) async {
        confirmTarget = nil
        let reportedToken = statusToken
        switch target {
        case .note(let id):
            await permanentlyDeleteNote(id)
            showDefaultStatusIfUnreported(String(localized: .mainTrashPermanentlyDeleted(String(localized: .mainTrashNotes))), since: reportedToken)
        case .todo(let id):
            await permanentlyDeleteTodo(id)
            showDefaultStatusIfUnreported(String(localized: .mainTrashPermanentlyDeleted(String(localized: .mainTrashTodos))), since: reportedToken)
        case .all:
            await emptyAll()
            showDefaultStatusIfUnreported(String(localized: .mainTrashEmptied), since: reportedToken)
        }
    }

    /// 取消确认弹窗：清空待确认目标（无任何写副作用）。
    func cancel() {
        confirmTarget = nil
    }

    // - MARK: 反馈小字条

    /// 显示反馈并排 3 秒清除任务（连续操作重启计时；PanelModel.showBar 同款）。
    func showStatus(_ message: String) {
        statusToken += 1
        statusMessage = message
        statusHideTask?.cancel()
        statusHideTask = Task { [weak self] in
            try? await Task.sleep(for: self?.statusHideDelay ?? .seconds(3))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    /// 动作成功后的默认反馈：仅当动作期间没有任何 showStatus 调用（token 未变）时才显示——
    /// 集成层在动作闭包内传回的失败/自定义文案优先，不被覆盖。判定按"串行动作"设计：
    /// 并发动作共享一个 token 通道时，后完成者的默认文案会被先完成者的上报吞掉
    /// （失败优先的取舍——回收站动作不并发发起，串行语义即实际语义）。
    private func showDefaultStatusIfUnreported(_ message: String, since token: Int) {
        guard statusToken == token else { return }
        showStatus(message)
    }

    /// 反馈文案的代次（showStatus 递增）：判定动作闭包是否已传回过文案。
    @ObservationIgnored private var statusToken = 0
}

/// 回收站视图（S3.5-05 的 UI 层，03 §16）：顶栏（标题 + 清空按钮）+ 操作反馈小字条
/// + 便签/待办两组已删条目列表；行 = 内容预览（≤2 行）+ 删除时间（RelativeTimeFormatter
/// 直接展示）+ 行尾恢复/永久删除按钮；空态 ContentUnavailableView。不可逆动作经
/// confirmationDialog 确认。模型由集成层注入并接线闭包；未接线时视图仍可安全显示。
struct TrashView: View {
    @Bindable var model: TrashModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let message = model.statusMessage {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                Divider()
            }
            content
        }
        .confirmationDialog(
            dialogTitle,
            isPresented: Binding(
                get: { model.confirmTarget != nil },
                set: { if !$0 { model.cancel() } }
            ),
            titleVisibility: .visible,
            presenting: model.confirmTarget
        ) { target in
            Button(role: .destructive) {
                // 弹窗收起回调（isPresented=false → cancel()）可能先于本任务执行并清空
                // confirmTarget——捕获 presented 目标走 confirm(_:)，不受竞态影响。
                Task { await model.confirm(target) }
            } label: {
                Text(target == .all ? String(localized: .mainTrashEmptyAll) : String(localized: .mainTrashDelete))
            }
            Button(role: .cancel) {
                model.cancel()
            } label: {
                Text(String(localized: .commonCancel))
            }
        }
        // 纸感底（三分区统一，见 paperSurface）。
        .paperSurface()
        // 订阅由视图挂载时启动（集成层装配时也可 start()，重复调用幂等）；
        // 不在 onDisappear 停——切换左栏入口不断流，与面板/主窗口其余入口同口径。
        .onAppear { model.start() }
    }

    /// 顶栏：标题（复用侧栏"回收站"键）+ 清空回收站按钮（无内容时禁用）。
    private var topBar: some View {
        HStack {
            Text(String(localized: .mainSectionTrash))
                .font(.headline)
            Spacer()
            Button(String(localized: .mainTrashEmptyAll)) {
                model.requestEmptyAll()
            }
            .disabled(isTrashEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// 空态（两组皆空）：回收站是空的。首帧未到渲染空白纸感底（W2）。
    @ViewBuilder
    private var content: some View {
        if !model.isLoaded {
            // 首帧未到（W2）：此时的"空"只是未加载——不显示空态也不放转圈。
            Color.clear
        } else if isTrashEmpty {
            ContentUnavailableView(String(localized: .mainTrashEmpty), systemImage: "trash")
        } else {
            list
        }
    }

    /// 两组列表：便签组在前、待办组在后（组内为流的降序）；组头与便签/待办分区的
    /// GroupHeader（带计数）同款。
    private var list: some View {
        List {
            if !model.deletedNotes.isEmpty {
                Section {
                    ForEach(model.deletedNotes) { note in
                        row(
                            preview: Text(note.content),
                            deletedAt: note.deletedAt ?? note.updatedAt,
                            onRestore: { Task { await model.requestRestoreNote(note.id) } },
                            onDelete: { model.requestDeleteNote(note.id) }
                        )
                    }
                } header: {
                    GroupHeader(title: String(localized: .mainTrashNotes), count: model.deletedNotes.count)
                }
            }
            if !model.deletedTodos.isEmpty {
                Section {
                    ForEach(model.deletedTodos) { todo in
                        row(
                            preview: Text(todo.title),
                            deletedAt: todo.deletedAt ?? todo.updatedAt,
                            onRestore: { Task { await model.requestRestoreTodo(todo.id) } },
                            onDelete: { model.requestDeleteTodo(todo.id) }
                        )
                    }
                } header: {
                    GroupHeader(title: String(localized: .mainTrashTodos), count: model.deletedTodos.count)
                }
            }
        }
        .listStyle(.inset)
        // 露出纸感底（与待办分区的 List 同款处理）。
        .scrollContentBackground(.hidden)
    }

    /// 回收站行：内容预览（最多约 2 行）+ 删除时间 + 行尾动作按钮。
    /// 相对时间随数据变化刷新；回收站低频访问，不引入计时刷新。
    private func row(
        preview: Text,
        deletedAt: Date,
        onRestore: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                preview
                    .font(.body)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(RelativeTimeFormatter.format(deletedAt, now: Date(), timeZone: model.timeZone))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(String(localized: .mainTrashRestore), action: onRestore)
            Button(String(localized: .mainTrashDelete), role: .destructive, action: onDelete)
        }
        .padding(.vertical, 2)
    }

    private var isTrashEmpty: Bool {
        model.deletedNotes.isEmpty && model.deletedTodos.isEmpty
    }

    /// 确认弹窗标题：清空与单条删除各有预插文案。
    private var dialogTitle: Text {
        switch model.confirmTarget {
        case .all:
            Text(String(localized: .mainTrashConfirmEmpty))
        case .note, .todo, .none:
            Text(String(localized: .mainTrashConfirmDelete))
        }
    }
}
