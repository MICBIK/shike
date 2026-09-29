// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ShikeData
import SwiftUI

/// 设置-卡片分页（S3-02，03 §9）：新卡片的默认层级、颜色、字号、自动隐藏
/// （开关/延迟/隐藏后不透明度）与空间（所有空间、是否显示在全屏应用之上）。
/// 这些值只决定"新卡片"的初始选项；已有卡片各自的设置在卡片菜单里改（S3-08）。
struct CardsSettingsView: View {
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Picker(String(localized: .settingsCardLevel), selection: $model.cardLevel) {
                Text(String(localized: .cardLevelFloating)).tag(CardLevel.floating)
                Text(String(localized: .cardLevelNormal)).tag(CardLevel.normal)
                Text(String(localized: .cardLevelDesktop)).tag(CardLevel.desktop)
            }
            Picker(String(localized: .settingsCardColor), selection: $model.cardColor) {
                Text(String(localized: .cardColorYellow)).tag(CardColor.yellow)
                Text(String(localized: .cardColorGreen)).tag(CardColor.green)
                Text(String(localized: .cardColorBlue)).tag(CardColor.blue)
                Text(String(localized: .cardColorPink)).tag(CardColor.pink)
                Text(String(localized: .cardColorPurple)).tag(CardColor.purple)
                Text(String(localized: .cardColorGray)).tag(CardColor.gray)
            }
            Picker(String(localized: .settingsCardFontSize), selection: $model.cardFontSize) {
                Text(String(localized: .cardFontSizeSmall)).tag(CardFontSize.small)
                Text(String(localized: .cardFontSizeMedium)).tag(CardFontSize.medium)
                Text(String(localized: .cardFontSizeLarge)).tag(CardFontSize.large)
            }
            Divider()
            Toggle(String(localized: .settingsCardAutoHide), isOn: $model.cardAutoHide)
            if model.cardAutoHide {
                Picker(String(localized: .settingsCardHideDelay), selection: $model.cardHideDelay) {
                    ForEach(SettingsModel.hideDelayOptions, id: \.self) { seconds in
                        Text(String(localized: .settingsCardHideDelaySeconds(Int(seconds)))).tag(seconds)
                    }
                }
                Picker(String(localized: .settingsCardHiddenOpacity), selection: $model.cardHiddenOpacity) {
                    ForEach(SettingsModel.hiddenOpacityOptions, id: \.self) { opacity in
                        Text(String(localized: .settingsCardHiddenOpacityPercent(Int((opacity * 100).rounded()))))
                            .tag(opacity)
                    }
                }
            }
            Divider()
            Picker(String(localized: .settingsCardAllSpaces), selection: $model.cardAllSpaces) {
                Text(String(localized: .cardSpaceAllSpaces)).tag(true)
                Text(String(localized: .cardSpaceCurrentOnly)).tag(false)
            }
            Toggle(String(localized: .settingsCardShowOverFullScreen), isOn: $model.cardShowOverFullScreen)
        }
    }
}
