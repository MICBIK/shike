// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 关于页（app-shell.md「组件契约」、GPL-3.0 第 5(d) 条）：
/// 图标（占位）、名称、版本、源码链接、版权行、法律声明、"查看许可证"、致谢。
struct AboutSettingsView: View {
    let onViewLicense: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "note.text")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(String(localized: .appName))
                .font(.title2)
            Text(Self.versionText)
                .foregroundStyle(.secondary)

            Link(String(localized: .aboutSource), destination: Self.sourceURL)

            Text(String(localized: .aboutCopyright))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: .aboutLegalNotice))
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(String(localized: .aboutViewLicense), action: onViewLicense)

            VStack(spacing: 2) {
                Text(String(localized: .aboutAcknowledgments))
                    .font(.caption)
                    .bold()
                Text(String(localized: .aboutAcknowledgmentsDetail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
    }

    /// 源码地址（app-shell.md「关于页」）。
    static let sourceURL = URL(string: "https://github.com/MICBIK/shike")!

    /// "版本 0.0.0（1）"：从 Info.plist 读取（app-shell.md「关于页」）。
    static var versionText: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return String(localized: .aboutVersion(short, build))
    }
}
