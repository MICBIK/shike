// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing
import UserNotifications

@testable import Shike

/// Story 3.10：通知权限（SPEC CAP-10、stage-2-components.md §4、03 §14）。
@MainActor
struct NotificationPermissionTests {
    private func makeModel() throws -> (PanelModel, StubDeniedScheduling, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let scheduling = StubDeniedScheduling()
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true),
            notificationScheduling: scheduling
        )
        return (environment.panelModel, scheduling, suiteName)
    }

    /// 可控授权状态的替身。
    private final class StubDeniedScheduling: NotificationScheduling {
        var status: UNAuthorizationStatus = .notDetermined
        var requested = 0
        var pending: [String] = []

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization() async -> Bool {
            requested += 1
            status = .authorized
            return true
        }
        func pendingIdentifiers() async -> [String] { pending }
        func add(identifier: String, title: String, body: String, userInfo: [String: String], fireDate: Date) async {
            pending.append(identifier)
        }
        func removePending(identifiers: [String]) async {
            pending.removeAll { identifiers.contains($0) }
        }
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test("授权状态刷新：denied 置位提示条条件；授权后复位")
    func deniedStateRefresh() async throws {
        let (model, scheduling, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.notificationDeniedChecker = { await scheduling.authorizationStatus() == .denied }

        scheduling.status = .denied
        await model.refreshNotificationAuthorization()
        #expect(model.notificationDenied == true)

        // 用户在系统设置重新允许后：状态复位
        scheduling.status = .authorized
        await model.refreshNotificationAuthorization()
        #expect(model.notificationDenied == false)
    }

    @Test("打开系统设置：走注入的跳转钩子（L2 记录调用）")
    func openSettingsDelegatesToHook() async throws {
        let (model, _, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        var opened = 0
        model.openNotificationSettings = { opened += 1 }
        model.openNotificationSettings()
        #expect(opened == 1)
    }

    @Test("权限请求后刷新状态（请求钩子 → refresh 闭环）")
    func requestThenRefresh() async throws {
        let (model, scheduling, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.notificationDeniedChecker = { await scheduling.authorizationStatus() == .denied }

        // 提交带时间待办 → 请求 → 状态从 notDetermined 变 authorized → 刷新后不置位
        model.mode = .todo
        model.draftTodo = "周五下午三点交报告"
        model.submitCurrentDraft()
        // 全套运行时提交 Task 可能被主 actor 延迟数秒（观测到的测试环境调度延迟，
        // 非产品缺陷）：窗口放宽到 10 秒。
        try await waitUntil(10) { scheduling.requested == 1 && !model.notificationDenied }
        #expect(model.notificationDenied == false)
    }

    @Test("SettingsModel 权限读取：三态映射")
    func settingsModelPermissionMapping() async {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let preferences = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = SettingsModel(
            hotkeyService: HotkeyService(preferences: preferences, enable: {}, disable: {}),
            launchAtLogin: LaunchAtLoginService(
                statusProvider: { .notRegistered },
                register: {},
                unregister: {},
                openSettings: {}
            ),
            preferences: preferences
        )

        model.notificationAuthorizationReader = { .denied }
        await model.refreshNotificationPermission()
        #expect(model.notificationPermission == .denied)

        model.notificationAuthorizationReader = { .notDetermined }
        await model.refreshNotificationPermission()
        #expect(model.notificationPermission == .notDetermined)

        model.notificationAuthorizationReader = { .authorized }
        await model.refreshNotificationPermission()
        #expect(model.notificationPermission == .granted)
    }

    // 截止时间轮询（仓库约定）；窗口可调（全套运行时主 actor 调度有延迟）。
    private func waitUntil(_ window: TimeInterval = 3, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "等待条件在 \(window) 秒内未满足")
    }
}
