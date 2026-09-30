// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ShikeData

/// 卡片外观映射（03 §10/§15；S3-01 先落映射表，S3-04 接菜单与设置）。
/// 颜色明暗各一套色值；字号三档；层级映射窗口 level（ADR-025 结论 2）。
enum CardTheme {
    /// 便签纸颜色（红绿蓝分量，明暗两套）。yellow 默认。
    static func background(for color: CardColor, dark: Bool) -> NSColor {
        switch (color, dark) {
        case (.yellow, false): NSColor(srgbRed: 1.00, green: 0.97, blue: 0.78, alpha: 0.97)
        case (.yellow, true): NSColor(srgbRed: 0.32, green: 0.30, blue: 0.16, alpha: 0.97)
        case (.green, false): NSColor(srgbRed: 0.82, green: 0.94, blue: 0.80, alpha: 0.97)
        case (.green, true): NSColor(srgbRed: 0.16, green: 0.30, blue: 0.19, alpha: 0.97)
        case (.blue, false): NSColor(srgbRed: 0.80, green: 0.89, blue: 0.97, alpha: 0.97)
        case (.blue, true): NSColor(srgbRed: 0.15, green: 0.24, blue: 0.33, alpha: 0.97)
        case (.pink, false): NSColor(srgbRed: 0.99, green: 0.85, blue: 0.90, alpha: 0.97)
        case (.pink, true): NSColor(srgbRed: 0.33, green: 0.19, blue: 0.24, alpha: 0.97)
        case (.purple, false): NSColor(srgbRed: 0.91, green: 0.85, blue: 0.98, alpha: 0.97)
        case (.purple, true): NSColor(srgbRed: 0.26, green: 0.20, blue: 0.33, alpha: 0.97)
        case (.gray, false): NSColor(srgbRed: 0.92, green: 0.92, blue: 0.92, alpha: 0.97)
        case (.gray, true): NSColor(srgbRed: 0.26, green: 0.26, blue: 0.27, alpha: 0.97)
        }
    }

    /// 正文字号（03 §10.5：小 / 中（默认）/ 大）。
    static func contentFontSize(for size: CardFontSize) -> CGFloat {
        switch size {
        case .small: 12
        case .medium: 13
        case .large: 16
        }
    }

    /// 卡片层级 → NSWindow.Level（ADR-025 结论 2；ADR-026：桌面层 = desktopIcon+1；
    /// ADR-031：普通层 = normal−1——Übersicht 生产验证值。可成为 key 的非激活面板
    /// 在 normal 层一旦 makeKey（编辑）就顶到层内最前、盖住其他 app 的普通窗口，
    /// 且切空间时带着该位置走（用户三次实测复现）；normal−1 从构造上保证卡片
    /// 永远在其他 app 普通窗口之下，同时仍可点击、可编辑（key 经 CPS steal focus）。
    static func windowLevel(for level: CardLevel) -> NSWindow.Level {
        switch level {
        case .floating: .floating
        case .normal: NSWindow.Level(NSWindow.Level.normal.rawValue - 1)
        case .desktop: NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        }
    }

    /// 空间行为（ADR-030）：普通层级**强制留在所属空间**——"所有空间跟随"的窗口
    /// 切空间后压住目标空间的窗口（用户三指滑动实测），"会被遮挡"（03 §10.3）只在
    /// 窗口属于该空间时成立；跨空间跟随只保留给置顶/桌面层（它们压不住人或本就该
    /// 出现在每块桌面）。置顶/桌面层跨空间时带 .stationary（不随切换移动）。
    /// 全屏压盖用 fullScreenAuxiliary；卡片不进 ⌘` 窗口循环。
    static func collectionBehavior(
        allSpaces: Bool,
        showOverFullScreen: Bool,
        level: CardLevel
    ) -> NSWindow.CollectionBehavior {
        var behavior: NSWindow.CollectionBehavior = (allSpaces && level != .normal)
            ? [.canJoinAllSpaces, .stationary]
            : [.moveToActiveSpace]
        behavior.insert(.ignoresCycle)
        if showOverFullScreen {
            behavior.insert(.fullScreenAuxiliary)
        }
        return behavior
    }
}

