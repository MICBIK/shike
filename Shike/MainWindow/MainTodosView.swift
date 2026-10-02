// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Observation
import ShikeData
import SwiftUI
import os

/// 主窗口-待办视图的模型（S3.5-04，03 §16.4）：观察流数据 + 搜索过滤 + 五分组 + 动作转发。
/// 数据与动作都走闭包接缝（@ObservationIgnored）：集成层（AppEnvironment 组装）注入
/// `todoRepository.observeActive` 与面板同语义的动作（03 §16.7：同一观察流，两侧即时互见）；
/// 默认空实现让 L2/预览可以不经接线直接组装。
@MainActor
@Observable
final class MainTodosModel {
    /// 观察流推送的待办全量（未删除，含已完成——与 TodoRepository.observeActive 同口径）。
    private(set) var todos: [Todo] = []

    /// 首帧是否已送达（W2，含空数组帧；流失败/非取消结束时同样置 true——失败由
    /// 反馈通道承接，不停在假空态）。视图空态分支以 `isLoaded && isEmpty` 分流，
    /// 首帧前渲染空白纸感底，避免闪现"没有待办"。
    private(set) var isLoaded = false
    /// 观察流是否处于失败态（打磨 R2）：失败翻 true、帧到达翻 false——空态视图
    /// 据此显示「读取失败 + 重试」而不是误导性的"没有待办"。
    private(set) var isLoadFailed = false

    /// 搜索关键词（03 §16.4）：按标题不区分大小写即时过滤；纯空白视为不过滤。
    var searchText: String = ""

    /// "已完成"组展开状态：与面板一致默认折叠（PanelModel.isCompletedSectionExpanded 同语义）。
    var isCompletedExpanded = false

    /// 分组时钟：跨天/唤醒时递增，驱动视图重算"逾期/今天"（PanelModel.timeContextTick 同模式；
    /// 不标 @ObservationIgnored——视图读取 groups 时要建立对它的依赖）。
    private(set) var timeContextTick = 0

    // - MARK: 注入接缝（@ObservationIgnored：闭包与配置不参与观察）

    /// 行显示与分组用的"现在"（NFR22：时间口径全部注入；L2 注入固定值让分组判定确定）。
    @ObservationIgnored var now: () -> Date = { Date() }
    /// 行显示与分组用的时区（与 PanelModel.timeZone 同模式；集成层随数据库 Options.timeZone 注入）。
    @ObservationIgnored var timeZone: TimeZone = .current

    /// 待办观察流工厂：集成接 `todoRepository.observeActive()`；默认立即结束的空流（未接线零副作用）。
    @ObservationIgnored var observeTodos: () -> AsyncThrowingStream<[Todo], any Error> = {
        AsyncThrowingStream<[Todo], any Error> { $0.finish() }
    }

    /// 勾选完成/勾回（03 §16.4）：Bool 为行快照推导的目标完成状态（true=完成、false=勾回）。
    /// 集成接 `PanelModel.toggleTodoCompletion(id)`（面板三态：待移入 1 秒可勾回）——
    /// 目标态由面板按自身快照与待移入窗仲裁；完成时清 snoozedUntil/取消提醒（ADR-017）
    /// 在 PanelModel 内实现一次。
    @ObservationIgnored var toggleComplete: (Todo.ID, Bool) -> Void = { _, _ in }
    /// 删除（软删除）：集成接 `PanelModel.deleteTodo(id)`（入撤销栈同语义）。
    @ObservationIgnored var delete: (Todo.ID) -> Void = { _ in }
    /// 编辑：主窗口暂无原位编辑（03 §16.4 只要求右键菜单与面板一致）。集成时留空实现，
    /// 或接面板定位 `PanelModel.locateTodo(uuid:)`（呼出面板并高亮该条后再编辑）。
    @ObservationIgnored var edit: (Todo.ID) -> Void = { _ in }
    /// "设置时间…"：集成接面板 `PanelModel.editingTimeTarget`（把该条交给面板的时间弹层）
    /// 或后续主窗口自己的时间编辑器；默认空实现。
    @ObservationIgnored var setTime: (Todo.ID) -> Void = { _ in }
    /// 观察流失败上报接缝（W3）：非取消结束与异常结束调用；集成接主窗口统一反馈。
    @ObservationIgnored var readFailureHandler: () -> Void = {}
    /// 面板引用（打磨二轮 B3 由卡B 移交卡A 实施）：主窗口行渲染"待移入窗"内的勾选
    /// 即时反馈——面板行按 pendingCompletionIDs 立即划线变灰，主窗口此前只等观察流
    /// 推送（点击后约 1 秒无任何视觉变化）。引用由集成层注入（MainWindowController）；
    /// nil 时行为同旧（仅 completedAt），L2 直组不受影响。@ObservationIgnored：引用
    /// 装配期一次赋值；视图追踪的是 panel.pendingCompletionIDs 的读取（PanelModel
    /// 自身可观察），不需要对引用本身建观察。
    @ObservationIgnored var panel: PanelModel?
    /// 稍后提醒（可选）：集成接 `PanelModel.snoozeTodo(uuid:until:)` 同语义（按 uuid 写
    /// snoozedUntil，已完成/已删除由仓储忽略）。面板待办行没有该菜单项，主窗口同样暂不
    /// 展示入口；接缝留作可选项，默认 nil 不产生任何调用。
    @ObservationIgnored var snooze: ((Todo.ID, Date) -> Void)?

