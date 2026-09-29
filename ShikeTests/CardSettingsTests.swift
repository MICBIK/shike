// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// S3-02：设置-卡片分页（03 §9）——新卡片默认值的持久化与非法值回落。
/// SettingsModel 的存储属性 + didSet 写偏好；卡片的消费端（S3-01 pin）读同一批键。
@MainActor
struct CardSettingsTests {
    private func makeModel(suite: String) -> (SettingsModel, Preferences) {
        let defaults = UserDefaults(suiteName: suite)!
        let preferences = Preferences(defaults: defaults)
        let model = SettingsModel(
            hotkeyService: HotkeyService(preferences: preferences),
            launchAtLogin: LaunchAtLoginService(),
            preferences: preferences
        )
        return (model, preferences)
    }

    @Test("默认值与 03 §9 一致：浮在最上层/黄/中/关/3 秒/20%/所有空间/不压全屏")
    func documentDefaults() throws {
        let suite = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let (model, preferences) = makeModel(suite: suite)
        #expect(model.cardLevel == .floating)
        #expect(model.cardColor == .yellow)
        #expect(model.cardFontSize == .medium)
        #expect(!model.cardAutoHide)
        #expect(model.cardHideDelay == 3)
        #expect(model.cardHiddenOpacity == 0.2)
        #expect(model.cardAllSpaces)
        #expect(!model.cardShowOverFullScreen)
        #expect(preferences.cardDefaultOptions.color == .yellow)
    }

    @Test("修改即持久化；卡片消费端（cardDefaultOptions）读到一致值")
    func persistsChanges() throws {
        let suite = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let (model, preferences) = makeModel(suite: suite)
        model.cardLevel = .desktop
        model.cardColor = .green
        model.cardFontSize = .large
        model.cardAutoHide = true
        model.cardHideDelay = 10
        model.cardHiddenOpacity = 0.5
        model.cardAllSpaces = false
        model.cardShowOverFullScreen = true
        let options = preferences.cardDefaultOptions
        #expect(options.level == .desktop)
        #expect(options.color == .green)
        #expect(options.fontSize == .large)
        #expect(options.autoHide)
        #expect(options.hideDelay == 10)
        #expect(options.hiddenOpacity == 0.5)
        #expect(!options.allSpaces)
        #expect(options.showOverFullScreen)
    }

    @Test("非法存储值回落文档默认（写坏的层级/颜色/字号/延迟）")
    func invalidStoredValuesFallBack() throws {
        let suite = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        defaults.set("sideways", forKey: "card.default.level")
        defaults.set("rainbow", forKey: "card.default.color")
        defaults.set("huge", forKey: "card.default.fontSize")
        defaults.set(7.0, forKey: "card.default.hideDelay")
        let preferences = Preferences(defaults: defaults)
        let model = SettingsModel(
            hotkeyService: HotkeyService(preferences: preferences),
            launchAtLogin: LaunchAtLoginService(),
            preferences: preferences
        )
        #expect(model.cardLevel == .floating)
        #expect(model.cardColor == .yellow)
        #expect(model.cardFontSize == .medium)
        #expect(model.cardHideDelay == 3)
        // 消费端同样回落（Preferences 层）
        #expect(preferences.cardDefaultOptions.level == .floating)
        #expect(preferences.cardDefaultOptions.hideDelay == 3.0)
    }

    @Test("不透明度越界钳制到 0～0.6")
    func opacityClamped() throws {
        let suite = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let (model, preferences) = makeModel(suite: suite)
        model.cardHiddenOpacity = 0.9
        #expect(model.cardHiddenOpacity == 0.6)
        #expect(preferences.cardDefaultHiddenOpacity == 0.6)
        model.cardHiddenOpacity = -0.1
        #expect(model.cardHiddenOpacity == 0.0)
        #expect(preferences.cardDefaultHiddenOpacity == 0.0)
    }
}
