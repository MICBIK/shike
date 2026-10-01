// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import os
import ShikeData
import SwiftUI

/// 主窗口便签模型（S3.5-03）：消费便签观察流，派生搜索过滤与「置顶/全部」两组；
/// 编辑、置顶、钉桌面、删除等动作经注入闭包转发（S1-01 PanelModel 的
/// @ObservationIgnored 闭包接缝同款）。
/// 集成时闭包接 PanelModel 同名语义：清空保存=删除入撤销栈、失败上报——
/// 主窗口不重复实现数据语义，只做观察、派生与转发。
@MainActor
@Observable
final class MainNotesModel {
    /// 便签观察流来源（集成接 noteRepository.observeActive()；L2 可换替身流）。
    let observeNotes: () -> AsyncThrowingStream<[NoteListItem], any Error>

    // MARK: 注入的动作闭包（默认空实现供 L2 直接组装；集成由 App 接 PanelModel）

    /// 编辑保存（集成接 panelModel.saveNoteContent：内容未变跳过、清空=删除入撤销栈）。
    @ObservationIgnored var saveNoteContent: (Note.ID, String) -> Void = { _, _ in }
    /// 置顶/取消置顶。
    @ObservationIgnored var setNotePinned: (Note.ID, Bool) -> Void = { _, _ in }
    /// 钉到桌面。
    @ObservationIgnored var pinNoteToDesktop: (Note.ID) -> Void = { _ in }
    /// 取消钉住。
    @ObservationIgnored var unpinNoteFromDesktop: (Note.ID) -> Void = { _ in }
    /// 删除便签（软删除；撤销提示条语义在接收方）。
    @ObservationIgnored var deleteNote: (Note.ID) -> Void = { _ in }

    // MARK: 状态

    /// 观察流最新快照（仓储序：updatedAt 降序）。
    private(set) var notes: [NoteListItem] = []
    /// 搜索关键词（派生过滤见 filteredNotes；内存过滤，无需防抖）。
    var searchText: String = ""
    /// 正在原位编辑的便签（空则无编辑）。
    private(set) var editingNoteID: Note.ID?
    /// 编辑中的文字（视图 TextField 绑定；beginEditing 时以行内容播种）。
    var editingNoteText: String = ""

    /// 行内相对时间的时区（L2 可注入；同 PanelModel.timeZone，阶段 1 恒为 .current）。
    @ObservationIgnored var timeZone: TimeZone = .current
    /// 编辑自动保存的防抖时长（L2 注入缩短；0.5 秒与面板行内编辑一致）。
    @ObservationIgnored var saveDebounceDelay: Duration = .milliseconds(500)

    /// @ObservationIgnored + nonisolated(unsafe)（Task 取消本身 Sendable 安全）
    /// 只为让 deinit 能停止；模式同 PanelModel。
    @ObservationIgnored nonisolated(unsafe) private var noteTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var saveDebounceTask: Task<Void, Never>?

    init(observeNotes: @escaping () -> AsyncThrowingStream<[NoteListItem], any Error>) {
        self.observeNotes = observeNotes
    }

    // MARK: 派生：搜索过滤 + 分组

