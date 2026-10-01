// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 便签列表（S1-05，03 §5）：「置顶」+「便签」两组（空组不显示）；纸感卡片行
/// （白卡片 + 左侧装订色条，时间在卡片角落）；单击原位编辑（光标就位），停止输入
/// 0.5 秒/失焦/收起面板时自动保存；右键菜单：编辑、置顶、复制、删除。
struct NoteListView: View {
    @Bindable var model: PanelModel

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !model.pinnedNotes.isEmpty {
                    Section {
                        ForEach(model.pinnedNotes) { item in
                            NoteRow(model: model, item: item)
                                .id(item.note.uuid.uuidString)
                        }
                    } header: {
                        GroupHeader(title: String(localized: .listGroupPinned), count: model.pinnedNotes.count)
                    }
                }
                if !model.unpinnedNotes.isEmpty {
                    Section {
                        ForEach(model.unpinnedNotes) { item in
                            NoteRow(model: model, item: item)
                                .id(item.note.uuid.uuidString)
                        }
                    } header: {
                        GroupHeader(title: String(localized: .listGroupNotes), count: model.unpinnedNotes.count)
                    }
                }
            }
            .listStyle(.sidebar)
            // 去掉 List 自带的半透明底，露出纸感渐变（2026-09-29）。
            .scrollContentBackground(.hidden)
            .onChange(of: model.recentlyCreatedItemID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID)
                }
            }
            // 搜索结果点击（S2-09）：滚动定位 + 1.5 秒高亮；挂载即定位（目标先于列表存在）。
            .onChange(of: model.locateNoteID, initial: true) { _, newID in
                if let newID {
                    proxy.scrollTo(newID)
                }
            }
        }
    }
}

/// 单行便签：纸感卡片（PaperCard 装订色条），展示态（前 3 行 + 角落修改时间）
/// 与编辑态（卡片上的原位编辑框，进入即聚焦）。
/// 编辑文字直接绑定模型（单一编辑通道），Esc/失焦/收起面板的保存读得到真实内容。
private struct NoteRow: View {
    @Bindable var model: PanelModel
    let item: NoteListItem

    @FocusState private var isFocused: Bool

    private var isEditing: Bool {
        model.editingNoteID == item.note.id
    }

    private var isRecentlyCreated: Bool {
        model.recentlyCreatedItemID == item.note.uuid.uuidString
    }

    /// 新建/定位高亮与 hover（hover 提示可点可右键）。
    @State private var isHovered = false
    /// 行入场状态（W6 动效表「新条目插入列表：行淡入+轻微上移 0.2s」）：
    /// 仅新条目做入场动效，旧行滚动进入不重复淡入。
    @State private var hasAppeared = false

    private var isHighlighted: Bool {
        isRecentlyCreated || model.locateNoteID == item.note.uuid.uuidString
    }

    var body: some View {
        Group {
            if isEditing {
                TextEditor(text: $model.editingNoteText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 13))
                    .frame(minHeight: 44)
                    .padding(.leading, 15)
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
                    .focused($isFocused)
                    .onChange(of: editingTextDebounceSeed) { _, _ in
                        scheduleAutosave()
                    }
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.note.content)
                        .font(.system(size: 13))
                        .lineLimit(3)
                    HStack(spacing: 4) {
                        // 已钉到桌面的图钉标记（S3-01）
                        if item.isPinnedToDesktop {
                            Image(systemName: "pin.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(Color.accentColor)
                        }
                        Spacer(minLength: 0)
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
                .onHover { isHovered = $0 }
                .onTapGesture {
                    startEditing()
                }
            }
        }
        .background(
            PaperCard(
                isHighlighted: isHighlighted,
                isHovered: isHovered && !isEditing,
                isActive: isEditing,
                edge: .binding
            )
        )
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 5)
        .onAppear {
            // 新条目入场（W6 动效表）；旧行直显。减弱动态效果时 Motion.gentle 直切。
            if isRecentlyCreated {
                withAnimation(Motion.gentle(0.2)) { hasAppeared = true }
            } else {
                hasAppeared = true
            }
        }
        .animation(Motion.gentle(0.2), value: isHighlighted)
        .onChange(of: model.editingNoteID) { _, _ in
            if isEditing {
                isFocused = true // 进入编辑：光标就位（03 §5）
            }
        }
        .onChange(of: isFocused) { _, focused in
            // 失焦（点击别处）：立即结束编辑并保存（03 §5 的第二个时机）。
            if !focused, isEditing {
                flushEditing()
            }
        }
        .contextMenu {
            Button(String(localized: .listMenuEdit)) {
                startEditing()
            }
            Button(item.note.pinnedAt == nil ? String(localized: .listMenuPin) : String(localized: .listMenuUnpin)) {
                Task { await model.setNotePinned(item.note.id, item.note.pinnedAt == nil) }
            }
            // 钉到桌面（S3-01，03 §10.2）：已钉显示"取消钉住"。
            Button(item.isPinnedToDesktop ? String(localized: .cardMenuUnpin) : String(localized: .cardMenuPinToDesktop)) {
                if item.isPinnedToDesktop {
                    Task { await model.unpinNoteFromDesktop(item.note.id) }
                } else {
                    Task { await model.pinNoteToDesktop(item.note.id) }
                }
            }
            Button(String(localized: .listMenuCopy)) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(item.note.content, forType: .string)
            }
            Divider()
            Button(String(localized: .listMenuDelete), role: .destructive) {
                Task { await model.deleteNote(item.note.id) }
            }
        }
        .onDisappear {
            saveDebounceTask?.cancel()
        }
    }

    /// 防抖种子：编辑文字变化时触发 0.5 秒自动保存（内容直接在模型上，无需回写）。
    private var editingTextDebounceSeed: String { model.editingNoteText }

    private func startEditing() {
        // 先 flush 正在编辑的其它行（03 §5：单击即改，同一时刻只有一行在编辑），
        // 再经仲裁器 claim（W4：其他面在编辑同一条时先收尾）并授权本行。
        model.beginNoteEditing(item.note.id, content: item.note.content)
    }

    /// 结束编辑并立即保存（失焦/Esc/收起面板共用；内容未变时 saveNoteContent 内部跳过）。
    private func flushEditing() {
        _ = model.endEditingIfNeeded()
    }

    /// 停止输入 0.5 秒后自动保存（03 §5）。
    private func scheduleAutosave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak model] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await model?.saveNoteContent(item.note.id, model?.editingNoteText ?? "")
        }
    }

    @State private var saveDebounceTask: Task<Void, Never>?
}
