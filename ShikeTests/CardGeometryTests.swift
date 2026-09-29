// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // 领域类型的 memberwise init 是 internal（包内约定，同 TodoGroupingTests）

/// S3-01：卡片几何纯函数与观察流对账（NFR26；03 §10.2）。
struct CardGeometryTests {
    private let screen = NSRect(x: 0, y: 0, width: 1_440, height: 900)
    private let size = CGSize(width: 240, height: 180)

    private func frame(_ x: Double, _ y: Double, _ w: Double = 240, _ h: Double = 180) -> CardFrame {
        CardFrame(x: x, y: y, width: w, height: h)
    }

    @Test("首张卡：可见区域中央偏上（水平居中、顶部 1/3 分位）")
    func firstCardAnchor() {
        let f = CardGeometry.initialFrame(existingFrames: [], screenVisibleFrame: screen, size: size)
        #expect(f.x == (1_440 - 240) / 2)
        #expect(f.y == 900 - 900 / 3 - 180 / 2)
    }

    @Test("重叠错开：每张后继卡依次错开 24pt（右下方向）")
    func staggerOnOverlap() {
        let first = CardGeometry.initialFrame(existingFrames: [], screenVisibleFrame: screen, size: size)
        let second = CardGeometry.initialFrame(existingFrames: [first], screenVisibleFrame: screen, size: size)
        #expect(second.x == first.x + 24)
        #expect(second.y == first.y - 24)
        let third = CardGeometry.initialFrame(existingFrames: [first, second], screenVisibleFrame: screen, size: size)
        #expect(third.x == first.x + 48)
        #expect(third.y == first.y - 48)
        // 不重叠的已有卡不触发错开
        let far = frame(1_000, 100)
        let free = CardGeometry.initialFrame(existingFrames: [far], screenVisibleFrame: screen, size: size)
        #expect(free.x == first.x)
        #expect(free.y == first.y)
    }

    @Test("错开出屏后钳制回可见区域（环绕尝试耗尽时仍入屏）")
    func staggerClampedToScreen() {
        let tiny = NSRect(x: 0, y: 0, width: 300, height: 220)
        var existing: [CardFrame] = []
        for _ in 0..<8 {
            let f = CardGeometry.initialFrame(existingFrames: existing, screenVisibleFrame: tiny, size: size)
            let clamped = CardGeometry.clampedFrame(
                NSRect(x: f.x, y: f.y, width: f.width, height: f.height),
                in: tiny
            )
            // 每个候选都被钳制在屏幕内（可能宽度被截到屏宽）
            #expect(clamped.x >= tiny.minX && clamped.x + clamped.width <= tiny.maxX)
            #expect(clamped.y >= tiny.minY && clamped.y + clamped.height <= tiny.maxY)
            existing.append(f)
        }
    }

    @Test("钳制：出界拉回；大于屏幕时贴齐屏幕尺寸")
    func clamping() {
        let inside = CardGeometry.clampedFrame(NSRect(x: 100, y: 100, width: 240, height: 180), in: screen)
        #expect(inside == frame(100, 100))
        let offRight = CardGeometry.clampedFrame(NSRect(x: 1_400, y: 100, width: 240, height: 180), in: screen)
        #expect(offRight.x == 1_440 - 240)
        let below = CardGeometry.clampedFrame(NSRect(x: 100, y: -50, width: 240, height: 180), in: screen)
        #expect(below.y == 0)
        let huge = CardGeometry.clampedFrame(NSRect(x: 10, y: 10, width: 2_000, height: 1_200), in: screen)
        #expect(huge.width == 1_440 && huge.height == 900)
        #expect(huge.x == 0 && huge.y == 0)
    }

    @Test("调整大小钳制：不小于最小尺寸")
    func resizeMinimum() {
        let tooSmall = CardGeometry.clampedResize(frame: NSRect(x: 0, y: 0, width: 80, height: 40), in: screen)
        // 显式转 Double 再比：macOS 27 SDK 下 Double == CGFloat 的混合比较不可靠（打磨台账 2026-09-29）。
        #expect(tooSmall.width == Double(CardGeometry.minSize.width))
        #expect(tooSmall.height == Double(CardGeometry.minSize.height))
    }

    @Test("对账：新增/更新/关闭/无变化")
    func diff() {        let note = Note(
            id: Note.ID(rawValue: 1), uuid: UUID(), content: "甲",
            pinnedAt: nil, createdAt: Date(), updatedAt: Date(), deletedAt: nil
        )
        let options = StickyCardOptions(
            level: .floating, color: .yellow, fontSize: .medium, autoHide: false,
            hideDelay: 3, hiddenOpacity: 0.2, allSpaces: true, showOverFullScreen: false
        )
        let card = StickyCard(
            noteID: note.id, frame: frame(10, 10), options: options,
            createdAt: Date(), updatedAt: Date()
        )
        let item = VisibleCard(card: card, note: note)
        #expect(CardDiff.operations(old: [], new: [item]) == [.create(note.id)])
        #expect(CardDiff.operations(old: [item], new: [item]).isEmpty)
        var movedCard = card
        movedCard.frame = frame(20, 20)
        #expect(CardDiff.operations(old: [item], new: [VisibleCard(card: movedCard, note: note)]) == [.update(note.id)])
        var editedNote = note
        editedNote.content = "甲改"
        #expect(CardDiff.operations(old: [item], new: [VisibleCard(card: card, note: editedNote)]) == [.update(note.id)])
        #expect(CardDiff.operations(old: [item], new: []) == [.close(note.id)])
    }

    @Test("外观判定（打磨 R4）：darkAqua 为深色、aqua 为浅色、高层级回退浅色")
    func appearanceResolution() {
        #expect(CardManager.isDarkAppearance(NSAppearance(named: .darkAqua)!))
        #expect(!CardManager.isDarkAppearance(NSAppearance(named: .aqua)!))
        // 未知/复合外观（如 highContrastAqua）按 bestMatch 规则回落浅色
        #expect(!CardManager.isDarkAppearance(NSAppearance(named: .vibrantLight)!))
    }
}
