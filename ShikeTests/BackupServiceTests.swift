// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 1.13：BackupService 的直调备份与偏好轮换（app-shell.md「L2 测试清单」；
/// NSCalendarDayChanged 订阅只转发到可直调的方法）。
@MainActor
struct BackupServiceTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shike-tests-service-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    @Test("runBackup 在 Backups/ 产出当日备份（数据目录不存在时先创建）")
    func runBackupProducesTodaysFile() async throws {
        let dataDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dataDirectory) }

        let database = try AppDatabase.inMemory()
        let service = BackupService(
            database: database,
            backupsDirectory: dataDirectory.appendingPathComponent("Backups", isDirectory: true),
            keepCount: { 7 }
        )

        await service.runBackup()

        let names = try FileManager.default.contentsOfDirectory(
            atPath: dataDirectory.appendingPathComponent("Backups", isDirectory: true).path
        )
        #expect(names.count == 1)
        #expect(names[0].hasPrefix("shike-"))
        #expect(names[0].hasSuffix(".sqlite"))
    }

    @Test("保留份数取自 backup.keepCount，轮换删除最旧备份")
    func rotatesByPreferenceKeepCount() async throws {
        let dataDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dataDirectory) }
        let backupsDirectory = dataDirectory.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        // 用 2020 年的固定日期：必然早于运行当天（轮换保留最新的），也不会与当天重名
        for name in ["shike-2020-01-01.sqlite", "shike-2020-01-02.sqlite", "shike-2020-01-03.sqlite"] {
            try "junk".write(to: backupsDirectory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        let suiteName = "shike-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        var preferences = Preferences(defaults: defaults)
        preferences.backupKeepCount = 2

        let database = try AppDatabase.inMemory()
        let service = BackupService(
            database: database,
            backupsDirectory: backupsDirectory,
            keepCount: { preferences.backupKeepCount }
        )
        await service.runBackup()

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path))
        // 4 份匹配文件按 keep=2 轮换：最旧的两份被删，保留 2020-01-03 与当天的备份
        #expect(names.count == 2)
        #expect(names.contains("shike-2020-01-03.sqlite"))
        #expect(!names.contains("shike-2020-01-01.sqlite"))
        #expect(!names.contains("shike-2020-01-02.sqlite"))
        #expect(names.contains { $0.hasPrefix("shike-") && !$0.hasPrefix("shike-2020-") })
    }

    @Test("NSCalendarDayChanged 订阅转发到可直调的备份方法")
    func dayChangedTriggersBackup() async throws {
        let dataDirectory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dataDirectory) }
        let backupsDirectory = dataDirectory.appendingPathComponent("Backups", isDirectory: true)

        let database = try AppDatabase.inMemory()
        let service = BackupService(
            database: database,
            backupsDirectory: backupsDirectory,
            keepCount: { 7 }
        )
        service.start()
        defer { service.stop() }

        // 等待 start() 的后台首次备份落盘
        try await waitForBackup(at: backupsDirectory)
        // 删掉当天备份，制造"通知到来时还没有备份"的可观察状态
        for name in try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path) {
            try FileManager.default.removeItem(at: backupsDirectory.appendingPathComponent(name))
        }

        // 跨天通知 → 订阅转发 → 再次备份
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        try await waitForBackup(at: backupsDirectory)
    }

    /// 轮询等待备份目录出现备份文件（backupNow 是后台执行，不等待完成）。
    private func waitForBackup(at directory: URL, timeout: TimeInterval = 3) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path),
               names.contains(where: { $0.hasSuffix(".sqlite") }) {
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("等待超时：Backups/ 中没有出现备份文件")
    }
}
