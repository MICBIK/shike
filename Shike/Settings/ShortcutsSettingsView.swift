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
                KeyboardShortcuts.Recorder(for: .togglePanel) { _ in
                    // 录制新组合：以新组合重装 CGEventTap 通道（ADR-021）。
                    model.hotkeyService.refreshTap()
                }
                Spacer()
                Toggle(String(localized: .settingsShortcutsEnabled), isOn: $isEnabled)
                    .toggleStyle(.switch)
            }
            if model.hotkeyService.tapAuthorizationDenied {
                Text(String(localized: .settingsShortcutsAccessDenied))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .formStyle(.grouped)
        .onChange(of: isEnabled) { _, newValue in
            model.hotkeyService.setEnabled(newValue)
        }
        .onAppear {
            // 授权"辅助功能"后回到设置页即重试安装（ADR-021）。
            model.hotkeyService.refreshTap()
        }
    }
}
