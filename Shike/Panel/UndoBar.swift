// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 底部撤销提示条（S1-07，03 §7）："已删除「前 12 个字…」"+ 撤销；5 秒自动消失（计时在模型）。
struct UndoBar: View {
    let summary: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(String(localized: .undoBarDeleted(summary)))
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            Button(String(localized: .undoBarUndo), action: onUndo)
                .font(.caption)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
