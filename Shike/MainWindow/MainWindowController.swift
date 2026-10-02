// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ShikeData
import SwiftUI
import UniformTypeIdentifiers
import os

/// 主窗口左栏三入口（03 §16.2，S3.5-02）：选中态记忆在 @AppStorage。
enum MainSection: String, CaseIterable, Identifiable {
    case notes
    case todos
    case trash

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: String(localized: .mainSectionNotes)
        case .todos: String(localized: .mainSectionTodos)
        case .trash: String(localized: .mainSectionTrash)
        }
    }

    var icon: String {
        switch self {
        case .notes: "note.text"
        case .todos: "checklist"
        case .trash: "trash"
        }
    }
}

/// 主窗口内容（03 §16，ADR-023：面板承载全部现有能力，主窗口只做增量）。
/// 左栏三入口 + 右侧内容区（S3.5-03/04/05 三视图）+ 工具栏导出（S3.5-06）。
struct MainRootView: View {
    @AppStorage("main.section") private var section: MainSection = .notes

    /// 三入口模型（数据流与动作闭包由 MainWindowController 接线后注入）。
    var notesModel: MainNotesModel
    var todosModel: MainTodosModel
    var trashModel: TrashModel
    /// 统一反馈条（W3）：导出成败、读失败、写失败旁路的唯一文案来源。
    var feedbackModel: MainFeedbackModel
    /// 导出动作以闭包注入（S3.5-06）：快照与 NSSavePanel 的窗口挂载留在控制器层，视图保持可测。
    var exportMarkdown: () -> Void = {}
    var exportJSON: () -> Void = {}