    /// 搜索过滤：大小写不敏感 contains；关键词首尾空白裁剪，空串不过滤。
    var filteredNotes: [NoteListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return notes }
        return notes.filter { $0.note.content.range(of: query, options: .caseInsensitive) != nil }
    }

    /// 「置顶」组：置顶时间降序（同 PanelModel.pinnedNotes）。
    var pinnedNotes: [NoteListItem] {
        filteredNotes
            .filter { $0.note.pinnedAt != nil }
            .sorted { ($0.note.pinnedAt ?? .distantPast) > ($1.note.pinnedAt ?? .distantPast) }
    }

    /// 「全部」组：过滤后的全部便签（含置顶，保持仓储的 updatedAt 降序）。
    var allNotes: [NoteListItem] { filteredNotes }

    // MARK: 观察流消费

    /// 启动消费（视图 .task 挂载时调用；重复调用先取消上一个任务）。
    func start() {
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            await self?.consumeNotes()
        }
    }

    /// 停止消费（视图 onDisappear / 窗口关闭），同时取消防抖保存任务。
    /// 先冲刷在编辑内容（幂等，无编辑时零开销）——调用方不必记得先收尾，
    /// 防抖窗内的最后一次编辑不因停止消费而丢失。
    func stop() {
        endEditing()
        noteTask?.cancel()
        noteTask = nil
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
    }

    private func consumeNotes() async {
        await runNotes(observeNotes())
    }

    /// 消费一个便签观察流。internal 供 L2 直接驱动真实流（确定性断言首帧）。
    func runNotes(_ stream: AsyncThrowingStream<[NoteListItem], any Error>) async {
        do {
            for try await items in stream {
                notes = items
                // 正在编辑的行已从流中消失（如清空保存=删除后行被移除）：复位编辑态，
                // 避免随后的防抖/失焦对已删行继续转发保存。
                if let editingID = editingNoteID, !items.contains(where: { $0.id == editingID }) {
                    saveDebounceTask?.cancel()
                    editingNoteID = nil
                    editingNoteText = ""
                }
            }
            // data-layer.md「观察」：非取消的正常结束是故障信号——兜底记日志，
            // 防止数据层语义变化后静默失效（模式同 CardManager 的观察流收尾）。
            guard !Task.isCancelled else { return }
            Log.app.error("主窗口便签观察流非取消正常结束（应为故障信号）")
        } catch is CancellationError {
            // stop()/视图销毁的取消不算失败。
        } catch {
            Log.app.error("主窗口便签观察流异常结束：\(String(describing: error), privacy: .public)")
        }
    }

    deinit {
        // Task.cancel 是 nonisolated 的，可在 deinit 调用。观察任务常驻使 deinit
        // 实际不可达（所有权为 app 生命周期，不经 stop() 不释放）；防抖任务可达
        // （sleep 期弱持有）——保留 cancel 作为对称防御，勿依赖它兜底观察。
        noteTask?.cancel()
        saveDebounceTask?.cancel()
    }

    // MARK: 原位编辑

    /// 单击行进入原位编辑（同一时刻只有一行在编辑）：先收尾上一行并立即保存，
    /// 再以该行当前内容播种编辑文字。
    func beginEditing(_ id: Note.ID) {
        guard editingNoteID != id else { return } // 已在编辑本行：保留进行中的文字
        endEditing()
        editingNoteID = id
        editingNoteText = notes.first(where: { $0.id == id })?.note.content ?? ""
    }

    /// 结束编辑：取消防抖并立即转发保存（失焦/Esc/开始编辑另一行共用）。
    /// 内容未变跳过、清空=删除的语义在接收方（panelModel.saveNoteContent）。
    func endEditing() {
        saveDebounceTask?.cancel()
        saveDebounceTask = nil
        guard let id = editingNoteID else { return }
        let text = editingNoteText
        // 复位编辑态与文字清空同帧完成：行的编辑分支随即卸载，TextField 的
        // onChange 不会对复位产生的空串再排一次保存（避免"结束编辑即误删"）。
        editingNoteID = nil
        editingNoteText = ""
        saveNoteContent(id, text)
    }

    /// 编辑文字变化（视图 TextField.onChange 调用）：0.5 秒防抖后转发保存闭包。
    /// 防抖刻意做在模型层而非视图层——保存闭包的接收方（集成时为 panelModel.saveNoteContent）
    /// 自身无防抖（面板的防抖在其视图层）；若将来接收方自带防抖，把本方法改为直接转发即可。
    /// 仅编辑中的行受理：编辑态复位瞬间迟到的 onChange 不会对刚结束的行误存（含空串误删）。
    func saveContent(_ id: Note.ID, _ text: String) {
        guard editingNoteID == id else { return }
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak self] in
            try? await Task.sleep(for: self?.saveDebounceDelay ?? .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNoteContent(id, text)
        }
    }
}

