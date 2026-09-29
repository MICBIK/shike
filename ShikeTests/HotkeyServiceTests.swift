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
        // 未接入 tap 通道前保持惰性（ADR-021）。
        #expect(environment.hotkeyService.isTapChannelActive == false)
    }

    // - MARK: CGEventTap 兜底通道（ADR-021）

    @Test("activateTapChannel：以存储的组合安装 tap；关闭卸载、重开重装")
    func tapChannelLifecycle() {
        let (preferences, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        var installerArgs: [(keyCode: Int, carbonModifiers: Int)] = []
        var installResults: [Bool] = []
        var removeCalls = 0
        let service = HotkeyService(preferences: preferences, enable: {}, disable: {})

        service.activateTapChannel(
            shortcutProvider: { (keyCode: 45, carbonModifiers: 6144) },
            installer: { keyCode, carbonModifiers, _, _ in
                installerArgs.append((keyCode, carbonModifiers))
                installResults.append(true)
                return true
            },
            remover: { removeCalls += 1 }
        )
        // 接入即按当前状态安装一次
        #expect(service.isTapChannelActive == true)
        #expect(installerArgs.count == 1)
        #expect(installerArgs[0].keyCode == 45)
        #expect(installerArgs[0].carbonModifiers == 6144)
        #expect(service.tapAuthorizationDenied == false)

        service.setEnabled(false)
        #expect(removeCalls == 1)
        service.setEnabled(true)
        #expect(installerArgs.count == 2)
        #expect(installerArgs[1] == (45, 6144))
        _ = installResults
    }

    @Test("refreshTap：辅助功能未授权时标记 tapAuthorizationDenied；组合被清空时撤下 tap")
    func tapInstallFailureAndClearing() {
        let (preferences, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        var removeCalls = 0
        var provided: (keyCode: Int, carbonModifiers: Int)? = (45, 6144)
        let service = HotkeyService(preferences: preferences, enable: {}, disable: {})
        service.activateTapChannel(
            shortcutProvider: { provided },
            installer: { _, _, _, _ in false },
            remover: { removeCalls += 1 }
        )
        #expect(service.tapAuthorizationDenied == true)

        // 用户清空快捷键：撤下 tap、清除授权标记
        provided = nil
        service.refreshTap()
        #expect(removeCalls == 1)
        #expect(service.tapAuthorizationDenied == false)
    }

    @Test("acceptFire：150ms 内重复触发折叠为一次，超过后放行")
    func dedupesRapidFires() {
        let (preferences, suiteName) = makeSuite()
        defer { cleanup(suiteName) }
        let service = HotkeyService(preferences: preferences, enable: {}, disable: {})
        let base = Date(timeIntervalSince1970: 1_000)

        #expect(service.acceptFire(now: base) == true)
        #expect(service.acceptFire(now: base.addingTimeInterval(0.1)) == false)
        #expect(service.acceptFire(now: base.addingTimeInterval(0.14)) == false)
        #expect(service.acceptFire(now: base.addingTimeInterval(0.16)) == true)
    }
}
