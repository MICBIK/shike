// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import ShikeData
import SwiftUI
import Testing

@testable import Shike

/// Story 2.1：面板行为——Esc 顺序、尺寸把手与记忆（app-shell.md「组件契约」、03 §3、§13）。
@MainActor
struct PanelBehaviorTests {
    // - MARK: 偏好键 panel.size

    @Test("panel.size：未写入时用默认尺寸；写入后按存储值恢复")
    func panelSizeDefaultAndRoundtrip() {
        let defaults = UserDefaults(suiteName: "shike-tests-\(UUID().uuidString)")!
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.panelSize == CGSize(width: 360, height: 520))

        preferences.panelSize = CGSize(width: 420, height: 560)
        #expect(preferences.panelSize == CGSize(width: 420, height: 560))
        #expect(defaults.string(forKey: Preferences.Key.panelSize) == "420.0x560.0")
    }

    @Test("panel.size：存储值损坏时回落默认，绝不 crash")
    func panelSizeInvalidFallsBackToDefault() {
        let defaults = UserDefaults(suiteName: "shike-tests-\(UUID().uuidString)")!
        defaults.set("abc", forKey: Preferences.Key.panelSize)
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.panelSize == CGSize(width: 360, height: 520))

        defaults.set("0x100", forKey: Preferences.Key.panelSize)
        #expect(preferences.panelSize == CGSize(width: 360, height: 520))

        defaults.set("420.0x560.0x9", forKey: Preferences.Key.panelSize)
        #expect(preferences.panelSize == CGSize(width: 360, height: 520))
    }

    @Test("panel.size 解析：接受正数宽高，拒绝零、负数与非数字")
    func parsePanelSizeCases() {
        #expect(Preferences.parsePanelSize("300x360") == CGSize(width: 300, height: 360))
        #expect(Preferences.parsePanelSize("12.5x7.25") == CGSize(width: 12.5, height: 7.25))
        #expect(Preferences.parsePanelSize("0x360") == nil)
        #expect(Preferences.parsePanelSize("-3x360") == nil)
        #expect(Preferences.parsePanelSize("300") == nil)
        #expect(Preferences.parsePanelSize("") == nil)
    }

    // - MARK: Esc 顺序（03 §13：结束编辑 → 收起面板）

    @Test("Esc：编辑中先结束编辑、不收起；非编辑则收起")
    func escapeOrdering() {
        #expect(PopoverController.escapeOutcome(editingHandled: true) == .consumedByEditing)
        #expect(PopoverController.escapeOutcome(editingHandled: false) == .closesPanel)
    }

    // - MARK: 防"刚关又开"（阶段 0 行为的回归，S1-01 AC）

    @Test("防刚关又开：已显示则关闭；刚收起 10 毫秒内不重开；超过窗口则打开")
    func debounceWindow() {
        // 面板显示中：toggle 走关闭
        #expect(PopoverController.shouldDebounceClose(isShown: true, intervalSinceClose: 999) == true)
        // 刚收起（0.005s）：不重新打开
        #expect(PopoverController.shouldDebounceClose(isShown: false, intervalSinceClose: 0.005) == true)
        // 边界：恰好 10 毫秒视为已出窗（< 才防抖）
        #expect(PopoverController.shouldDebounceClose(isShown: false, intervalSinceClose: 0.01) == false)
        // 已超过窗口：正常打开
        #expect(PopoverController.shouldDebounceClose(isShown: false, intervalSinceClose: 0.5) == false)
        // 初始 distantPast 场景：间隔极大，不防抖
        #expect(PopoverController.shouldDebounceClose(isShown: false, intervalSinceClose: 10_000) == false)
    }

    // - MARK: 尺寸把手

    @Test("把手建议尺寸经钳制应用；只有拖动结束才持久化")
    func applyResizeClampsAndPersistsOnlyAtEnd() {
        let popoverController = PopoverController(
            contentViewController: NSHostingController(rootView: Text("")),
            initialSize: CGSize(width: 360, height: 520)
        )
        var persisted: [CGSize] = []
        popoverController.persistSize = { persisted.append($0) }

        // 拖大：即时生效（期望值用同一钳制函数计算——验证接线，数学由 PanelSizingTests 兜底），不持久化
        let visibleFrame = PopoverController.visibleFrame(for: nil)
        let expectedMid = PopoverController.clampedSize(
            NSSize(width: 500, height: 600),
            visibleFrame: visibleFrame
        )
        popoverController.applyResize(CGSize(width: 500, height: 600), isFinal: false)
        #expect(popoverController.popover.contentSize == expectedMid)
        #expect(persisted.isEmpty)

        // 结束时持久化（持久化的是钳制后的值，与即时生效的一致）
        popoverController.applyResize(CGSize(width: 500, height: 600), isFinal: true)
        #expect(persisted == [CGSize(width: expectedMid.width, height: expectedMid.height)])

        // 拖太小：钳到最小尺寸
        popoverController.applyResize(CGSize(width: 10, height: 10), isFinal: true)
        #expect(popoverController.popover.contentSize == NSSize(width: 300, height: 360))
        #expect(persisted.last == CGSize(width: 300, height: 360))

        // 拖太大：钳到最大值与可见区域（测试机的屏幕高度可能小于 1000+边距）中的较小者
        let expectedMax = PopoverController.clampedSize(
            NSSize(width: 5_000, height: 5_000),
            visibleFrame: visibleFrame
        )
        popoverController.applyResize(CGSize(width: 5_000, height: 5_000), isFinal: true)
        #expect(popoverController.popover.contentSize == expectedMax)
        #expect(popoverController.popover.contentSize.width <= 600)
    }

    @Test("初始尺寸来自偏好设置并经钳制")
    func initialSizeFromPreferencesIsClamped() {
        let popoverController = PopoverController(
            contentViewController: NSHostingController(rootView: Text("")),
            initialSize: CGSize(width: 9_999, height: 9_999)
        )
        let expectedMax = PopoverController.clampedSize(
            NSSize(width: 9_999, height: 9_999),
            visibleFrame: PopoverController.visibleFrame(for: nil)
        )
        #expect(popoverController.popover.contentSize == expectedMax)
        #expect(popoverController.popover.contentSize.width <= 600)
    }

    // - MARK: PanelModel 的把手与 Esc 回调（默认空实现，供 L2 组装）

    @Test("PanelModel 默认回调：无编辑时 Esc 落到收起；有编辑时结束并返回 true（S1-05 接入）")
    func panelModelCallbacksDefaultAndInjectable() async throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        // 默认：无编辑状态，Esc 落到"收起面板"
        #expect(environment.panelModel.endEditingIfNeeded() == false)
        #expect(environment.panelModel.resizeCurrentSize() == CGSize(width: 360, height: 520))

        // 注入替身后尺寸回调跟随
        var applied: [CGSize] = []
        environment.panelModel.resizeCurrentSize = { CGSize(width: 400, height: 500) }
        environment.panelModel.resizeApply = { size, _ in applied.append(size) }
        #expect(environment.panelModel.resizeCurrentSize() == CGSize(width: 400, height: 500))
        environment.panelModel.resizeApply(CGSize(width: 1, height: 2), true)
        #expect(applied == [CGSize(width: 1, height: 2)])

        // 编辑态（S1-05）：有编辑时 Esc 结束编辑并返回 true
        let note = try await environment.noteRepository.create(content: "x")
        environment.panelModel.editingNoteID = note.id
        environment.panelModel.editingNoteText = "y"
        #expect(environment.panelModel.endEditingIfNeeded() == true)
        #expect(environment.panelModel.editingNoteID == nil)
        #expect(environment.panelModel.editingNoteText == "")
    }
}
