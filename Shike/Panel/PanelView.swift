// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 面板内容（03 §3）：顶栏「便签｜待办」分段控件；提示条位于顶栏下方；
/// 当前模式为空时显示空状态，非空时显示条数占位（列表在阶段 1 提供）。
struct PanelView: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            if let banner = model.banner {
                Banner(state: banner) { model.retryBanner() }
                Divider()
            }
            content
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
                Text(String(localized: .panelModeTodo)).tag(PanelModel.Mode.todo)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        switch model.mode {
        case .note:
            if model.notes.isEmpty {
                EmptyStateView(mode: .note)
            } else {
                countPlaceholder(model.notes.count)
            }
        case .todo:
            if model.todos.isEmpty {
                EmptyStateView(mode: .todo)
            } else {
                countPlaceholder(model.todos.count)
            }
        }
    }

    private func countPlaceholder(_ count: Int) -> some View {
        VStack {
            Text(String(localized: .panelPlaceholderCount(count)))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 24)
    }
}
