// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 底部反馈条（S1-07，03 §7；视觉批次 2026-09-29 重构）：
/// 删除视角 = 废纸篓图标 + "已删除「…」" + 撤销键帽；恢复视角 = 青绿对勾 + "已恢复「…」"
/// + 剩余可撤销数；底部 5 秒倒计时细条（模型计时为准，条形为示意）。
struct UndoBar: View {
    let state: PanelModel.DeletedBarState
    let onUndo: () -> Void

    @State private var countdownWidth: CGFloat = 1

    private var isRecovered: Bool {
        if case .recovered = state { return true }
        return false
    }

    private var text: String {
        switch state {
        case .deleted(let summary): return String(localized: .undoBarDeleted(summary))
        case .recovered(let summary, _): return String(localized: .undoBarRecovered(summary))
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isRecovered ? "checkmark.circle" : "trash")
                .font(.caption)
                .foregroundStyle(isRecovered ? Color.accentColor : Color.secondary)
            Text(text)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(isRecovered ? Color.primary : Color.secondary)
            if case .recovered(_, let remaining) = state, remaining > 0 {
                Text(String(localized: .undoBarRemaining(remaining)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 8)
            Button(action: onUndo) {
                HStack(spacing: 5) {
                    Text(String(localized: .undoBarUndo))
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("⌘Z")
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 3))
                        .overlay(
                            RoundedRectangle(cornerRadius: 3)
                                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5)
                        )
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isRecovered ? Color.accentColor.opacity(0.08) : Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .bottom) {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: proxy.size.width * countdownWidth, height: 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 2)
            .allowsHitTesting(false)
        }
        .onAppear { restartCountdown() }
        .onTapGesture { onUndo() }
        .accessibilityAction(named: String(localized: .undoBarUndo), onUndo)
    }

    /// 倒计时细条：视角切换（删除↔恢复）即重启，与模型的重启计时同步。
    private func restartCountdown() {
        countdownWidth = 1
        guard !Motion.reduce else { return }
        withAnimation(.linear(duration: 5)) { countdownWidth = 0 }
    }
}
