// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 桌面卡片：以所属便签为键，一张便签至多一张卡片（data-layer.md「公开类型」）。
public struct StickyCard: Sendable, Equatable {
    public let noteID: Note.ID
    public var frame: CardFrame
    public var options: StickyCardOptions
    public let createdAt: Date
    public var updatedAt: Date
}

/// 屏幕坐标，左下角为原点（与 AppKit 一致）。
public struct CardFrame: Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// 卡片层级。
public enum CardLevel: String, Sendable, Equatable, CaseIterable {
    case floating
    case normal
    case desktop
}

/// 卡片颜色。
public enum CardColor: String, Sendable, Equatable, CaseIterable {
    case yellow, green, blue, pink, purple, gray
}

/// 卡片字号。
public enum CardFontSize: String, Sendable, Equatable, CaseIterable {
    case small, medium, large
}

/// 卡片显示选项。hiddenOpacity 在类型内钳制到 0.0～0.6。
public struct StickyCardOptions: Sendable, Equatable {
    public var level: CardLevel
    public var color: CardColor
    public var fontSize: CardFontSize
    public var autoHide: Bool
    /// 秒，大于 0。
    public var hideDelay: TimeInterval
    /// 0.0～0.6，超出范围的输入在构造时钳制。
    public var hiddenOpacity: Double
    public var allSpaces: Bool
    public var showOverFullScreen: Bool

    public init(
        level: CardLevel,
        color: CardColor,
        fontSize: CardFontSize,
        autoHide: Bool,
        hideDelay: TimeInterval,
        hiddenOpacity: Double,
        allSpaces: Bool,
        showOverFullScreen: Bool
    ) {
        self.level = level
        self.color = color
        self.fontSize = fontSize
        self.autoHide = autoHide
        self.hideDelay = hideDelay
        self.hiddenOpacity = Self.clampOpacity(hiddenOpacity)
        self.allSpaces = allSpaces
        self.showOverFullScreen = showOverFullScreen
    }

    public static func clampOpacity(_ value: Double) -> Double {
        min(max(value, 0.0), 0.6)
    }
}

/// 观察流中的可见卡片：卡片本体，附带所属便签。
public struct VisibleCard: Sendable, Equatable {
    public let card: StickyCard
    public let note: Note
}
