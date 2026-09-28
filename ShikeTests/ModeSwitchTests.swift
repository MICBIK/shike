// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.3：模式切换与呼出模式（app-shell.md「组件契约」、03 §9）。
@MainActor
struct ModeSwitchTests {
    // - MARK: 呼出决策纯函数

    @Test("initialMode：last 用上次的模式；固定模式无视 lastMode（全 6 组合）")
    func initialModeCombinations() {
        #expect(PanelModel.initialMode(openMode: .last, lastMode: .note) == .note)
        #expect(PanelModel.initialMode(openMode: .last, lastMode: .todo) == .todo)
        #expect(PanelModel.initialMode(openMode: .note, lastMode: .note) == .note)
        #expect(PanelModel.initialMode(openMode: .note, lastMode: .todo) == .note)
        #expect(PanelModel.initialMode(openMode: .todo, lastMode: .note) == .todo)
        #expect(PanelModel.initialMode(openMode: .todo, lastMode: .todo) == .todo)
    }

    // - MARK: 偏好键

    @Test("panel.lastMode / panel.openMode：默认值、往返、非法值回落")
    func panelModePreferences() {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let preferences = Preferences(defaults: defaults)

        #expect(preferences.panelLastMode == "note")
        #expect(preferences.panelOpenMode == "last")

        preferences.panelLastMode = "todo"
        preferences.panelOpenMode = "todo"
        #expect(preferences.panelLastMode == "todo")
        #expect(preferences.panelOpenMode == "todo")

        defaults.set("bogus", forKey: Preferences.Key.panelLastMode)
        defaults.set("sometimes", forKey: Preferences.Key.panelOpenMode)
        #expect(preferences.panelLastMode == "bogus") // 存储层原样返回；解析在 PanelModel
        #expect(preferences.panelOpenMode == "sometimes")
        #expect(PanelModel.OpenMode(rawValue: preferences.panelOpenMode) == nil) // 消费端回落 last
    }

    // - MARK: PanelModel 行为

    private func makeEnvironment(openMode: String) throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.set(openMode, forKey: Preferences.Key.panelOpenMode)
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: defaults),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        return (environment, suiteName)
    }

    @Test("初始化读取 lastMode：偏好为 todo 时初始模式为 todo")
    func initReadsLastMode() throws {
        let (environment, suiteName) = try makeEnvironment(openMode: "last")
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        environment.preferences.panelLastMode = "todo"

        // 重新组装一份：初始模式来自持久化的 lastMode
        let defaults = UserDefaults(suiteName: suiteName)!
        let second = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: defaults),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        #expect(second.panelModel.mode == .todo)
    }

    @Test("切换模式写入 panel.lastMode；applyOpenMode 按 openMode 决策")
    func modeSwitchPersistsAndApplyOpenMode() throws {
        let (environment, suiteName) = try makeEnvironment(openMode: "last")
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let panelModel = environment.panelModel

        panelModel.mode = .todo
        #expect(environment.preferences.panelLastMode == "todo")

        // openMode = last：applyOpenMode 回到上次的模式
        panelModel.mode = .note
        panelModel.applyOpenMode()
        #expect(panelModel.mode == .note)

        // openMode = todo：applyOpenMode 总是进待办
        environment.preferences.panelOpenMode = "todo"
        panelModel.mode = .note
        panelModel.applyOpenMode()
        #expect(panelModel.mode == .todo)
        #expect(environment.preferences.panelLastMode == "todo")
    }

    @Test("applyOpenMode：非法 openMode 存储值回落 last")
    func applyOpenModeInvalidFallsBackToLast() throws {
        let (environment, suiteName) = try makeEnvironment(openMode: "sometimes")
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        environment.preferences.panelLastMode = "note"
        environment.panelModel.applyOpenMode()
        #expect(environment.panelModel.mode == .note)
    }
}