    /// 观察流消费任务（nonisolated(unsafe) 供 deinit 取消；deinit 与 start/stop 不会并发发生）。
    @ObservationIgnored nonisolated(unsafe) private var todoTask: Task<Void, Never>?
    /// 跨天/唤醒观察者（S2-06 同面板：分组时钟递增驱动重算）；nonisolated(unsafe) 供 stop 移除。
    @ObservationIgnored nonisolated(unsafe) private var timeContextObservers: [any NSObjectProtocol] = []

    // - MARK: 生命周期

    /// 订阅待办观察流并注册跨天/唤醒观察者（视图 onAppear 或集成层装配时调用；
    /// 重复调用先取消旧订阅，幂等）。
    func start() {
        todoTask?.cancel()
        todoTask = Task { [weak self] in
            await self?.consumeObservation()
        }
        startTimeContextObservers()
    }

    /// 停止消费与观察者（applicationWillTerminate 等场景由集成层调用；切换左栏入口
    /// 不断流，与面板常驻订阅同口径）。
    func stop() {
        todoTask?.cancel()
        todoTask = nil
        stopTimeContextObservers()
    }

    deinit {
        // Task.cancel 是 nonisolated 的，可在 deinit 调用；释放时停止观察。
        todoTask?.cancel()
    }

    /// 订阅跨天与唤醒：分组时钟递增让视图重算"逾期/今天"（PanelModel 同款，
    /// 模型内自注册——面板的 timeContextChanged 钩子已被菜单栏计数占用，不能复用）。
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

    /// 消费观察流：每帧刷新 todos，分组由视图按需重算。
    /// 流以非取消方式结束与面板同语义视为故障信号（data-layer.md「观察」）；
    /// internal 供 L2 直接驱动真实流（确定性断言收尾路径，MainNotesModel.runNotes 同形）。
    func runTodos(_ stream: AsyncThrowingStream<[Todo], any Error>) async {
        do {
            for try await items in stream {
                todos = items
                isLoaded = true
                isLoadFailed = false
            }
            guard !Task.isCancelled else { return }
            isLoaded = true
            isLoadFailed = true
            readFailureHandler()
            Log.app.error("主窗口待办观察流非取消结束（应为故障信号）")
        } catch {
            guard !(error is CancellationError) else { return }
            isLoaded = true
            isLoadFailed = true
            readFailureHandler()
            Log.app.error("主窗口待办观察流失败：\(String(describing: error), privacy: .public)")
        }
    }

    private func consumeObservation() async {
        await runTodos(observeTodos())
    }

    // - MARK: 派生与动作

    /// 跨天/唤醒：递增分组时钟让视图重算"逾期/今天"。由 startTimeContextObservers
    /// 自注册的观察者调用（PanelModel.handleTimeContextChanged 同款）；不占用面板的
    /// timeContextChanged 钩子——它已被菜单栏计数接线（AppDelegate）。
    func handleTimeContextChanged() {
        timeContextTick += 1
    }

    /// 搜索过滤后的五分组（S3.5-04，03 §16.4）：直接复用面板分组器 TodoGrouping——
    /// 组序（逾期/今天/以后/无日期/已完成）与组内排序和面板完全一致；关键词按标题
    /// 不区分大小写过滤（含已完成，与面板搜索同口径）。读取 timeContextTick 建立
    /// 跨天重算依赖（盲审 F3 同面板）。
    var groups: TodoGroups {
        _ = timeContextTick
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = query.isEmpty
            ? todos
            : todos.filter { $0.title.range(of: query, options: .caseInsensitive) != nil }
        return TodoGrouping.group(todos: filtered, now: now(), timeZone: timeZone)
    }

    /// 圆圈勾选/勾回（行视图调用）：按当前完成态推导目标状态转发给 toggleComplete。
    func toggleCompletion(_ todo: Todo) {
        toggleComplete(todo.id, todo.completedAt == nil)
    }
}

