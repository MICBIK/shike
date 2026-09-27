// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 未实现分页的占位（03 §9）：显示"将在阶段 N 提供"。
struct PlaceholderSettingsView: View {
    let stage: Int

    var body: some View {
        Text(String(localized: .settingsPlaceholder(stage)))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
