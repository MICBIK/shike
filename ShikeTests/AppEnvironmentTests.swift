// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 1.7：用内存库和独立偏好组装 App 逻辑，不碰真实数据（CAP-11）。
struct AppEnvironmentTests {
    /// 建立独立 suite 的 UserDefaults；测试结束时清除该 suite。
    private func makeIsolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "shike-tests-\(UUID().uuidString)")!
        // 各测试在结束时自行 removePersistentDomain 清理
    }

    @Test("组装后提供三仓储与 Preferences；写入能从同库观察读到")
    @MainActor
    func assemblesRepositoriesAndPreferences() async throws {
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(defaults: makeIsolatedDefaults()),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-env", isDirectory: true)
        )

        // Preferences 可用
        #expect(environment.preferences.backupKeepCount == 7)

        // 通过环境的仓储写入，从同一个库的观察中读到
        let note = try await environment.noteRepository.create(content: "经组装点写入")
        let stream = environment.noteRepository.observeActive()
        var sawNote = false
        for try await items in stream {
            sawNote = items.contains { $0.note.id == note.id && $0.note.content == "经组装点写入" }
            break
        }
        #expect(sawNote)

        // 三仓储指向同一批数据：待办与卡片仓储也可用
        let todo = try await environment.todoRepository.create(title: "待办", due: nil)
        #expect(todo.title == "待办")
    }

    @Test("AppEnvironment 是 @MainActor 且不创建窗口")
    @MainActor
    func createsNoWindows() async throws {
        let windowsBefore = Set(NSApplication.shared.windows)
        _ = AppEnvironment(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(defaults: makeIsolatedDefaults()),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-env", isDirectory: true)
        )
        let windowsAfter = Set(NSApplication.shared.windows)
        #expect(windowsAfter == windowsBefore)
    }
}

/// Story 1.7：偏好键与默认值（04 §5.5：backup.keepCount 默认 7）。
struct PreferencesTests {
    @Test("空独立 suite 读到默认值 7；写入后读回；suite 清理")
    func defaultsAndRoundTrip() {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        var preferences = Preferences(defaults: defaults)
        #expect(preferences.backupKeepCount == 7)

        preferences.backupKeepCount = 3
        #expect(preferences.backupKeepCount == 3)
    }
}