/// 主窗口-待办视图（S3.5-04，03 §16.4）：顶部搜索框 + 五分组列表
/// （逾期（红）/ 今天 / 以后 / 无日期 / 已完成（默认折叠））。
/// 视觉与交互跟随面板 TodoListView（纸感白卡行、逾期红、完成灰、右键菜单一致）。
struct MainTodosView: View {
    /// 模型由集成层注入并接线动作闭包；未接线时视图仍可安全显示（动作空实现）。
    @Bindable var model: MainTodosModel

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            content
        }
        // 纸感底（三分区统一，见 paperSurface）。frame 与 MainNotesView 同款：
        // 空态分支（ContentUnavailableView）不贪婪，无此 frame 时 VStack 只取理想
        // 高度被居中、四周露出窗口白底（打磨二轮·卡A 项4）。
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
        .paperSurface()
        // 订阅由视图挂载时启动（集成层装配时也可 start()，重复调用幂等）；
        // 不在 onDisappear 停——切换左栏入口不断流，与面板常驻订阅同口径。
        .onAppear { model.start() }
    }

    /// 搜索框（与便签分区同款纸感容器视觉，S3.5 集成统一；放大镜 + plain 13pt
    /// + 非空可一键清空）。
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(0.65))
            TextField(
                String(localized: .mainTodosSearch),
                text: $model.searchText
            )
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            // ⌘F 聚焦搜索（打磨二轮 B4，卡B 移交卡A 实施；面板 ⌘F 同语义）。
            .keyboardShortcut("f", modifiers: .command)
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

    /// 空态分流（与便签分区同口径）：真没有待办显示"没有待办"；快照非空但搜索
    /// 过滤为空显示"没有找到 X"+ 一键清除；首帧未到渲染空白纸感底（W2）。
    @ViewBuilder
    private var content: some View {
        let groups = model.groups
        if !model.isLoaded {
            // 首帧未到（W2）：此时的"空"只是未加载——不显示空态也不放转圈。
            Color.clear
        } else if model.todos.isEmpty {
            if model.isLoadFailed {
                // 读取失败（打磨 R2）：不显示"没有待办"（谎话），给重试出口。
                readFailedView
            } else {
                // 空态与便签分区同构（打磨二轮·卡A 项4）：Label=分区名 + 引导句描述。
                // frame 让空态分支贪婪填充：搜索框钉在顶部，CUV 在剩余空间居中。
                ContentUnavailableView {
                    Label(String(localized: .mainSectionTodos), systemImage: "checklist")
                } description: {
                    Text(String(localized: .mainTodosEmptyGuide))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else if groups.hasNoActive && groups.completed.isEmpty {
            searchNoResults
        } else {
            list(groups: groups)
        }
    }

    /// 读取失败空态（打磨 R2）：文案复用 main.read.failed，重试重订阅（与便签分区同款）。
    private var readFailedView: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(String(localized: .mainReadFailed))
                .font(.callout)
                .foregroundStyle(.secondary)
            Button(String(localized: .bannerRetry)) {
                model.start()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 搜索无命中的轻提示（文案与「清空」按钮复用面板搜索既有键，便签分区同款）。
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
        // 顶部对齐贪婪填充（打磨二轮·卡A 项4）：分支不贪婪时外层 frame 会把整组居中。
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 48)
    }

    /// 手工排版（打磨二轮·卡A 项1）：与便签分区同一 LazyVStack 节奏（组头 16/14/6、
    /// 行水平 12/垂直 3）——List(.sidebar) 的系统行内边距无法用 listRowInsets 完全
    /// 中和（实测待办卡片比便签深约 16pt），改手工排版后三视图共享同一几何常量；
    /// 待办行无 List 特性依赖（无选择/滑动/行锚定弹层），行为零变化。
    private func list(groups: TodoGroups) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                section(title: String(localized: .listGroupOverdue), todos: groups.overdue, isOverdue: true)
                section(title: String(localized: .listGroupToday), todos: groups.today)
                section(title: String(localized: .listGroupLater), todos: groups.later)
                section(title: String(localized: .listGroupNoDate), todos: groups.noDate)
                completedSection(groups.completed)
            }
            .padding(.bottom, 16)
        }
    }

    /// 普通组：空组不显示（03 §6 同面板）。
    @ViewBuilder
    private func section(title: String, todos: [Todo], isOverdue: Bool = false) -> some View {
        if !todos.isEmpty {
            sectionHeader(title: title, count: todos.count, isOverdue: isOverdue)
            ForEach(todos) { todo in
                MainTodoRow(model: model, todo: todo, isOverdue: isOverdue)
            }
        }
    }

    /// "已完成"组：默认折叠、标题可点击展开/收起、空组不显示（与面板 TodoListView 同款）。
    @ViewBuilder
    private func completedSection(_ todos: [Todo]) -> some View {
        if !todos.isEmpty {
            Button {
                model.isCompletedExpanded.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: model.isCompletedExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(String(localized: .listGroupCompleted(todos.count)))
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                }
                .foregroundStyle(Color.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .padding(.trailing, 16)
            if model.isCompletedExpanded {
                ForEach(todos) { todo in
                    MainTodoRow(model: model, todo: todo)
                }
            }
        }
    }

    /// 组头（与便签分区 section 同款手工边距：领先 16 / 上 14 / 下 6）。
    private func sectionHeader(title: String, count: Int, isOverdue: Bool = false) -> some View {
        GroupHeader(title: title, count: count, isOverdue: isOverdue)
            .padding(.leading, 16)
            .padding(.top, 14)
            .padding(.bottom, 6)
            .padding(.trailing, 16)
    }
}

