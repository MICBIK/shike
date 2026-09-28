// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.2：全局快捷键服务（app-shell.md「组件契约」、ADR-015）。
/// 真实系统热键的注册路径由人工验收（L3）；这里用替身验证封装逻辑。
@MainActor
struct HotkeyServiceTests {
    /// 建 suite 并登记 defer 清理（仓库约定：测试结束 removePersistentDomain）。
    private func makeSuite() -> (Preferences, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
        return (preferences, suiteName)
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test("默认开启：新偏好为空时 isEnabled 为 true")
    func defaultsToEnabled() {
        let (preferences, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        let service = HotkeyService(preferences: preferences, enable: {}, disable: {})
        #expect(service.isEnabled == true)
    }

    @Test("初始化时读取已存储的关闭状态")
    func readsStoredDisabledState() {
        let (preferences, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        preferences.hotkeyTogglePanelEnabled = false

        let service = HotkeyService(preferences: preferences, enable: {}, disable: {})
        #expect(service.isEnabled == false)
    }

    @Test("setEnabled(false)：调用 disable、持久化；setEnabled(true)：调用 enable、持久化")
    func setEnabledTogglesAndPersists() {
        let (preferences, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        var enableCalls = 0
        var disableCalls = 0
        let service = HotkeyService(
            preferences: preferences,
            enable: { enableCalls += 1 },
            disable: { disableCalls += 1 }
        )

        service.setEnabled(false)
        #expect(service.isEnabled == false)
        #expect(disableCalls == 1)
        #expect(enableCalls == 0)
        #expect(preferences.hotkeyTogglePanelEnabled == false)

        service.setEnabled(true)
        #expect(service.isEnabled == true)
        #expect(enableCalls == 1)
        #expect(preferences.hotkeyTogglePanelEnabled == true)
    }

    @Test("AppEnvironment 组装 HotkeyService：惰性（不触碰系统热键）、状态与偏好一致")
    func appEnvironmentAssemblesInertService() throws {
        let (_, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        #expect(environment.hotkeyService.isEnabled == true)
    }
}
