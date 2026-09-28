// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo 的 RmbHighlightedTextField.swift、PlaceholderNSTextView.swift 与
// FocusDirection.swift 移植；去掉自动补全、高亮与对焦方向枚举；Tab 改为 onTab 回调
// （切模式）；回车决策提为纯函数 newlineDecision 并在输入法组合态交还输入法；
// 行数上限改为 03 §4（便签 6、待办 2）（2026-09-28）。

import AppKit
import SwiftUI

/// 面板顶栏下方的快速输入框（S1-04，03 §4）。
struct CaptureTextView: NSViewRepresentable {
    let placeholder: String
    var text: Binding<String>
    var maximumNumberOfLines: Int
    var allowsLineBreaks: Bool
    var focusTrigger: UUID?
    /// 外部驱动的草稿变更令牌（提交清空、模式切换）：焦点态下也必须回写视图，
    /// 否则可见文字与绑定脱节、互相污染（demo 的"活动编辑器不回写"守卫只适用于
    /// 其"提交即关窗"的场景，拾刻的常驻输入框需要显式通道）。
    var externalChangeTrigger: UUID?
    var textContainerDynamicHeight: Binding<CGFloat>?
    var onSubmit: () -> Void
    /// Tab 切换模式（03 §4）；Shift+Tab 同样切换到另一模式。
    var onTab: (_ direction: FocusDirection) -> Void

    private let textFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = CaptureNSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? CaptureNSTextView else {
            return scrollView
        }
        textView.placeholder = placeholder
        textView.font = textFont
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isRichText = false
        textView.importsGraphics = false
        textView.delegate = context.coordinator
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? CaptureNSTextView else { return }
        context.coordinator.parent = self
        textView.placeholder = placeholder

        // 外部变更（提交清空、模式切换）：无条件回写视图（保留光标相对位置）。
        if let trigger = externalChangeTrigger, trigger != context.coordinator.lastExternalChangeTrigger {
            context.coordinator.lastExternalChangeTrigger = trigger
            updateText(in: textView, with: text.wrappedValue)
        }

        // AppKit 在输入法组合期间拥有文字；组合态不替换、不刷新属性（03 §4、规格 IME 安全）。
        if !textView.hasMarkedText() {
            let updatedText = text.wrappedValue
            if updatedText == textView.string {
                refreshPlaceholder(for: textView)
            } else if textView.window?.firstResponder !== textView {
                updateText(in: textView, with: updatedText)
            }
        }

        if let trigger = focusTrigger, trigger != context.coordinator.lastFocusTrigger {
            context.coordinator.lastFocusTrigger = trigger
            if textView.window?.firstResponder !== textView {
                textView.window?.makeFirstResponder(textView)
            }
            let textLength = (textView.string as NSString).length
            textView.setSelectedRange(NSRange(location: textLength, length: 0))
        }

        textView.scrollRangeToVisible(textView.selectedRange())
        adjustDynamicHeight(for: textView, context: context)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // - MARK: 文字与属性

    private func updateText(in textView: NSTextView, with updatedText: String) {
        let selectedRange = textView.selectedRange()
        let updatedTextLength = (updatedText as NSString).length
        let selectionLocation = min(selectedRange.location, updatedTextLength)
        let selectionLength = min(selectedRange.length, updatedTextLength - selectionLocation)

        textView.string = updatedText
        textView.setSelectedRange(NSRange(location: selectionLocation, length: selectionLength))
    }

    private func refreshPlaceholder(for textView: NSTextView) {
        textView.needsDisplay = true
    }

    // - MARK: 高度（03 §4：随内容增高，达上限后框内滚动）

    /// 高度计算（纯函数）：至少一行，随内容增高，上限为 maxLines 行。
    static func captureHeight(usedHeight: CGFloat, lineHeight: CGFloat, maxLines: Int) -> CGFloat {
        let maxHeight = lineHeight * CGFloat(max(maxLines, 1))
        return min(max(usedHeight, lineHeight), maxHeight)
    }

