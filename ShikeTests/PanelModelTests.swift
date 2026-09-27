// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 1.9：面板模式与尺寸（app-shell.md「组件契约」、03 §3）。
@MainActor
struct PanelModelTests {
    private func makeEnvironment() throws -> AppEnvironment {
        try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: "shike-tests-\(UUID().uuidString)")!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
    }

    @Test("AppEnvironment 组装 PanelModel：默认便签，可切换")
    func modeDefaultsToNoteAndSwitches() throws {
        let environment = try makeEnvironment()
        #expect(environment.panelModel.mode == .note)
        #expect(environment.panelModel.notes.isEmpty)
        #expect(environment.panelModel.todos.isEmpty)

        environment.panelModel.mode = .todo
        #expect(environment.panelModel.mode == .todo)
        environment.panelModel.mode = .note
        #expect(environment.panelModel.mode == .note)
    }
}

/// Story 1.9：面板尺寸常量与屏幕钳制（03 §3）。
struct PanelSizingTests {
    @Test("尺寸常量：默认 360×520、最小 300×360、最大 600×1000")
    func constants() {
        #expect(PanelSizing.defaultSize == NSSize(width: 360, height: 520))
        #expect(PanelSizing.minSize == NSSize(width: 300, height: 360))
        #expect(PanelSizing.maxSize == NSSize(width: 600, height: 1_000))
    }

    @Test("大屏幕上默认尺寸不钳制；超大请求钳到最大")
    func clampingBounds() {
        let big = NSRect(x: 0, y: 0, width: 2_000, height: 1_200)
        #expect(PopoverController.clampedSize(PanelSizing.defaultSize, visibleFrame: big) == PanelSizing.defaultSize)
        #expect(
            PopoverController.clampedSize(NSSize(width: 5_000, height: 5_000), visibleFrame: big)
                == PanelSizing.maxSize
        )
    }

    @Test("可见区域不够时压到最小尺寸；不超出可见区域")
    func clampingSmallScreen() {
        let small = NSRect(x: 0, y: 0, width: 800, height: 400)
        let clamped = PopoverController.clampedSize(PanelSizing.defaultSize, visibleFrame: small)
        #expect(clamped == NSSize(width: 360, height: 360))
        #expect(clamped.height <= small.height)
    }
}
