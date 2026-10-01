// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ShikeData
import SwiftUI

/// 单张卡片的界面模型：便签内容 + 卡片选项（CardManager 推送，视图只渲染）。
@MainActor
@Observable
final class CardModel {
    var content: String
    var options: StickyCardOptions
    /// 指针悬停（ADR-026：只增强工具栏对比度，所有功能不再依赖悬停才可点）。
    var isHovered = false
    /// 系统深色模式（打磨 R4：CardManager 经 KVO 推送，切换深浅色卡片即时换色）。
    var isDark: Bool
    /// 卡片上编辑（S3-06，03 §10.2）：工具栏铅笔/双击进入，点击外部/Esc/✓ 结束，0.5 秒防抖自动保存。
    var isEditing = false
    var editingText = ""
    /// 拖动或调整大小进行中（打磨 R11）：指针会离开窗口，工具栏保持可见。
    var isDragging = false

    init(content: String, options: StickyCardOptions, isDark: Bool) {
        self.content = content
        self.options = options
        self.isDark = isDark
    }
}

/// 卡片窗口（ADR-025 结论 4）：borderless + 非激活面板——点击不把拾刻变成前台应用；
/// 编辑态（S3-06）把 allowsKey 置 true 后才能成为 key 窗口接收键盘。
@MainActor
final class StickyCardPanel: NSPanel {
    let noteID: Note.ID
    var allowsKey = false

    override var canBecomeKey: Bool { allowsKey }

    init(noteID: Note.ID, contentRect: NSRect) {
        self.noteID = noteID
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false // 移动只经顶部工具栏的 performDrag（03 §10.2）
        hidesOnDeactivate = false
        level = CardTheme.windowLevel(for: .floating)
    }

    /// 应用选项到窗口属性（颜色/字号在 SwiftUI 层随 options 渲染）。
    /// ADR-029 层级语义：切到"普通"时立即让位——level setter 会把窗口放到新层
    /// 最前（正好压住正在用的窗口，用户看就是"普通=置顶"），orderBack 沉到普通
    /// 窗口链底部（03 §10.3"会被遮挡"）；之后点卡片可见部分浮到前面（规格
    /// "点击后浮到前面"，CardHostingView.mouseDown）。floating/desktop 由
    /// level setter 自动浮出/沉底，无需干预。普通层级被其他窗口激活时被正常
    /// 压盖（LevelProbe 原型 v4 实证：TextEdit 激活后压住全部配置的 panel）。
    func apply(options: StickyCardOptions) {
        let newLevel = CardTheme.windowLevel(for: options.level)
        let levelChanged = newLevel != level
        level = newLevel
        collectionBehavior = CardTheme.collectionBehavior(
            allSpaces: options.allSpaces,
            showOverFullScreen: options.showOverFullScreen,
            level: options.level
        )
        if levelChanged, options.level == .normal, isVisible {
            orderBack(nil)
        }
    }
}

