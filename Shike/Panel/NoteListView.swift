// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 便签列表（S1-05，03 §5）：「置顶」+「便签」两组（空组不显示）；行显示内容前 3 行与相对修改时间；
/// 单击原位编辑（光标就位），停止输入 0.5 秒/失焦/收起面板时自动保存；右键菜单：编辑、置顶、复制、删除。
struct NoteListView: View {
    @Bindable var model: PanelModel

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !model.pinnedNotes.isEmpty {
                    Section(String(localized: .listGroupPinned)) {
                        ForEach(model.pinnedNotes) { item in
                            NoteRow(model: model, item: item)
                                .id(item.note.uuid.uuidString)
                        }
                    }
                }
                if !model.unpinnedNotes.isEmpty {
                    Section(String(localized: .listGroupNotes)) {
                        ForEach(model.unpinnedNotes) { item in
                            NoteRow(model: model, item: item)
                                .id(item.note.uuid.uuidString)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            // 可读性修复：去掉 List 自带的半透明底，露出面板实心底（2026-09-29）。
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

/// 单行便签：展示态（前 3 行 + 修改时间）与编辑态（原位编辑框，进入即聚焦）。
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

    /// 视觉批次：新建/定位高亮与 hover 底色（hover 提示可点可右键），高亮消失走淡出。
    @State private var isHovered = false

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
                    .focused($isFocused)
                    .onChange(of: editingTextDebounceSeed) { _, _ in
                        scheduleAutosave()
                    }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.note.content)
                        .font(.system(size: 13))
                        .lineLimit(3)
                    Text(RelativeTimeFormatter.format(
                        item.note.updatedAt,
                        now: Date(),
                        timeZone: model.timeZone
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .background(
                    Group {
                        if isHighlighted {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentColor.opacity(0.15))
                        } else if isHovered {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.primary.opacity(0.05))
                        }
                    }
                )
                .animation(Motion.gentle(0.2), value: isHighlighted)
                .animation(Motion.gentle(0.1), value: isHovered)
                .onHover { isHovered = $0 }
                .onTapGesture {
                    startEditing()
                }
            }
        }
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
        // 先 flush 正在编辑的其它行（03 §5：单击即改，同一时刻只有一行在编辑）。
        _ = model.endEditingIfNeeded()
        model.editingNoteID = item.note.id
        model.editingNoteText = item.note.content
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