/// 主窗口便签视图（S3.5-03）：顶部搜索框 +「置顶/全部」两组纸感卡片列表。
/// 只做两栏布局的内容区（左栏是 MainRootView 的事）；视觉跟随面板纸感
/// （复用 PaperCard 装订色条与 GroupHeader），交互与面板便签行同语义：
/// 单击原位编辑（失焦/Esc 结束、变化即存）、右键菜单一致、行删除按钮。
struct MainNotesView: View {
    @Bindable var model: MainNotesModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        // 窗口宽度自适应：内容区最小 320，随窗口拉伸（设计值）。
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        // 纸感底（三分区统一，见 paperSurface）：纸青渐变垫厚材质。
        .paperSurface()
        // 订阅由视图挂载时启动（重复调用幂等）；不在 onDisappear 停——切换左栏
        // 入口不断流，与待办/回收站/面板常驻订阅同口径，编辑防抖也不被切换打断。
        .onAppear { model.start() }
    }

    // MARK: 搜索框

    /// 顶部搜索框（placeholder「搜索便签」）：纸感容器 + 常驻放大镜，非空可一键清空。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.65))
            TextField(String(localized: .mainNotesSearch), text: $model.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
            if !model.searchText.isEmpty {
                Button {
                    model.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(String(localized: .searchClear)))
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color("CardBackground").opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Color.accentColor.opacity(0.22), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 内容区

    @ViewBuilder
    private var content: some View {
        if model.notes.isEmpty {
            // 空态（S3.5-03 AC）：还没有便签，从菜单栏面板记一条吧。
            ContentUnavailableView {
                Label(String(localized: .mainSectionNotes), systemImage: "note.text")
            } description: {
                Text(String(localized: .mainNotesEmpty))
            }
        } else {
            noteList
        }
    }

    /// 两组列表（置顶在前列，空组不显示）。置顶组与全部组含同一条置顶便签，
    /// 用 ScrollView + LazyVStack 手工排版而非 List，避开同 ID 跨 Section 的行身份冲突；
    /// 编辑器只保留一份——全部组里的置顶便签渲染展示态（allowsEditing=false），
    /// 避免两份行的 FocusState 竞争把刚进入的编辑立刻失焦收尾。
    private var noteList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if !model.pinnedNotes.isEmpty {
                    section(title: String(localized: .listGroupPinned), items: model.pinnedNotes) { _ in true }
                }
                if !model.allNotes.isEmpty {
                    section(title: String(localized: .mainNotesGroupAll), items: model.allNotes) { item in
                        item.note.pinnedAt == nil // 置顶便签的编辑入口在置顶组那份
                    }
                } else {
                    // 搜索无命中（快照非空但过滤为空）：复用面板搜索的空结果文案。
                    searchNoResults
                }
            }
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private func section(
        title: String,
        items: [NoteListItem],
        allowsEditing: @escaping (NoteListItem) -> Bool
    ) -> some View {
        GroupHeader(title: title, count: items.count)
            .padding(.leading, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
        ForEach(items) { item in
            MainNoteRow(model: model, item: item, allowsEditing: allowsEditing(item))
        }
    }

    /// 搜索无命中的轻提示（文案与「清空」按钮复用面板搜索既有键）。
    private var searchNoResults: some View {
        VStack(spacing: 8) {
            Text(String(localized: .searchEmpty(model.searchText)))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(String(localized: .searchClear)) {
                model.searchText = ""
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
    }
}

/// 主窗口便签行：纸感卡片（复用面板 PaperCard 装订色条），展示态为内容 3 行预览
/// + 置顶图钉 + 相对时间（hover 出删除按钮）；单击原位编辑（编辑态与展示态同位置，
/// 失焦/Esc 结束，变化经模型防抖保存）；右键菜单与面板便签行一致。
private struct MainNoteRow: View {
    @Bindable var model: MainNotesModel
    let item: NoteListItem
    /// 本行是否承担编辑器（置顶便签在两组各有一份行，只让一份渲染编辑框，
    /// 避免双 FocusState 竞争把刚进入的编辑立即失焦收尾）。
    var allowsEditing: Bool

    @FocusState private var isFocused: Bool
    @State private var isHovered = false

    private var isEditing: Bool {
        model.editingNoteID == item.note.id
    }

    var body: some View {
        Group {
            if isEditing && allowsEditing {
                editor
            } else {
                display
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            PaperCard(
                isHovered: isHovered && !isEditing,
                isActive: isEditing,
                edge: .binding
            )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu { menu }
        .onChange(of: model.editingNoteID) { _, _ in
            if isEditing && allowsEditing {
                isFocused = true // 进入编辑：光标就位（同面板；非编辑器副本不抢焦点）
            }
        }
        .onChange(of: isFocused) { _, focused in
            // 失焦（点击别处）：立即结束编辑并保存（同面板的收尾时机）。
            // 非编辑器副本（allowsEditing=false）不持有焦点，守卫只是防御。
            if !focused, isEditing, allowsEditing {
                model.endEditing()
            }
        }
    }

    /// 展示态：内容 3 行预览 + 钉桌面图钉（同面板 NoteListView 的 pin.fill 语义——
    /// 标记"钉到桌面"，置顶状态由组头表达）+ 相对时间。
    private var display: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.note.content)
                .font(.system(size: 13))
                .lineLimit(3)
            HStack(spacing: 4) {
                if item.isPinnedToDesktop {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                if isHovered {
                    // 行删除按钮：与菜单删除同走注入的 deleteNote（撤销语义在接收方）。
                    Button {
                        model.deleteNote(item.note.id)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(String(localized: .listMenuDelete)))
                }
                Text(RelativeTimeFormatter.format(
                    item.note.updatedAt,
                    now: Date(),
                    timeZone: model.timeZone
                ))
                .font(.system(size: 10.5))
                .foregroundStyle(Color("CardMeta"))
            }
        }
        .padding(.leading, 15)
        .padding(.trailing, 12)
        .padding(.top, 9)
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            // 非编辑器副本不响应单击编辑（编辑入口在承担编辑器的那份行/右键菜单）。
            if allowsEditing {
                model.beginEditing(item.note.id)
            }
        }
    }

    /// 编辑态：展示态同位置的原位编辑框（多行、进入即聚焦；Esc 结束）。
    private var editor: some View {
        TextField("", text: $model.editingNoteText, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .lineLimit(1...6)
            .padding(.leading, 15)
            .padding(.trailing, 12)
            .padding(.vertical, 6)
            .focused($isFocused)
            .onExitCommand {
                // Esc：结束编辑并立即保存（同卡片编辑的收尾时机）。
                model.endEditing()
            }
            .onChange(of: model.editingNoteText) { _, newText in
                // 变化即交模型保存（防抖在模型层，见 MainNotesModel.saveContent；
                // beginEditing 的播种与本行未编辑时由模型的编辑态守卫挡下）。
                model.saveContent(item.note.id, newText)
            }
    }

    /// 右键菜单（与面板便签行一致：编辑/置顶/钉桌面/复制/删除，键全部复用）。
    @ViewBuilder
    private var menu: some View {
        Button(String(localized: .listMenuEdit)) {
            model.beginEditing(item.note.id)
        }
        Button(item.note.pinnedAt == nil ? String(localized: .listMenuPin) : String(localized: .listMenuUnpin)) {
            model.setNotePinned(item.note.id, item.note.pinnedAt == nil)
        }
        // 钉到桌面：已钉显示「取消钉住」（同面板）。
        Button(item.isPinnedToDesktop ? String(localized: .cardMenuUnpin) : String(localized: .cardMenuPinToDesktop)) {
            if item.isPinnedToDesktop {
                model.unpinNoteFromDesktop(item.note.id)
            } else {
                model.pinNoteToDesktop(item.note.id)
            }
        }
        Button(String(localized: .listMenuCopy)) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(item.note.content, forType: .string)
        }
        Divider()
        Button(String(localized: .listMenuDelete), role: .destructive) {
            model.deleteNote(item.note.id)
        }
    }
}