/// 卡片内容（03 §10.1，ADR-026 重做）：常驻顶部工具栏 + 正文区。
/// 工具栏永远占位（正文永远从它下方开始，任何状态都不被遮挡）、永远可点
/// （不依赖悬停出现）；悬停只把按钮从 55% 提亮到全亮。
struct CardContentView: View {
    @Bindable var model: CardModel
    var onClose: () -> Void
    /// 拖动/调整大小开始（控制器置 busy：进行中不自动隐藏，03 §10.4）。
    var onDragStarted: () -> Void = {}
    var onDragEnded: () -> Void
    /// 调整大小结束（与移动分开收尾：要按最小尺寸钳制）。
    var onResizeEnded: () -> Void = {}
    /// 卡片菜单改动选项（颜色/层级/字号/自动隐藏/空间，S3-03/S3-04）。
    var onOptionsChange: (StickyCardOptions) -> Void = { _ in }
    /// 进入编辑（工具栏铅笔或双击内容区，S3-06）。
    var onEditRequest: () -> Void = {}
    /// 编辑文字变化（控制器做 0.5 秒防抖自动保存，03 §10.2）。
    var onEditingTextChange: (String) -> Void = { _ in }
    /// 结束编辑（Esc/点击外部/✓），保存交给控制器。
    var onEditEnd: () -> Void = {}
    /// 在面板中显示（S3-08，03 §10.5）。
    var onShowInPanel: () -> Void = {}

    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            topBar
            contentArea
        }
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: CardTheme.background(
                    for: model.options.color,
                    dark: model.isDark
                )))
        )
        // 先裁圆角（滚动到末尾的文字不盖出下缘圆角），再在裁剪后的整体上加投影
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        .overlay(alignment: .bottomTrailing) {
            // 右下角调整大小把手（03 §10.2）；编辑态不显示，避免吃文本框角落的点击
            if !model.isEditing {
                resizeGrip
            }
        }
        .animation(Motion.standard(0.15), value: model.isEditing)
        .onHover { model.isHovered = $0 }
    }

    /// 正文区（03 §10.1）：顶部固定只留 2pt 呼吸，编辑/展示两种状态一致，不跳动
    /// （R10 的固定留白由布局本身保证，不再靠条件 padding）。
    @ViewBuilder
    private var contentArea: some View {
        if model.isEditing {
            TextEditor(text: $model.editingText)
                .scrollContentBackground(.hidden)
                .font(.system(size: CardTheme.contentFontSize(for: model.options.fontSize)))
                .padding(.top, 2)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
                .focused($editorFocused)
                .onAppear {
                    // 窗口已在控制器置 allowsKey 并 makeKey，下一拍聚焦文本视图
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(50))
                        editorFocused = true
                    }
                }
                .onChange(of: model.editingText) { _, newText in
                    onEditingTextChange(newText)
                }
                .onExitCommand {
                    // IME 组合态守卫（打磨 R5，与主窗口便签编辑器同款）：组合中
                    // Esc 归输入法（取消候选），不收整卡编辑。SwiftUI 不暴露组合
                    // 态，经键窗第一响应者 NSTextView 探测；非组合态行为不变。
                    if (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true { return }
                    // Esc：结束编辑（03 §10.2）；保存由控制器收尾
                    onEditEnd()
                }
        } else {
            ScrollView(.vertical) {
                Text(model.content)
                    .font(.system(size: CardTheme.contentFontSize(for: model.options.fontSize)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                    .textSelection(.enabled)
            }
            .scrollContentBackground(.hidden)
            .onTapGesture(count: 2) {
                onEditRequest()
            }
            // 右键正文 = ⋯ 菜单同源（ADR-026）：工具栏之外的第二条操作通路。
            // 只挂展示态——编辑态要保留 TextEditor 原生的剪切/拷贝/粘贴菜单。
            .contextMenu {
                menuContent
            }
        }
    }

    /// 常驻顶部工具栏：左拖动区（含抓手提示）；右编辑/颜色/层级/⋯/✕。
    private var topBar: some View {
        HStack(spacing: 4) {
            CardDragBar(
                onDragStarted: { model.isDragging = true }, // 拖动中工具栏常驻提亮（指针会离开卡片）
                onDragEnded: {
                    model.isDragging = false
                    onDragEnded()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .leading) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 1)
                    .allowsHitTesting(false)
            }
            HStack(spacing: 6) {
                editButton
                colorMenu
                levelMenu
                optionsMenu
                closeButton
            }
            .opacity(model.isHovered || model.isDragging ? 1 : 0.55)
            .animation(Motion.standard(0.15), value: model.isHovered || model.isDragging)
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(height: 24)
        .background(
            // 上缘随卡片圆角，避免方角盖出纸面
            UnevenRoundedRectangle(
                topLeadingRadius: 10,
                topTrailingRadius: 10,
                style: .continuous
            )
            .fill(Color.primary.opacity(0.035))
        )
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    /// 编辑（铅笔）/ 结束编辑（✓）。
    private var editButton: some View {
        Button {
            if model.isEditing {
                onEditEnd()
            } else {
                onEditRequest()
            }
        } label: {
            Image(systemName: model.isEditing ? "checkmark" : "pencil")
        }
        .buttonStyle(.plain)
        .help(String(localized: .listMenuEdit))
        .accessibilityLabel(String(localized: .listMenuEdit))
    }

    /// 颜色菜单：按钮直接显示当前颜色的色板。
    private var colorMenu: some View {
        Menu {
            Picker(String(localized: .cardMenuColor), selection: colorBinding) {
                Text(String(localized: .cardColorYellow)).tag(CardColor.yellow)
                Text(String(localized: .cardColorGreen)).tag(CardColor.green)
                Text(String(localized: .cardColorBlue)).tag(CardColor.blue)
                Text(String(localized: .cardColorPink)).tag(CardColor.pink)
                Text(String(localized: .cardColorPurple)).tag(CardColor.purple)
                Text(String(localized: .cardColorGray)).tag(CardColor.gray)
            }
            .pickerStyle(.inline)
        } label: {
            Circle()
                .fill(Color(nsColor: CardTheme.background(
                    for: model.options.color,
                    dark: model.isDark
                )))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.3), lineWidth: 0.5))
                .frame(width: 9, height: 9)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: .cardMenuColor))
        .accessibilityLabel(String(localized: .cardMenuColor))
    }

    /// 层级菜单（03 §10.3，ADR-026）：显式选择替代循环按钮；图标随当前层级变化。
    private var levelMenu: some View {
        Menu {
            Picker(String(localized: .cardBarLevel), selection: levelBinding) {
                Text(String(localized: .cardLevelFloating)).tag(CardLevel.floating)
                Text(String(localized: .cardLevelNormal)).tag(CardLevel.normal)
                Text(String(localized: .cardLevelDesktop)).tag(CardLevel.desktop)
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: levelIcon)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(String(localized: .cardBarLevel))
        .accessibilityLabel(String(localized: .cardBarLevel))
    }

    private var levelIcon: String {
        switch model.options.level {
        case .floating: "square.stack.3d.up"
        case .normal: "macwindow"
        case .desktop: "pin"
        }
    }

    private var closeButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
        }
        .buttonStyle(.plain)
        .help(String(localized: .cardMenuUnpin))
        .accessibilityLabel(String(localized: .cardMenuUnpin))
    }

    /// ⋯ 菜单与正文右键菜单共用内容（03 §10.5，ADR-026 后：编辑/颜色/层级在工具栏，
    /// 次常用留在这里）。
    @ViewBuilder
    private var menuContent: some View {
        Picker(String(localized: .settingsCardFontSize), selection: fontSizeBinding) {
                Text(String(localized: .cardFontSizeSmall)).tag(CardFontSize.small)
                Text(String(localized: .cardFontSizeMedium)).tag(CardFontSize.medium)
                Text(String(localized: .cardFontSizeLarge)).tag(CardFontSize.large)
            }
            .pickerStyle(.inline)
            Picker(String(localized: .settingsCardAllSpaces), selection: allSpacesBinding) {
                Text(String(localized: .cardSpaceAllSpaces)).tag(true)
                Text(String(localized: .cardSpaceCurrentOnly)).tag(false)
            }
            .pickerStyle(.inline)
            Toggle(
                String(localized: .settingsCardShowOverFullScreen),
                isOn: showOverFullScreenBinding
            )
            Menu(String(localized: .cardMenuAutoHide)) {
                Toggle(String(localized: .cardMenuAutoHide), isOn: autoHideBinding)
                if model.options.autoHide {
                    Picker(String(localized: .cardMenuAutoHideDelay), selection: hideDelayBinding) {
                        ForEach([1.0, 3.0, 5.0, 10.0], id: \.self) { seconds in
                            Text(String(localized: .settingsCardHideDelaySeconds(Int(seconds))))
                                .tag(seconds)
                        }
                    }
                    .pickerStyle(.inline)
                    Picker(String(localized: .settingsCardHiddenOpacity), selection: hiddenOpacityBinding) {
                        ForEach([0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6], id: \.self) { opacity in
                            Text(String(localized: .settingsCardHiddenOpacityPercent(Int((opacity * 100).rounded()))))
                                .tag(opacity)
                        }
                    }
                    .pickerStyle(.inline)
                }
            }
        Divider()
        Button(String(localized: .cardMenuShowInPanel), action: onShowInPanel)
        Button(String(localized: .cardMenuUnpin), action: onClose)
            .keyboardShortcut("w", modifiers: .command)
    }

    private var optionsMenu: some View {
        Menu {
            menuContent
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .fixedSize()
        .help(String(localized: .cardMenuOptions))
        .accessibilityLabel(String(localized: .cardMenuOptions))
    }

    /// 右下角调整大小把手（03 §10.2，ADR-026）：borderless 面板没有系统边缘，
    /// 自行跟踪拖拽换算新 frame；松手后控制器按最小尺寸钳制并持久化。
    /// busy 置位与拖动同路（onDragStarted → 控制器），调整大小中不自动隐藏。
    private var resizeGrip: some View {
        CardResizeGrip(
            onResizeStarted: {
                model.isDragging = true
                onDragStarted()
            },
            onResizeEnded: {
                model.isDragging = false
                onResizeEnded()
            }
        )
        .frame(width: 14, height: 14)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arrow.down.forward.and.arrow.up.backward")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.tertiary)
                .padding(2)
                .allowsHitTesting(false)
        }
    }

    // 选项绑定：统一走"改副本 → onOptionsChange"（持久化经仓储回环）
    private var colorBinding: Binding<CardColor> {
        optionBinding(\.color) { $0.color = $1 }
    }
    private var fontSizeBinding: Binding<CardFontSize> {
        optionBinding(\.fontSize) { $0.fontSize = $1 }
    }
    private var levelBinding: Binding<CardLevel> {
        optionBinding(\.level) { $0.level = $1 }
    }
    private var allSpacesBinding: Binding<Bool> {
        optionBinding(\.allSpaces) { $0.allSpaces = $1 }
    }
    private var showOverFullScreenBinding: Binding<Bool> {
        optionBinding(\.showOverFullScreen) { $0.showOverFullScreen = $1 }
    }
    private var autoHideBinding: Binding<Bool> {
        optionBinding(\.autoHide) { $0.autoHide = $1 }
    }
    private var hideDelayBinding: Binding<Double> {
        optionBinding(\.hideDelay) { $0.hideDelay = $1 }
    }
    private var hiddenOpacityBinding: Binding<Double> {
        optionBinding(\.hiddenOpacity) { $0.hiddenOpacity = $1 }
    }

    private func optionBinding<Value>(
        _ keyPath: KeyPath<StickyCardOptions, Value>,
        _ set: @escaping (inout StickyCardOptions, Value) -> Void
    ) -> Binding<Value> {
        Binding(
            get: { model.options[keyPath: keyPath] },
            set: { newValue in
                var options = model.options
                set(&options, newValue)
                onOptionsChange(options)
            }
        )
    }
}

