// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 待办列表（S2-06，03 §6）：「逾期（红）」「今天」「以后」「无日期」「已完成（N）」
/// （默认折叠、空组不显示）；行 = 圆圈按钮 + 标题 + 时间；勾选立即划线变灰、1 秒后移组、
/// 期间可勾回；单击标题原位单行编辑；右键菜单：编辑、删除（设置时间… 随 3.7 加入）。
struct TodoListView: View {
    @Bindable var model: PanelModel
    @State private var isCompletedSectionExpanded = false

    var body: some View {
        // 一次求值（7 处引用局部值）：避免每处 access 各自重算与跨午夜单帧不一致（盲审 F2）
        let groups = model.todoGroups
        return ScrollViewReader { proxy in
            List {
                section(title: String(localized: .listGroupOverdue), todos: groups.overdue, isOverdue: true)
                section(title: String(localized: .listGroupToday), todos: groups.today)
                section(title: String(localized: .listGroupLater), todos: groups.later)
                section(title: String(localized: .listGroupNoDate), todos: groups.noDate)
                if !groups.completed.isEmpty {
                    Section {
                        if isCompletedSectionExpanded {
                            ForEach(groups.completed) { todo in
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
                                Text(String(localized: .listGroupCompleted(groups.completed.count)))
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
            // 通知点本体（S2-04）：滚动定位 + 1.5 秒高亮（PanelModel 负责清除计时）。
            // initial: true——定位目标在列表挂载前已设置（模式切换/冷启动路径）时，
            // 挂载即定位一次（盲审 F2：onChange 默认不响应既有值）。
            .onChange(of: model.locateTodoID, initial: true) { _, newID in
                if let newID {
                    proxy.scrollTo(newID)
                }
            }
            // 设置时间弹层（S2-07）：锚定列表；清除时间时弹层随 editingTimeTarget 置空关闭。
            .popover(item: $model.editingTimeTarget) { todo in
                TodoTimeEditorView(todo: todo, model: model)
                    .id(todo.id) // 非 nil→非 nil 切换不复用旧状态（盲审 3.7-F2）
            }
        }
    }

    /// 空组不显示（03 §6）。
    @ViewBuilder
    private func section(title: String, todos: [Todo], isOverdue: Bool = false) -> some View {
        if !todos.isEmpty {
            Section {
                ForEach(todos) { todo in
                    TodoRow(model: model, todo: todo, isOverdue: isOverdue)
                        .id(todo.uuid.uuidString)
                }
            } header: {
                Text(title)
                    .foregroundStyle(isOverdue ? Color.red : Color.secondary)
            }
        }
    }
}

/// 单行待办：圆圈（完成/勾回）+ 标题 + 时间；编辑态为原位单行编辑框。
private struct TodoRow: View {
    @Bindable var model: PanelModel
    let todo: Todo
    /// 所在组是否逾期组（时间红字；行内再按各自 due 判定兜底组迁移前的窗口）。
    var isOverdue = false

    @FocusState private var isFocused: Bool

    /// 视觉上的完成态：勾选后立即生效（数据 1 秒后才落库）。
    private var isVisuallyCompleted: Bool {
        todo.completedAt != nil || model.pendingCompletionIDs.contains(todo.id)
    }

    private var isEditing: Bool {
        model.editingTodoID == todo.id
    }

    /// 行尾时间文案（03 §6）；注入 now/时区。读取 tick 建立跨天重算依赖（盲审 F3）。
    private var timeText: String? {
        _ = model.timeContextTick
        return TodoGrouping.timeText(for: todo, now: Date(), timeZone: model.timeZone)
    }

    /// 该行是否按逾期红字显示：逾期组的行，或未完成但 due 已过。
    private var showsOverdueTime: Bool {
        _ = model.timeContextTick
        return isOverdue || (!isVisuallyCompleted && TodoGrouping.isOverdue(todo, now: Date(), timeZone: model.timeZone))
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
                if let timeText {
                    Text(timeText)
                        .font(.caption)
                        .foregroundStyle(showsOverdueTime ? Color.red : Color.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .background(
            model.recentlyCreatedItemID == todo.uuid.uuidString || model.locateTodoID == todo.uuid.uuidString
                ? Color.accentColor.opacity(0.15)
                : .clear
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
            Button(String(localized: .todoMenuSetTime)) {
                _ = model.endEditingIfNeeded()
                model.editingTimeTarget = todo
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
