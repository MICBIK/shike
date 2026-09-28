// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 空状态（03 §3、02 验收第 4 条）：便签用 note.text 与"还没有便签"，
/// 待办用 checklist 与"没有待办"；不显示引导句（S1-10 提供）。
struct EmptyStateView: View {
    let mode: PanelModel.Mode

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: mode == .note ? "note.text" : "checklist")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text(mode == .note ? String(localized: .panelEmptyNoteTitle) : String(localized: .panelEmptyTodoTitle))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