/// 卡片几何纯函数（NFR26）：定位错开、钳制、观察流差量。
/// 全部注入屏幕信息，可 L2 直测。
enum CardGeometry {
    /// 新卡默认尺寸（03 §10.2）。
    static let defaultSize = CGSize(width: 240, height: 180)
    /// 最小尺寸（03 §10.2）。
    static let minSize = CGSize(width: 160, height: 100)
    /// 重叠时的错开距离（03 §10.2）。
    static let stagger: CGFloat = 24

    /// 新卡 frame：面板所在屏可见区域中央偏上；与已有卡重叠时依次错开 24pt，
    /// 错开出屏后回卷继续找空位（最多绕 existing 数 + 1 轮，仍无空位则用最后候选钳制入屏）。
    static func initialFrame(
        existingFrames: [CardFrame],
        screenVisibleFrame: NSRect,
        size: CGSize
    ) -> CardFrame {
        let anchorX = screenVisibleFrame.midX - size.width / 2
        let anchorY = screenVisibleFrame.maxY - screenVisibleFrame.height / 3 - size.height / 2
        let maxAttempts = existingFrames.count + 1
        var candidate = NSRect(x: anchorX, y: anchorY, width: size.width, height: size.height)
        for attempt in 0..<maxAttempts {
            let offset = CGFloat(attempt) * stagger
            candidate = NSRect(
                x: anchorX + offset,
                y: anchorY - offset,
                width: size.width,
                height: size.height
            )
            let cardFrame = CardFrame(
                x: candidate.minX, y: candidate.minY,
                width: candidate.width, height: candidate.height
            )
            if !existingFrames.contains(where: { overlaps(cardFrame, $0) }) {
                return clampedFrame(candidate, in: screenVisibleFrame)
            }
        }
        return clampedFrame(candidate, in: screenVisibleFrame)
    }

    /// 矩形相交（共享任何面积即重叠）。
    static func overlaps(_ a: CardFrame, _ b: CardFrame) -> Bool {
        a.x < b.x + b.width && b.x < a.x + a.width
            && a.y < b.y + b.height && b.y < a.y + a.height
    }

    /// 把 frame 钳制进可见区域（保持大小；区域比卡片还小时贴齐左下角）。
    static func clampedFrame(_ frame: NSRect, in visible: NSRect) -> CardFrame {
        let width = min(frame.width, visible.width)
        let height = min(frame.height, visible.height)
        var x = frame.minX
        var y = frame.minY
        x = max(visible.minX, min(x, visible.maxX - width))
        y = max(visible.minY, min(y, visible.maxY - height))
        return CardFrame(x: x, y: y, width: width, height: height)
    }

    /// 调整大小后的钳制：不小于最小尺寸、不超出所在可见区域。
    static func clampedResize(frame: NSRect, in visible: NSRect) -> CardFrame {
        let width = max(minSize.width, min(frame.width, visible.width))
        let height = max(minSize.height, min(frame.height, visible.height))
        return clampedFrame(
            NSRect(x: frame.minX, y: frame.minY, width: width, height: height),
            in: visible
        )
    }
}

/// 卡片对账（NFR24）：由前后两次 `VisibleCard` 快照算出窗口操作。
/// 纯函数，CardManager 执行；frame/options/便签内容任一变化都算 update。
enum CardDiff {
    enum Operation: Equatable {
        case create(Note.ID)
        case update(Note.ID)
        case close(Note.ID)
    }

    static func operations(old: [VisibleCard], new: [VisibleCard]) -> [Operation] {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.card.noteID, $0) })
        let newByID = Dictionary(uniqueKeysWithValues: new.map { ($0.card.noteID, $0) })
        var ops: [Operation] = []
        for (id, newValue) in newByID {
            switch oldByID[id] {
            case nil:
                ops.append(.create(id))
            case .some(let oldValue):
                if oldValue != newValue {
                    ops.append(.update(id))
                }
            }
        }
        for id in oldByID.keys where newByID[id] == nil {
            ops.append(.close(id))
        }
        return ops
    }
}
