// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import KeyboardShortcuts
import SwiftUI

/// 设置-快捷键分页（S1-02，03 §9）：录制"呼出 / 收起面板"的组合，并可启用/关闭。
struct ShortcutsSettingsView: View {
    let model: SettingsModel
    @State private var isEnabled: Bool

    init(model: SettingsModel) {
        self.model = model
        _isEnabled = State(initialValue: model.hotkeyService.isEnabled)
    }

    var body: some View {
        Form {
            HStack {
                Text(String(localized: .settingsShortcutsTogglePanel))
                KeyboardShortcuts.Recorder(for: .togglePanel)
                Spacer()
                Toggle(String(localized: .settingsShortcutsEnabled), isOn: $isEnabled)
                    .toggleStyle(.switch)
            }
        }
        .padding(20)
        .formStyle(.grouped)
        .onChange(of: isEnabled) { _, newValue in
            model.hotkeyService.setEnabled(newValue)
        }
    }
}
