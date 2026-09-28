// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 设置-通用分页（03 §9）：阶段 1 从"呼出时进入"开始；开机自启在 S1-08（Story 2.9）加入。
struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Picker(String(localized: .settingsGeneralOpenMode), selection: $model.panelOpenMode) {
                Text(String(localized: .settingsGeneralOpenModeLast)).tag(PanelModel.OpenMode.last)
                Text(String(localized: .settingsGeneralOpenModeNote)).tag(PanelModel.OpenMode.note)
                Text(String(localized: .settingsGeneralOpenModeTodo)).tag(PanelModel.OpenMode.todo)
            }
            .pickerStyle(.radioGroup)
        }
        .padding(20)
        .formStyle(.grouped)
    }
}