/// 主窗口待办行：纸感卡片（左色边 = 青绿/逾期红/完成灰）+ 勾选框 + 标题 + 时间徽章。
/// 视觉与面板 TodoListView.TodoRow 一致（白卡、删除线、逾期红字）；主窗口无原位编辑，
/// 编辑走右键菜单注入的接缝。
private struct MainTodoRow: View {
    @Bindable var model: MainTodosModel
    let todo: Todo
    /// 所在组是否逾期组（时间红字与左色边；行内再按各自 due 判定兜底组迁移前的窗口）。
    var isOverdue = false

    /// hover 抬描边与投影。
    @State private var isHovered = false

    /// 视觉上的完成态（打磨二轮 B3）：勾选后立即生效——含面板"待移入窗"内的
    /// 勾选（pendingCompletionIDs，与面板 TodoListView 同款判定），不再等约 1 秒
    /// 的观察流推送；勾回同理即时恢复。
    private var isVisuallyCompleted: Bool {
        todo.completedAt != nil || (model.panel?.pendingCompletionIDs.contains(todo.id) ?? false)
    }

    /// 行尾时间文案（03 §6，与面板同一 TodoGrouping.timeText）；读取 tick 建立跨天重算依赖。
    private var timeText: String? {
        _ = model.timeContextTick
        return TodoGrouping.timeText(for: todo, now: model.now(), timeZone: model.timeZone)
    }

    /// 该行是否按逾期红字显示：逾期组的行，或未完成但 due 已过。
    private var showsOverdueTime: Bool {
        _ = model.timeContextTick
        return isOverdue || (!isVisuallyCompleted && TodoGrouping.isOverdue(todo, now: model.now(), timeZone: model.timeZone))
    }

    /// 左色边颜色：完成灰 / 逾期红 / 其余青绿（与面板同）。
    private var edgeColor: Color {
        if isVisuallyCompleted { return Color.secondary.opacity(0.35) }
        if showsOverdueTime { return Color.red.opacity(0.85) }
        return Color.accentColor
    }

    /// 行尾时间颜色：逾期红；完成态回灰；其余青绿加重（与面板同）。
    private var timeColor: Color {
        if isVisuallyCompleted { return Color("CardMeta") }
        if showsOverdueTime { return Color.red }
        return Color.accentColor.opacity(0.9)
    }

    var body: some View {
        HStack(spacing: 9) {
            Button {
                model.toggleCompletion(todo)
            } label: {
                Image(systemName: isVisuallyCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isVisuallyCompleted ? Color.secondary : Color.accentColor)
            }
            .buttonStyle(.plain)

            Text(todo.title)
                .font(.system(size: 13, weight: .medium))
                .strikethrough(isVisuallyCompleted)
                .foregroundStyle(isVisuallyCompleted ? Color.secondary : Color.primary)

            if let timeText {
                Text(timeText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(timeColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, 13)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background(
            PaperCard(
                isHovered: isHovered,
                edge: .leftEdge(edgeColor)
            )
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        .animation(Motion.gentle(0.2), value: isVisuallyCompleted)
        .animation(Motion.gentle(0.1), value: isHovered)
        .onHover { isHovered = $0 }
        .contentShape(Rectangle())
        .contextMenu {
            // 与面板 TodoListView 的 contextMenu 一致（03 §16.4"右键菜单与面板待办行一致"）。
            Button(String(localized: .listMenuEdit)) {
                // 集成：留空实现或接 PanelModel.locateTodo(uuid:)（呼出面板定位该条后再编辑）。
                model.edit(todo.id)
            }
            Button(String(localized: .todoMenuSetTime)) {
                // 集成：接 PanelModel.editingTimeTarget（面板时间弹层）或主窗口时间编辑器。
                model.setTime(todo.id)
            }
            Divider()
            Button(String(localized: .listMenuDelete), role: .destructive) {
                // 集成：接 PanelModel.deleteTodo(id)（软删除入撤销栈）。
                model.delete(todo.id)
            }
        }
    }
}
