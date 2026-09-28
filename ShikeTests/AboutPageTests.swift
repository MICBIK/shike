// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import Shike

/// Story 1.12：关于页的资源与版本（app-shell.md「L2 测试清单」）。
/// AboutSettingsView 因 View 一致性被推断为 @MainActor，CI 的 Xcode 26 要求在隔离上下文引用其静态成员。
@MainActor
struct AboutPageTests {
    @Test("App 包中有 LICENSE，内容不为空且是 GPL 原文")
    func licenseBundledAndNonEmpty() {
        let text = LicenseWindowController.loadLicenseText()
        #expect(!text.isEmpty)
        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
    }

    @Test("版本格式：版本 <MARKETING>（<BUILD>），取自 Info.plist")
    func versionFormat() {
        // 期望值由 Info.plist 实际值拼出：格式钉死，版本号提升时不会误伤
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        #expect(AboutSettingsView.versionText == "版本 \(short)（\(build)）")
        #expect(AboutSettingsView.versionText.hasPrefix("版本 "))
        #expect(AboutSettingsView.versionText.hasSuffix("）"))
    }

    @Test("源码链接指向 MICBIK/shike")
    func sourceLink() {
        #expect(AboutSettingsView.sourceURL.absoluteString == "https://github.com/MICBIK/shike")
    }
}
