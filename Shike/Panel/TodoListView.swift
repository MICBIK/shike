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
    // "已完成"组展开状态在 PanelModel（S2-09 定位已完成待办时需先展开）

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
                        if model.isCompletedSectionExpanded {
                            ForEach(groups.completed) { todo in
                                TodoRow(model: model, todo: todo)
                                    .id(todo.uuid.uuidString)
                            }
                        }
                    } header: {
                        Button {
                            model.isCompletedSectionExpanded.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: model.isCompletedSectionExpanded ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 9, weight: .semibold))
                                Text(String(localized: .listGroupCompleted(groups.completed.count)))
                                    .font(.system(size: 11, weight: .semibold))
                                    .tracking(0.6)
                            }
                            .foregroundStyle(Color.secondary)
                        }
                        .buttonStyle(.plain)
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
                GroupHeader(title: title, count: todos.count, isOverdue: isOverdue)
            }
        }
    }
}

/// 单行待办：纸感卡片（左色边 = 青绿/逾期红/完成灰）+ 圆圈（完成/勾回）+ 标题 + 时间；
/// 编辑态为卡片上的原位单行编辑框。
private struct TodoRow: View {
    @Bindable var model: PanelModel
    let todo: Todo
    /// 所在组是否逾期组（时间红字与左色边；行内再按各自 due 判定兜底组迁移前的窗口）。
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

    /// hover 抬描边与投影。
    @State private var isHovered = false

    /// 该行是否按逾期红字显示：逾期组的行，或未完成但 due 已过。
    private var showsOverdueTime: Bool {
        _ = model.timeContextTick
        return isOverdue || (!isVisuallyCompleted && TodoGrouping.isOverdue(todo, now: Date(), timeZone: model.timeZone))
    }

    /// 左色边颜色：完成灰 / 逾期红 / 其余青绿（纸感批次）。
    private var edgeColor: Color {
        if isVisuallyCompleted { return Color.secondary.opacity(0.35) }
        if showsOverdueTime { return Color.red.opacity(0.85) }
        return Color.accentColor
    }

    private var isHighlighted: Bool {
        model.recentlyCreatedItemID == todo.uuid.uuidString
            || model.locateTodoID == todo.uuid.uuidString
    }

    var body: some View {
        HStack(spacing: 9) {
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
                    .font(.system(size: 13, weight: .medium))
                    .strikethrough(isVisuallyCompleted)
                    .foregroundStyle(isVisuallyCompleted ? Color.secondary : Color.primary)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        startEditing()
                    }
                if let timeText {
                    Text(timeText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(timeColor)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            PaperCard(
                isHighlighted: isHighlighted,
                isHovered: isHovered && !isEditing,
                isActive: isEditing,
                edge: .leftEdge(edgeColor)
            )
        )
        .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .animation(Motion.gentle(0.2), value: isVisuallyCompleted)
        .animation(Motion.gentle(0.2), value: isHighlighted)
        .animation(Motion.gentle(0.1), value: isHovered)
        .onHover { isHovered = $0 }
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

    /// 行尾时间颜色：逾期红；带时间未逾期为青绿加重；完成态回灰。
    private var timeColor: Color {
        if isVisuallyCompleted { return Color("CardMeta") }
        if showsOverdueTime { return Color.red }
        return Color.accentColor.opacity(0.9)
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
