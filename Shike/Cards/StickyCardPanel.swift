// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 单张卡片的界面模型：便签内容 + 卡片选项（CardManager 推送，视图只渲染）。
@MainActor
@Observable
final class CardModel {
    var content: String
    var options: StickyCardOptions
    var isHovered = false
    /// 系统深色模式（打磨 R4：CardManager 经 KVO 推送，切换深浅色卡片即时换色）。
    var isDark: Bool
    /// 卡片上编辑（S3-06，03 §10.2）：双击进入，点击外部/Esc 结束，0.5 秒防抖自动保存。
    var isEditing = false
    var editingText = ""

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
        isMovable = false // 移动只经顶部操作条的 performDrag（03 §10.2）
        hidesOnDeactivate = false
        level = CardTheme.windowLevel(for: .floating)
    }

    /// 应用选项到窗口属性（颜色/字号在 SwiftUI 层随 options 渲染）。
    func apply(options: StickyCardOptions) {
        level = CardTheme.windowLevel(for: options.level)
        collectionBehavior = CardTheme.collectionBehavior(
            allSpaces: options.allSpaces,
            showOverFullScreen: options.showOverFullScreen
        )
    }
}

/// 卡片内容（03 §10.1）：纸面（所选颜色、圆角 10、正文按字号、超出滚动）
/// + hover 出现的顶部操作条（左拖动区、右层级按钮/⋯/✕）。
struct CardContentView: View {
    @Bindable var model: CardModel
    var onClose: () -> Void
    var onLevelCycle: () -> Void
    /// 拖动开始（控制器置 busy：拖动中不自动隐藏，03 §10.4）。
    var onDragStarted: () -> Void = {}
    var onDragEnded: () -> Void
    /// 卡片菜单改动选项（自动隐藏开关/延迟/不透明度，S3-03）。
    var onOptionsChange: (StickyCardOptions) -> Void = { _ in }
    /// 双击进入编辑（S3-06）。
    var onEditRequest: () -> Void = {}
    /// 编辑文字变化（控制器做 0.5 秒防抖自动保存，03 §10.2）。
    var onEditingTextChange: (String) -> Void = { _ in }
    /// 结束编辑（Esc/点击外部），保存交给控制器。
    var onEditEnd: () -> Void = {}
    /// 在面板中显示（S3-08，03 §10.5）。
    var onShowInPanel: () -> Void = {}

    @FocusState private var editorFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: CardTheme.background(
                    for: model.options.color,
                    dark: model.isDark
                )))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

            if model.isEditing {
                TextEditor(text: $model.editingText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: CardTheme.contentFontSize(for: model.options.fontSize)))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .padding(.top, model.isHovered ? 26 : 10)
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
                        // Esc：结束编辑（03 §10.2）；保存由控制器收尾
                        onEditEnd()
                    }
            } else {
                ScrollView(.vertical) {
                    Text(model.content)
                        .font(.system(size: CardTheme.contentFontSize(for: model.options.fontSize)))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                        .textSelection(.enabled)
                }
                .scrollContentBackground(.hidden)
                .padding(.top, model.isHovered ? 26 : 10)
                .onTapGesture(count: 2) {
                    onEditRequest()
                }
            }
            if model.isHovered || model.isEditing {
                topBar
                    .opacity(model.isHovered ? 1 : 0)
                    .allowsHitTesting(model.isHovered)
                    .animation(Motion.standard(0.15), value: model.isHovered)
            }
        }
        .animation(Motion.standard(0.15), value: model.isEditing)
        .onHover { model.isHovered = $0 }
    }

    /// 顶部操作条：整条是拖动区（performDrag 原生拖动，松手回调持久化），
    /// 右侧三个按钮要接住点击不吃拖动。
    private var topBar: some View {
        HStack(spacing: 6) {
            CardDragBar(
                onDragStarted: { model.isHovered = true }, // 拖动中保持操作条可见（busy 由控制器接管）
                onDragEnded: onDragEnded
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onLevelCycle) {
                Image(systemName: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
            .help(String(localized: .cardBarLevel))
            optionsMenu
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .help(String(localized: .cardMenuUnpin))
        }
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .padding(.horizontal, 4)
                .padding(.top, 4)
        )
        .frame(height: 20)
        .padding(.horizontal, 6)
        .padding(.top, 6)
    }

    /// ⋯ 菜单（03 §10.5 全量，S3-03/S3-05/S3-08）。
    private var optionsMenu: some View {
        Menu {
            sectionEditing
            Picker(String(localized: .cardMenuColor), selection: colorBinding) {
                Text(String(localized: .cardColorYellow)).tag(CardColor.yellow)
                Text(String(localized: .cardColorGreen)).tag(CardColor.green)
                Text(String(localized: .cardColorBlue)).tag(CardColor.blue)
                Text(String(localized: .cardColorPink)).tag(CardColor.pink)
                Text(String(localized: .cardColorPurple)).tag(CardColor.purple)
                Text(String(localized: .cardColorGray)).tag(CardColor.gray)
            }
            .pickerStyle(.inline)
            Picker(String(localized: .settingsCardFontSize), selection: fontSizeBinding) {
                Text(String(localized: .cardFontSizeSmall)).tag(CardFontSize.small)
                Text(String(localized: .cardFontSizeMedium)).tag(CardFontSize.medium)
                Text(String(localized: .cardFontSizeLarge)).tag(CardFontSize.large)
            }
            .pickerStyle(.inline)
            Picker(String(localized: .cardBarLevel), selection: levelBinding) {
                Text(String(localized: .cardLevelFloating)).tag(CardLevel.floating)
                Text(String(localized: .cardLevelNormal)).tag(CardLevel.normal)
                Text(String(localized: .cardLevelDesktop)).tag(CardLevel.desktop)
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
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.button)
        .menuIndicator(.visible)
        .fixedSize()
        .help(String(localized: .cardMenuOptions))
    }

    /// 编辑入口（03 §10.5 第一行）。
    @ViewBuilder
    private var sectionEditing: some View {
        if !model.isEditing {
            Button(String(localized: .listMenuEdit), action: onEditRequest)
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
