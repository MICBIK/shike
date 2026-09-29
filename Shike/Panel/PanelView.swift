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
                if model.mode == .todo, model.notificationDenied {
                    notificationDeniedBar
                }
                content
            }
            if let bar = model.deletedBar {
                UndoBar(state: bar) { model.undoLastDelete() }
                    .id(String(describing: bar)) // 视角切换即重建：倒计时与出入场重启
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.standard(), value: model.deletedBar)
        .overlay(alignment: .bottomTrailing) {
            PopoverResizeHandle(
                currentSize: { model.resizeCurrentSize() },
                onResize: { proposed, isFinal in model.resizeApply(proposed, isFinal) }
            )
        }
        // 视觉批次：识别 chip 的弹入/淡出（减弱动态效果时直切）。
        .animation(Motion.standard(), value: model.recognitionHintState)
        .animation(Motion.standard(), value: model.isSearching)
        // 可读性修复（2026-09-29 验收反馈）：面板背景给稳定的实心底，
        // 不再透出壁纸造成"文字发雾"；保留一丝材质透气感。
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.93))
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
    /// 视觉批次：圆角容器实体化 + 聚焦青绿描边。
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
            onFocusChange: { captureFocused = $0 },
            onSubmit: { model.submitCurrentDraft() },
            onTab: { _ in
                // 03 §4：Tab 切换到另一模式（Shift+Tab 同向处理）。
                model.mode = model.mode == .note ? .todo : .note
            },
            onViewReady: { textView in model.captureDidBecomeReady(textView) }
        )
        .frame(height: max(captureHeight, 22))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    captureFocused ? Color.accentColor.opacity(0.85) : Color.primary.opacity(0.08),
                    lineWidth: captureFocused ? 1.5 : 1
                )
        )
        .animation(Motion.standard(0.15), value: captureFocused)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @State private var captureFocused = false

    /// 通知权限被拒提示条（S2-10，03 §14）：仅待办模式显示。
    private var notificationDeniedBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
            Text(String(localized: .bannerNotificationDenied))
                .font(.caption)
            Spacer()
            Button(String(localized: .bannerOpenSystemSettings)) {
                model.openNotificationSettings()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.yellow.opacity(0.12))
    }

    /// 时间识别提示（S2-01，03 §4；视觉批次 chip 化）：输入框下方圆角 chip，
    /// 时钟图标 + 结果（青绿加重，已过为红）；✕ 取消本次识别。
    @ViewBuilder
    private var recognitionHintBar: some View {
        switch model.recognitionHintState {
        case .recognized(let content):
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(content.isPast ? Color.red : Color.accentColor)
                    Text(content.headline)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(content.isPast ? Color.red : Color.accentColor)
                    if let suffix = content.durationSuffix {
                        Text("（\(suffix)）")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        model.dismissRecognition()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(String(localized: .captureRecognitionDismiss))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 3.5)
                .background(
                    Capsule().fill(
                        content.isPast ? Color.red.opacity(0.10) : Color.accentColor.opacity(0.10)
                    )
                )
                .overlay(
                    Capsule().strokeBorder(
                        content.isPast ? Color.red.opacity(0.45) : Color.accentColor.opacity(0.55),
                        lineWidth: 1
                    )
                )
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.scale(scale: 0.94, anchor: .leading).combined(with: .opacity))
        case .dismissed:
            HStack {
                Text(String(localized: .captureRecognitionDismissed))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .transition(.opacity)
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