    private func adjustDynamicHeight(for textView: NSTextView, context: Context) {
        guard let dynamicHeight = context.coordinator.parent.textContainerDynamicHeight,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return
        }
        let lineHeight = layoutManager.defaultLineHeight(for: textFont)
        let newHeight = Self.captureHeight(
            usedHeight: layoutManager.usedRect(for: textContainer).height,
            lineHeight: lineHeight,
            maxLines: maximumNumberOfLines
        )
        guard dynamicHeight.wrappedValue != newHeight else { return }
        DispatchQueue.main.async {
            dynamicHeight.wrappedValue = newHeight
        }
    }

    // - MARK: 回车决策（纯函数；L1 覆盖）

    enum NewlineDecision {
        /// 交给输入法（组合态）。
        case toInputMethod
        /// 插入换行（⇧↩ 且模式允许）。
        case insertLineBreak
        /// 提交。
        case submit
        /// 交给 AppKit 默认处理（理论不可达，防御）。
        case passThrough
    }

    /// 回车（insertNewline 命令）的处置：组合态 > ⇧↩（允许换行的模式）> 裸回车提交。
    static func newlineDecision(
        hasMarkedText: Bool,
        allowsLineBreaks: Bool,
        modifiers: NSEvent.ModifierFlags
    ) -> NewlineDecision {
        if hasMarkedText { return .toInputMethod }
        let relevant = modifiers.intersection([.command, .option, .shift, .control])
        if allowsLineBreaks, relevant == .shift { return .insertLineBreak }
        if relevant.isEmpty { return .submit }
        return .passThrough
    }

    // - MARK: Coordinator

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CaptureTextView
        var lastFocusTrigger: UUID?
        var lastExternalChangeTrigger: UUID?

        init(_ parent: CaptureTextView) {
            self.parent = parent
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .shift, .control]) ?? []
                switch CaptureTextView.newlineDecision(
                    hasMarkedText: textView.hasMarkedText(),
                    allowsLineBreaks: parent.allowsLineBreaks,
                    modifiers: modifiers
                ) {
                case .toInputMethod, .passThrough, .insertLineBreak:
                    // insertLineBreak 返回 false 让 shouldChangeTextIn 放行 "\n"。
                    return false
                case .submit:
                    parent.onSubmit()
                    return true
                }
            case #selector(NSResponder.insertTab(_:)):
                parent.onTab(.forward)
                return true
            case #selector(NSResponder.insertBacktab(_:)):
                parent.onTab(.backward)
                return true
            default:
                return false
            }
        }

        func textView(
            _ textView: NSTextView,
            shouldChangeTextIn affectedCharRange: NSRange,
            replacementString: String?
        ) -> Bool {
            guard let replacementString else { return true }
            if replacementString == "\n" {
                // 只有"⇧↩ 且模式允许换行"才真正插入换行；其余回车已被 doCommandBy 消费。
                let modifiers = NSApp.currentEvent?.modifierFlags.intersection([.command, .option, .shift, .control]) ?? []
                return parent.allowsLineBreaks && modifiers == .shift
            }
            if replacementString == "\t" {
                return false
            }
            return true
        }

        func textDidChange(_ obj: Notification) {
            guard let textView = obj.object as? NSTextView else { return }
            if parent.text.wrappedValue != textView.string {
                parent.text.wrappedValue = textView.string
            }
        }
    }
}

// - MARK: 方向（自 demo FocusDirection.swift 收敛为二值）

enum FocusDirection {
    case forward
    case backward
}

// - MARK: AppKit 文本视图（自 demo PlaceholderNSTextView + FocusAwareNSTextView）

final class CaptureNSTextView: NSTextView {
    var placeholder = ""

    override func draw(_ rect: CGRect) {
        super.draw(rect)

        guard string.isEmpty, !hasMarkedText(), !placeholder.isEmpty else { return }
        let textOrigin = NSPoint(
            x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
            y: textContainerInset.height
        )
        placeholder.draw(
            at: textOrigin,
            withAttributes: [
                .font: font ?? .systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.placeholderTextColor,
            ]
        )
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            // 让 AppKit 先完成字段编辑器安装，再把光标移到末尾（移植注释）。
            DispatchQueue.main.async { [weak self] in
                guard let self, window?.firstResponder === self else { return }
                let textLength = (string as NSString).length
                setSelectedRange(NSRange(location: textLength, length: 0))
            }
        }
        return became
    }
}
