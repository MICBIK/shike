// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 设置-通用分页（03 §9）：呼出时进入（S1-03）与开机自启（S1-08）；
/// 需要批准时显示说明与"打开登录项设置"按钮（03 §14）。
struct GeneralSettingsView: View {
    @Bindable var model: SettingsModel
    let launchAtLogin: LaunchAtLoginService
    @State private var isEnabled = false
    @State private var needsApproval = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Picker(String(localized: .settingsGeneralOpenMode), selection: $model.panelOpenMode) {
                Text(String(localized: .settingsGeneralOpenModeLast)).tag(PanelModel.OpenMode.last)
                Text(String(localized: .settingsGeneralOpenModeNote)).tag(PanelModel.OpenMode.note)
                Text(String(localized: .settingsGeneralOpenModeTodo)).tag(PanelModel.OpenMode.todo)
            }
            .pickerStyle(.radioGroup)

            Picker(String(localized: .settingsGeneralMenuBarCounter), selection: $model.menuBarCounter) {
                Text(String(localized: .settingsGeneralCounterNone)).tag(MenuBarCounter.none)
                Text(String(localized: .settingsGeneralCounterOverdueToday)).tag(MenuBarCounter.overdueAndToday)
                Text(String(localized: .settingsGeneralCounterAllIncomplete)).tag(MenuBarCounter.allIncomplete)
            }
            .onChange(of: model.menuBarCounter) { _, _ in
                model.onMenuBarCounterChanged()
            }

            Divider()

            Toggle(String(localized: .settingsGeneralLaunchAtLogin), isOn: $isEnabled)
                .toggleStyle(.switch)
                .onChange(of: isEnabled) { _, newValue in
                    do {
                        try launchAtLogin.setEnabled(newValue)
                    } catch {
                        errorMessage = String(localized: .settingsLaunchAtLoginFailed)
                    }
                    syncState()
                }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red) // 注册/注销失败（开发期 App 不在 /Applications 是常态）
            }

            if needsApproval {
                Text(String(localized: .settingsLaunchAtLoginNeedApproval))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(String(localized: .settingsLaunchAtLoginOpenSettings)) {
                    launchAtLogin.openSystemSettings()
                }
            }
        }
        .padding(20)
        .formStyle(.grouped)
        .onAppear {
            syncState()
        }
    }

    /// 每次显示/操作后都从系统读取状态（03 §9：以系统为准）。
    private func syncState() {
        launchAtLogin.refresh()
        isEnabled = launchAtLogin.isEnabled
        needsApproval = launchAtLogin.status == .requiresApproval
    }
}
