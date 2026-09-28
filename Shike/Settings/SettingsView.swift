// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 设置窗口内容（03 §9）：顶部六个分页，由 SettingsTab 注册表驱动。
struct SettingsView: View {
    @Bindable var model: SettingsModel
    let onViewLicense: () -> Void

    var body: some View {
        TabView(selection: $model.selectedTab) {
            ForEach(SettingsTab.allCases) { tab in
                tabContent(tab)
                    .tabItem { Text(tab.title) }
                    .tag(tab)
            }
        }
        .frame(width: 460, height: 380)
    }

    @ViewBuilder
    private func tabContent(_ tab: SettingsTab) -> some View {
        switch tab {
        case .about:
            AboutSettingsView(onViewLicense: onViewLicense)
        case .shortcuts:
            ShortcutsSettingsView(model: model)
        case .general:
            GeneralSettingsView(model: model, launchAtLogin: model.launchAtLogin)
        default:
            if let stage = tab.placeholderStage {
                PlaceholderSettingsView(stage: stage)
            }
        }
    }
}
