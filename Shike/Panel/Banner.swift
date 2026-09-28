// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 顶栏下方的红色错误提示条（03 §3）：文案 + "重试"按钮。
struct Banner: View {
    let state: PanelModel.BannerState
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(state.message)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
            Button(String(localized: .bannerRetry), action: onRetry)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.08))
    }
}