    init(
        notesModel: MainNotesModel,
        todosModel: MainTodosModel,
        trashModel: TrashModel,
        feedbackModel: MainFeedbackModel,
        exportMarkdown: @escaping () -> Void = {},
        exportJSON: @escaping () -> Void = {}
    ) {
        self.notesModel = notesModel
        self.todosModel = todosModel
        self.trashModel = trashModel
        self.feedbackModel = feedbackModel
        self.exportMarkdown = exportMarkdown
        self.exportJSON = exportJSON
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(MainSection.allCases) { entry in
                    Label(entry.title, systemImage: entry.icon)
                        .tag(entry)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .listStyle(.sidebar)
        } detail: {
            switch section {
            case .notes:
                MainNotesView(model: notesModel)
            case .todos:
                MainTodosView(model: todosModel)
            case .trash:
                TrashView(model: trashModel)
            }
        }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button(String(localized: .mainExportMarkdown)) { exportMarkdown() }
                    Button(String(localized: .mainExportJson)) { exportJSON() }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .accessibilityLabel(Text(String(localized: .mainExportMenu)))
                }
            }
        }
        // 底部统一反馈条（W3）：导出成功/失败、回收站写失败、三模型读失败、
        // 面板写失败旁路都写 feedbackModel（3 秒自清）；回收站分区内部的
        // 同源展示照旧（TrashView 顶部小字条）——同一条失败在回收站分区
        // 两处同文案时底部条让位（打磨 R3：同屏不重复显示同一句话，
        // 两通道同一 tick 写入、同时长自清，去重窗口即显示窗口）。
        .safeAreaInset(edge: .bottom) {
            if let message = feedbackModel.message,
               !(section == .trash && message == trashModel.statusMessage)
            {
                VStack(spacing: 0) {
                    Divider()
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }
}

/// 主窗口单例（03 §16.1，S3.5-01）：右键菜单/设置打开；已有窗口前置聚焦，不重复开窗；
/// 尺寸与位置经 frameAutosave 记住；关闭只是关窗，拾刻继续驻留菜单栏（重开状态都在——
/// 控制器与窗口常驻，仅 orderOut/重前置）。
@MainActor
final class MainWindowController {
    private var window: NSWindow?

    /// 主窗口三入口的模型（S3.5-03~05）：构造时按接线表接好——便签/待办动作接
    /// PanelModel 同语义（清空保存=删除入撤销栈、完成清提醒等数据语义只在面板实现一次），
    /// 回收站写路径接 TrashRepository、失败经 showStatus 回传文案。
    let notesModel: MainNotesModel
    let todosModel: MainTodosModel
    let trashModel: TrashModel
    /// 统一反馈条（W3）：底部 safeAreaInset 的唯一文案来源（MainRootView 渲染）。
    let feedback: MainFeedbackModel

    /// 待办「编辑/设置时间」先呼出面板再定位（主窗口不做编辑器，03 §16.7）。
    /// 面板与状态项归 AppDelegate 所有，装配完成后注入（组合方式与通知定位
    /// openPanelHandler、卡片 showInPanelHandler 一致）；未注入时仅定位不呼出。
    var openPanelHandler: (() -> Void)?

    /// 导出快照的流来源与显示时区（app 生命周期常驻）。
    private let environment: AppEnvironment

    /// 导出格式（S3.5-06）。
    private enum ExportFormat {
        case markdown
        case json
    }

    init(environment: AppEnvironment) {
        self.environment = environment
        let panelModel = environment.panelModel
        let noteRepository = environment.noteRepository
        let todoRepository = environment.todoRepository
        let trashRepository = environment.trashRepository
        let feedback = MainFeedbackModel()
        self.feedback = feedback

        // 读失败（W3）：三模型观察流失败经注入闭包上报（文案 main.read.failed）；
        // 接线在下方三模型装配完成后统一挂（notesModel/todosModel/trashModel 皆是局部 let）。
        let showReadFailure: () -> Void = { [weak feedback] in
            feedback?.show(String(localized: .mainReadFailed))
        }

        // —— 便签（S3.5-03）：观察流接仓储；async 动作一律 Task 包装，
        //    [weak panelModel] 防闭包随模型常驻而拉长面板生命周期。
        let notesModel = MainNotesModel(observeNotes: { [noteRepository] in
            noteRepository.observeActive()
        })
        notesModel.saveNoteContent = { [weak panelModel] id, text in
            Task { await panelModel?.saveNoteContent(id, text) }
        }
        notesModel.setNotePinned = { [weak panelModel] id, pinned in
            Task { await panelModel?.setNotePinned(id, pinned) }
        }
        // 钉桌面/取消钉住：PanelModel 的同名闭包已由 AppEnvironment 接到卡片创建链。
        notesModel.pinNoteToDesktop = { [weak panelModel] id in
            Task { await panelModel?.pinNoteToDesktop(id) }
        }
        notesModel.unpinNoteFromDesktop = { [weak panelModel] id in
            Task { await panelModel?.unpinNoteFromDesktop(id) }
        }
        notesModel.deleteNote = { [weak panelModel] id in
            Task { await panelModel?.deleteNote(id) }
        }
        self.notesModel = notesModel

        // —— 待办（S3.5-04）。时区保持模型默认 .current：阶段 1 口径同
        //    PanelModel.timeZone（恒 .current，Options.timeZone 接线时两处一起改）。
        let todosModel = MainTodosModel()
        todosModel.observeTodos = { [todoRepository] in
            todoRepository.observeActive()
        }
        // 勾选接面板的三态切换（toggleTodoCompletion：待移入 1 秒可勾回，docs/03 §6/§16.4
        // 同语义）——Bool 目标态由面板按自身快照与待移入窗仲裁；主窗口行随观察流推送移组。
        todosModel.toggleComplete = { [weak panelModel] id, _ in
            panelModel?.toggleTodoCompletion(id)
        }
        // 勾选即时反馈（打磨二轮 B3，卡B 移交卡A 实施）：主窗口行读 panel.pendingCompletionIDs
        // 渲染待移入窗内的划线变灰，与面板行同节奏（方案见审查审计-打磨二轮 卡B节 B3）。
        todosModel.panel = panelModel
        todosModel.delete = { [weak panelModel] id in
            Task { await panelModel?.deleteTodo(id) }
        }
        self.todosModel = todosModel

        // 稍后提醒：面板待办行无此菜单项，主窗口同口径不提供，保持 nil。

        // —— 回收站（S3.5-05）：写路径接 TrashRepository；throws 失败转 main.trash.failed
        //    文案：trashModel.showStatus 供回收站分区内部的同源展示（照旧），
        //    feedback.show 供底部统一反馈条（W3——与分区展示同文案，双通道保证可见）。
        //    闭包存于 trashModel 自身，[weak trashModel] 防模型→闭包→模型循环引用。
        let trashModel = TrashModel()
        trashModel.observeNotes = { [trashRepository] in
            trashRepository.observeNotes()
        }
        trashModel.observeTodos = { [trashRepository] in
            trashRepository.observeTodos()
        }
        trashModel.readFailureHandler = showReadFailure
        trashModel.restoreNote = { [weak trashModel, trashRepository, feedback] id in
            do { try await trashRepository.restoreNote(id) }
            catch {
                Log.app.error("恢复便签失败：\(String(describing: error), privacy: .public)")
                trashModel?.showStatus(String(localized: .mainTrashFailed))
                feedback.show(String(localized: .mainTrashFailed))
            }
        }
        trashModel.restoreTodo = { [weak trashModel, trashRepository, feedback] id in
            do { try await trashRepository.restoreTodo(id) }
            catch {
                Log.app.error("恢复待办失败：\(String(describing: error), privacy: .public)")
                trashModel?.showStatus(String(localized: .mainTrashFailed))
                feedback.show(String(localized: .mainTrashFailed))
            }
        }
        trashModel.permanentlyDeleteNote = { [weak trashModel, trashRepository, feedback] id in
            do { try await trashRepository.permanentlyDeleteNote(id) }
            catch {
                Log.app.error("永久删除便签失败：\(String(describing: error), privacy: .public)")
                trashModel?.showStatus(String(localized: .mainTrashFailed))
                feedback.show(String(localized: .mainTrashFailed))
            }
        }
        trashModel.permanentlyDeleteTodo = { [weak trashModel, trashRepository, feedback] id in
            do { try await trashRepository.permanentlyDeleteTodo(id) }
            catch {
                Log.app.error("永久删除待办失败：\(String(describing: error), privacy: .public)")
                trashModel?.showStatus(String(localized: .mainTrashFailed))
                feedback.show(String(localized: .mainTrashFailed))
            }
        }
        trashModel.emptyAll = { [weak trashModel, trashRepository, feedback] in
            do { try await trashRepository.emptyTrash() }
            catch {
                Log.app.error("清空回收站失败：\(String(describing: error), privacy: .public)")
                trashModel?.showStatus(String(localized: .mainTrashFailed))
                feedback.show(String(localized: .mainTrashFailed))
            }
        }
        self.trashModel = trashModel
        // 时区统一走面板口径（阶段 1 恒 .current；Options.timeZone 接线时随面板一并改）。
        trashModel.timeZone = panelModel.timeZone
        notesModel.timeZone = panelModel.timeZone
        // 三面编辑互斥（W4）：主窗口便签行的仲裁器接环境级单份（面板/卡片侧已接）。
        notesModel.editArbiter = environment.editArbiter
        // 读失败上报（W3）：三模型统一挂同一闭包（feedback 弱持有）。
        notesModel.readFailureHandler = showReadFailure
        todosModel.readFailureHandler = showReadFailure

        // 编辑/设置时间：呼出面板并沿用面板行菜单的同款行为（右键菜单与面板一致，
        // 03 §16.4）——编辑→面板行内编辑态；设置时间→面板时间弹层；定位高亮让用户
        // 看到目标行。id→Todo 经主窗口自己的快照映射（行本就由它渲染，必在快照内），
        // 不依赖面板流的健康度。放在 init 末尾：弱捕获 self 需存储属性全部初始化完成。
        todosModel.edit = { [weak self, weak panelModel] id in
            guard let self, let panelModel,
                  let todo = self.todosModel.todos.first(where: { $0.id == id }) else { return }
            self.openPanelHandler?()
            _ = panelModel.endEditingIfNeeded()
            panelModel.locateTodo(uuid: todo.uuid)
            panelModel.editingTodoID = todo.id
            panelModel.editingTodoText = todo.title
        }
        todosModel.setTime = { [weak self, weak panelModel] id in
            guard let self, let panelModel,
                  let todo = self.todosModel.todos.first(where: { $0.id == id }) else { return }
            self.openPanelHandler?()
            _ = panelModel.endEditingIfNeeded()
            panelModel.locateTodo(uuid: todo.uuid)
            panelModel.editingTimeTarget = todo
        }

        // 写失败旁路（W3）：面板收着时主窗口也要可见。主窗口可见（或尚未创建——
        // 3 秒自清保证不会留下过期文案）才显示；文案与面板横幅同源
        // （banner.saveFailed + ErrorText.reason）。面板横幅保留不动。
        // 放在 init 末尾：弱捕获 self 需存储属性全部初始化完成。
        panelModel.writeFailureHandler = { [weak feedback, weak self] reason in
            guard let feedback, self?.window?.isVisible != false else { return }
            feedback.show(String(localized: .bannerSaveFailed(ErrorText.reason(reason))))
        }
    }

    /// 退出前同步冲刷主窗口便签在编辑内容（W1 数据安全）：取走在编辑快照
    /// （takePendingEdit 复位编辑态与防抖）后经 SyncFlush 同步等待落库——
    /// 同面板保存语义（空→软删除、未变跳过，比对基准是本模型快照），
    /// 不再走 saveNoteContent 的 fire-and-forget 通道。超时/失败记日志。
    func endEditingIfNeeded() {
        guard let edit = notesModel.takePendingEdit() else { return }
        SyncFlush.noteContent(
            edit.id,
            text: edit.text,
            snapshotContent: edit.snapshotContent,
            repository: environment.noteRepository
        )
    }

    /// 退出前停止主窗口模型的观察消费与跨天/唤醒观察者（进程退出场景下
    /// 仅为语义收尾，观察任务本会随进程消亡）。
    func stop() {
        notesModel.stop()
        todosModel.stop()
        trashModel.stop()
    }

    func show() {
        if let window {
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: .appName) // 应用名不翻译（键值即"拾刻"）
        // 控制器强持有窗口：关掉默认的 close-即-release，避免 ARC 下过释放（打磨 P1）
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(
            rootView: MainRootView(
                notesModel: notesModel,
                todosModel: todosModel,
                trashModel: trashModel,
                feedbackModel: feedback,
                exportMarkdown: { [weak self] in self?.runExport(.markdown) },
                exportJSON: { [weak self] in self?.runExport(.json) }
            )
        )
        // 记住尺寸与位置：返回 false 表示没有已存 frame，居中放置
        if !window.setFrameAutosaveName("Main Window") {
            window.center()
        }
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    // - MARK: 导出（S3.5-06）

    /// 导出：取观察流首帧快照（订阅即推当前值，首帧即全量）→ NSSavePanel 以 sheet
    /// 挂主窗口 → 写盘。成功/失败反馈经统一反馈条 feedback（W3，3 秒自清）；
    /// 用户取消保存面板则无操作无反馈。
    private func runExport(_ format: ExportFormat) {
        guard let window else { return }
        Task { [feedback] in
            do {
                let notes = try await snapshotNotes()
                let todos = try await snapshotTodos()
                let generatedAt = Date()
                let panel = NSSavePanel()
                let content: Data
                switch format {
                case .markdown:
                    // UTType.markdown 在 CI 的 Xcode 26 SDK 上不可用（本地 27 门控），
                    // 用扩展名等价构造（"md" 恒解析为 net.daringfireball.markdown）。
                    if let markdownType = UTType(filenameExtension: "md") {
                        panel.allowedContentTypes = [markdownType]
                    }
                    // 文件名属数据制品命名（"拾刻导出 …"），同 ExportService 节标题口径，不进本地化。
                    panel.nameFieldStringValue = "拾刻导出 \(Self.fileDate(generatedAt, timeZone: environment.panelModel.timeZone)).md"
                    // 文档导出按显示时区落日期（同面板行时间的时区口径）。
                    content = Data(ExportService.markdown(
                        notes: notes,
                        todos: todos,
                        generatedAt: generatedAt,
                        timeZone: environment.panelModel.timeZone
                    ).utf8)
                case .json:
                    panel.allowedContentTypes = [.json]
                    panel.nameFieldStringValue = "拾刻导出 \(Self.fileDate(generatedAt, timeZone: environment.panelModel.timeZone)).json"
                    content = try ExportService.json(notes: notes, todos: todos, generatedAt: generatedAt)
                }
                let response = await panel.beginSheetModal(for: window)
                guard response == .OK, let url = panel.url else { return }
                do {
                    try content.write(to: url, options: .atomic)
                    feedback.show(String(localized: .mainExportDone(url.path)))
                } catch {
                    Log.app.error("导出写盘失败：\(String(describing: error), privacy: .public)")
                    feedback.show(String(localized: .mainExportFailed))
                }
            } catch {
                Log.app.error("导出失败：\(String(describing: error), privacy: .public)")
                feedback.show(String(localized: .mainExportFailed))
            }
        }
    }

    /// 便签首帧快照：NoteListItem 拆出 Note（导出只需要域类型本体）。
    /// 经迭代器取首帧（本工具链 AsyncSequence 无 next() 便捷成员）。
    private func snapshotNotes() async throws -> [Note] {
        var iterator = environment.noteRepository.observeActive().makeAsyncIterator()
        guard let items = try await iterator.next() else { return [] }
        return items.map(\.note)
    }

    /// 待办首帧快照（observeActive 同款订阅即推当前值）。
    private func snapshotTodos() async throws -> [Todo] {
        var iterator = environment.todoRepository.observeActive().makeAsyncIterator()
        guard let todos = try await iterator.next() else { return [] }
        return todos
    }

    /// 导出文件名日期：yyyy-MM-dd（固定 en_US_POSIX 防区域设置改写字段序，同导出服务口径）。
    /// internal 供 L2 断言（时区显式注入，与导出正文的 panelModel.timeZone 同源）。
    static func fileDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
