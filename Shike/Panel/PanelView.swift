// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 面板内容（03 §3）：顶栏只有「便签｜待办」分段控件；
/// 提示条（顶栏下方）与列表/空状态由 Story 1.10 接入。
struct PanelView: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(spacing: 0) {
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

            Divider()

            // 列表与空状态由 Story 1.10 接入。
            Spacer()
        }
    }
}