/// 拖动区：mouseDown 交给窗口 performDrag（阻塞到松手），结束后回调持久化新位置。
private struct CardDragBar: NSViewRepresentable {
    var onDragStarted: () -> Void
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragBarView {
        let view = DragBarView()
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: DragBarView, context: Context) {
        view.onDragStarted = onDragStarted
        view.onDragEnded = onDragEnded
    }

    final class DragBarView: NSView {
        var onDragStarted: () -> Void = {}
        var onDragEnded: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            onDragStarted()
            window.performDrag(with: event)
            // performDrag 返回即松手：交给 CardController 换算并持久化（03 §10.2 移动）。
            onDragEnded()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}

/// 调整大小把手：自行跟踪拖拽（borderless 面板没有系统边缘），右下角向外拉改变
/// 宽高（屏幕坐标 y 向上，高度取 -dy）；实时钳制最小尺寸，松手由控制器持久化。
private struct CardResizeGrip: NSViewRepresentable {
    var onResizeStarted: () -> Void
    var onResizeEnded: () -> Void

    func makeNSView(context: Context) -> ResizeGripView {
        let view = ResizeGripView()
        view.onResizeStarted = onResizeStarted
        view.onResizeEnded = onResizeEnded
        return view
    }

    func updateNSView(_ view: ResizeGripView, context: Context) {
        view.onResizeStarted = onResizeStarted
        view.onResizeEnded = onResizeEnded
    }

    final class ResizeGripView: NSView {
        var onResizeStarted: () -> Void = {}
        var onResizeEnded: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            onResizeStarted()
            defer { onResizeEnded() }
            let original = window.frame
            let start = NSEvent.mouseLocation
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
                guard next.type == .leftMouseDragged else { break }
                let now = NSEvent.mouseLocation
                let width = max(CardGeometry.minSize.width, original.width + now.x - start.x)
                let height = max(CardGeometry.minSize.height, original.height - (now.y - start.y))
                window.setFrame(
                    NSRect(x: original.minX, y: original.minY, width: width, height: height),
                    display: true
                )
            }
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}

/// 卡片宿主视图：非激活窗口里 SwiftUI `.plain` 按钮首击被吞的历史问题（≤macOS 14），
/// 覆写 acceptsFirstMouse 兜底（ADR-026；macOS 15+ 系统已修，防御无害）。
/// 普通层级卡片被其他窗口遮挡时，点击可见部分把自己提到所在层最前
/// （03 §10.3"点击后浮到前面"，ADR-029）；floating/desktop 层级下此调用无害。
final class CardHostingView: NSHostingView<CardContentView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.orderFront(nil)
        super.mouseDown(with: event)
    }
}
