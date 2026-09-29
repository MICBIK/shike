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
                greetingRow
                captureArea
                recognitionHintBar
                if model.mode == .todo, model.notificationDenied {
                    notificationDeniedBar
                }
                content
                statsBar
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
        // 纸感批次（方向一，ADR-022）：品牌纸青渐变打底；下面仍垫系统厚材质（ADR-024），
        // 渐变留 6% 透明度让材质透气——保留一点 Mac 的磨砂深度，又不吃掉对比度。
        .background(paperGradient.opacity(0.94))
        .background(.thickMaterial)
    }

    /// 纸感底：上青下白的垂直渐变（浅色纸感 / 深色墨青，Assets 双外观）。
    private var paperGradient: some View {
        LinearGradient(
            colors: [
                Color("PaperTop"),
                Color("PaperMid"),
                Color("PaperBottom"),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// 日期问候行（纸感批次）：「9月29日 周二 · 早上好 ☀」（图标走 SF Symbol）。
    private var greetingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Text(GreetingFormat.date.string(from: Date()))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
            Text(GreetingFormat.weekday.string(from: Date()))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Spacer()
            Text(greetingText)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Image(systemName: greetingSymbol)
                .font(.system(size: 10))
                .foregroundStyle(greetingIsNight ? Color.secondary : Color.yellow)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    /// 按时段问候（03 §3 视觉批次）：5–11 早、11–13 午、13–18 下午、其余晚间。
    private var greetingText: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return String(localized: .greetingMorning)
        case 11..<13: return String(localized: .greetingNoon)
        case 13..<18: return String(localized: .greetingAfternoon)
        default: return String(localized: .greetingEvening)
        }
    }

    private var greetingIsNight: Bool {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<18: return false
        default: return true
        }
    }

    private var greetingSymbol: String {
        greetingIsNight ? "moon.fill" : "sun.max.fill"
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
    /// 视觉批次：纸感容器（卡片底）+ 常驻笔图标 + 聚焦青绿描边与光晕。
    private var captureArea: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.accentColor.opacity(captureFocused ? 0.95 : 0.65))
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
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color("CardBackground").opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(
                    captureFocused ? Color.accentColor.opacity(0.85) : Color.accentColor.opacity(0.22),
                    lineWidth: captureFocused ? 1.5 : 1
                )
        )
        .shadow(
            color: captureFocused ? Color.accentColor.opacity(0.28) : Color.accentColor.opacity(0.06),
            radius: captureFocused ? 5 : 2,
            y: 1
        )
        .animation(Motion.standard(0.15), value: captureFocused)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    @State private var captureFocused = false

    /// 底部统计条（纸感批次）：「今天记了 N 条 · 待办完成 N 条」，数字青绿加重。
    private var statsBar: some View {
        let stats = model.todayActivity
        return HStack(spacing: 6) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.accentColor)
            Text(Self.statsLine(notes: stats.notesCreated, todos: stats.todosCompleted))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(
            LinearGradient(
                colors: [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.03)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor.opacity(0.14))
                .frame(height: 0.5)
        }
        .accessibilityElement(children: .combine)
    }

    /// 统计文案：字符串目录里带 Markdown 加粗（**%lld**），这里解析为数字青绿加重。
    static func statsLine(notes: Int, todos: Int) -> AttributedString {
        let raw = String(localized: .panelStatsToday(notes, todos))
        if let attributed = try? AttributedString(markdown: raw) {
            return attributed
        }
        return AttributedString(raw.replacingOccurrences(of: "**", with: ""))
    }

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

/// 问候行的日期/星期格式化（跟随系统区域；DateFormatter 非 Sendable，锁在主 actor）。
@MainActor
private enum GreetingFormat {
    static let date: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMd") // 9月29日 / Sep 29
        return formatter
    }()
    static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("c") // 周二 / Tue
        return formatter
    }()
}
