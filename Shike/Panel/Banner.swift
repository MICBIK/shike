// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 顶栏下方的红色错误提示条（03 §3）：文案 + "重试"按钮；
/// notFound 形态（打磨 R2）重试大概率无意义，改出"知道了"。
struct Banner: View {
    let state: PanelModel.BannerState
    let onRetry: () -> Void
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Text(state.message)
                .foregroundStyle(.red)
                .lineLimit(2)
            Spacer()
            if state.kind == .notFound, let onDismiss {
                Button(String(localized: .bannerDismiss), action: onDismiss)
            } else {
                Button(String(localized: .bannerRetry), action: onRetry)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.red.opacity(0.08))
    }
}
