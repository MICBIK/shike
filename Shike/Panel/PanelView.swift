// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 面板内容（03 §3）：顶栏「便签｜待办」；其下为错误提示条（顶栏下方）；
/// 再下为快速输入框（S1-04）；当前模式为空时显示空状态，非空时显示条数占位（列表在 2.6/2.7 提供）。
struct PanelView: View {
    @Bindable var model: PanelModel
    @State private var captureHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let banner = model.banner {
                Banner(state: banner) { model.retryBanner() }
                Divider()
            }
            if model.isSearching {
                SearchView(model: model)
            } else {
                captureArea
                recognitionHintBar
                content
            }
            if let summary = model.deletedBarSummary {
                Divider()
                UndoBar(summary: summary) { model.undoLastDelete() }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            PopoverResizeHandle(
                currentSize: { model.resizeCurrentSize() },
                onResize: { proposed, isFinal in model.resizeApply(proposed, isFinal) }
            )
        }
    }

    private var topBar: some View {
        HStack {
            Picker("", selection: $model.mode) {
                Text(String(localized: .panelModeNote)).tag(PanelModel.Mode.note)
                // 待办数字角标（S2-08）：与菜单栏计数同口径，0 不显示
                Text(todoSegmentLabel).tag(PanelModel.Mode.todo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
            Button {
                model.beginSearch()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// 待办分段的角标文案（S2-08）：计数 0 或口径"不显示"时只显示"待办"。
    private var todoSegmentLabel: String {
        let base = String(localized: .panelModeTodo)
        guard let count = model.todoBadgeCount, count > 0 else { return base } // 0 不显示（盲审 F1）
        return "\(base) \(count)"
    }

    /// 快速输入框（03 §4）：高度随内容，便签最多 6 行、待办 2 行后框内滚动。
    private var captureArea: some View {
        CaptureTextView(
            placeholder: placeholderText,
            text: Binding(
                get: { model.currentDraft },
                set: { model.currentDraft = $0 }
            ),
            maximumNumberOfLines: model.mode == .note ? 6 : 2,
            allowsLineBreaks: model.mode == .note,
            focusTrigger: model.focusToken,
            externalChangeTrigger: model.draftResetToken,
            textContainerDynamicHeight: $captureHeight,
            highlightRanges: model.mode == .todo ? (model.recognition?.matchedRanges ?? []) : [],
            onSubmit: { model.submitCurrentDraft() },
            onTab: { _ in
                // 03 §4：Tab 切换到另一模式（Shift+Tab 同向处理）。
                model.mode = model.mode == .note ? .todo : .note
            },
            onViewReady: { textView in model.captureDidBecomeReady(textView) }
        )
        .frame(height: max(captureHeight, 22))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    /// 时间识别提示条（S2-01，03 §4）：输入框下方一行小字；✕ 取消本次识别。
    @ViewBuilder
    private var recognitionHintBar: some View {
        switch model.recognitionHintState {
        case .recognized(let content):
            HStack(spacing: 6) {
                Text("🕒").font(.caption)
                Text(content.headline)
                    .font(.caption)
                    .foregroundStyle(content.isPast ? Color.red : Color.primary)
                if let suffix = content.durationSuffix {
                    Text("（\(suffix)）").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    model.dismissRecognition()
                } label: {
                    Image(systemName: "xmark").font(.caption2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(String(localized: .captureRecognitionDismiss))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        case .dismissed:
            HStack {
                Text(String(localized: .captureRecognitionDismissed))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        case nil:
            EmptyView()
        }
    }

    private var placeholderText: String {
        model.mode == .note
            ? String(localized: .panelCapturePlaceholderNote)
            : String(localized: .panelCapturePlaceholderTodo)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .note:
            if model.notes.isEmpty {
                EmptyStateView(mode: .note)
            } else {
                NoteListView(model: model)
            }
        case .todo:
            if model.todos.isEmpty {
                EmptyStateView(mode: .todo)
            } else {
                TodoListView(model: model)
            }
        }
    }
}
