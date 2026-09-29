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

    init(content: String, options: StickyCardOptions) {
        self.content = content
        self.options = options
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
    var onDragEnded: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: CardTheme.background(
                    for: model.options.color,
                    dark: NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                )))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)

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
            .animation(Motion.standard(0.15), value: model.isHovered)

            topBar
                .opacity(model.isHovered ? 1 : 0)
                .allowsHitTesting(model.isHovered)
                .animation(Motion.standard(0.15), value: model.isHovered)
        }
        .onHover { model.isHovered = $0 }
    }

    /// 顶部操作条：整条是拖动区（performDrag 原生拖动，松手回调持久化），
    /// 右侧三个按钮要接住点击不吃拖动。
    private var topBar: some View {
        HStack(spacing: 6) {
            CardDragBar(onDragEnded: onDragEnded)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: onLevelCycle) {
                Image(systemName: "square.stack.3d.up")
            }
            .buttonStyle(.plain)
            .help(String(localized: .cardBarLevel))
            Button {
                // 卡片菜单（⋯）随 S3-08 接入；占位保持 03 §10.1 的结构。
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .disabled(true)
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
}

/// 拖动区：mouseDown 交给窗口 performDrag（阻塞到松手），结束后回调持久化新位置。
private struct CardDragBar: NSViewRepresentable {
    var onDragEnded: () -> Void

    func makeNSView(context: Context) -> DragBarView {
        let view = DragBarView()
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ view: DragBarView, context: Context) {
        view.onDragEnded = onDragEnded
    }

    final class DragBarView: NSView {
        var onDragEnded: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            window.performDrag(with: event)
            // performDrag 返回即松手：交给 CardController 换算并持久化（03 §10.2 移动）。
            onDragEnded()
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .openHand)
        }
    }
}
