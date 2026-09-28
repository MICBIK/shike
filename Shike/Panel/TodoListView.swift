// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 待办列表（S1-06，03 §6）：「待办」+「已完成（N）」（默认折叠、空组不显示）；
/// 行 = 圆圈按钮 + 标题；勾选立即划线变灰、1 秒后移组、期间可勾回；单击标题原位单行编辑；
/// 右键菜单：编辑、删除。
struct TodoListView: View {
    @Bindable var model: PanelModel
    @State private var isCompletedSectionExpanded = false

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !model.activeTodos.isEmpty {
                    Section(String(localized: .listGroupTodos)) {
                        ForEach(model.activeTodos) { todo in
                            TodoRow(model: model, todo: todo)
                                .id(todo.uuid.uuidString)
                        }
                    }
                }
                if !model.completedTodos.isEmpty {
                    Section {
                        if isCompletedSectionExpanded {
                            ForEach(model.completedTodos) { todo in
                                TodoRow(model: model, todo: todo)
                                    .id(todo.uuid.uuidString)
                            }
                        }
                    } header: {
                        Button {
                            isCompletedSectionExpanded.toggle()
                        } label: {
                            HStack {
                                Image(systemName: isCompletedSectionExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption)
                                Text(String(localized: .listGroupCompleted(model.completedTodos.count)))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: model.recentlyCreatedItemID) { _, newID in
                if let newID {
                    proxy.scrollTo(newID)
                }
            }
        }
    }
}

/// 单行待办：圆圈（完成/勾回）+ 标题；编辑态为原位单行编辑框。
private struct TodoRow: View {
    @Bindable var model: PanelModel
    let todo: Todo

    @FocusState private var isFocused: Bool

    /// 视觉上的完成态：勾选后立即生效（数据 1 秒后才落库）。
    private var isVisuallyCompleted: Bool {
        todo.completedAt != nil || model.pendingCompletionIDs.contains(todo.id)
    }

    private var isEditing: Bool {
        model.editingTodoID == todo.id
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                model.toggleTodoCompletion(todo.id)
            } label: {
                Image(systemName: isVisuallyCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isVisuallyCompleted ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)

            if isEditing {
                TextField("", text: $model.editingTodoText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .focused($isFocused)
                    .onSubmit {
                        flushEditing()
                    }
                    .onChange(of: model.editingTodoText) { _, _ in
                        scheduleAutosave() // 0.5 秒防抖（FR44：防抖同便签）
                    }
            } else {
                Text(todo.title)
                    .font(.system(size: 13))
                    .strikethrough(isVisuallyCompleted)
                    .foregroundStyle(isVisuallyCompleted ? Color.secondary : Color.primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startEditing()
                    }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .background(
            model.recentlyCreatedItemID == todo.uuid.uuidString ? Color.accentColor.opacity(0.15) : .clear
        )
        .onChange(of: model.editingTodoID) { _, _ in
            if isEditing {
                isFocused = true
            }
        }
        .onChange(of: isFocused) { _, focused in
            if !focused, isEditing {
                flushEditing()
            }
        }
        .contextMenu {
            Button(String(localized: .listMenuEdit)) {
                startEditing()
            }
            Divider()
            Button(String(localized: .listMenuDelete), role: .destructive) {
                Task { await model.deleteTodo(todo.id) }
            }
        }
    }

    private func startEditing() {
        _ = model.endEditingIfNeeded()
        model.editingTodoID = todo.id
        model.editingTodoText = todo.title
    }

    private func flushEditing() {
        _ = model.endEditingIfNeeded()
    }

    /// 停止输入 0.5 秒后自动保存（FR44：防抖同便签；onSubmit/失焦/Esc 仍立即保存）。
    private func scheduleAutosave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { [weak model] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await model?.saveTodoTitle(todo.id, model?.editingTodoText ?? "")
        }
    }

    @State private var saveDebounceTask: Task<Void, Never>?
}
