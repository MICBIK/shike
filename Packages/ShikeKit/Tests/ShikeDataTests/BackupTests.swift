// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// Story 1.13：每日备份（data-layer.md「备份」与「L1 测试清单」备份各项）。
struct BackupTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shike-tests-backup-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    /// 打开数据目录中的磁盘库（Asia/Shanghai，固定时钟 T0）。
    private func makeDatabase(in directory: URL) throws -> AppDatabase {
        try AppDatabase.open(
            directory: directory,
            options: .init(timeZone: TimeZone(identifier: "Asia/Shanghai")!, clock: { TestClock.t0 })
        )
    }

    private func noteCount(of database: AppDatabase) async throws -> Int? {
        try await database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note")
        }
    }

    @Test("新建备份：.created、文件名按公历+时区；独立打开 journal_mode=delete 且行数一致")
    func createsBackupOpenableStandalone() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let dataDirectory = root.appendingPathComponent("Data", isDirectory: true)
        let backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)

        let database = try makeDatabase(in: dataDirectory)
        let noteRepository = NoteRepository(database: database)
        _ = try await noteRepository.create(content: "备份内容一")
        _ = try await noteRepository.create(content: "备份内容二")
        let sourceCount = try await noteCount(of: database)
        #expect(sourceCount == 2)

        let outcome = try await database.backupIfNeeded(to: backupsDirectory, keep: 7)
        guard case .created(let url, let removed) = outcome else {
            Issue.record("应为 .created，实际 \(outcome)")
            return
        }
        #expect(url.lastPathComponent == "shike-2026-09-23.sqlite") // T0 = 2026-09-23 12:00 +08:00
        #expect(removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // 复制到不含 -wal/-shm 的位置后独立打开
        let copyDirectory = root.appendingPathComponent("Standalone", isDirectory: true)
        try FileManager.default.createDirectory(at: copyDirectory, withIntermediateDirectories: true)
        let copyURL = copyDirectory.appendingPathComponent("restored.sqlite")
        try FileManager.default.copyItem(at: url, to: copyURL)

        let restored = try DatabaseQueue(path: copyURL.path)
        let mode = try await restored.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode == "delete")
        let restoredCount = try await restored.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note")
        }
        #expect(restoredCount == 2)
    }

    @Test("当天已存在：.alreadyExists，不重复备份，但轮换照常执行")
    func skipsExistingBackupButRotates() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        let database = try makeDatabase(in: root.appendingPathComponent("Data", isDirectory: true))

        _ = try await database.backupIfNeeded(to: backupsDirectory, keep: 2)
        // 塞两份更早的备份，keep=2 时轮换应删掉最旧的 2026-09-21
        try "junk".write(to: backupsDirectory.appendingPathComponent("shike-2026-09-21.sqlite"), atomically: true, encoding: .utf8)
        try "junk".write(to: backupsDirectory.appendingPathComponent("shike-2026-09-22.sqlite"), atomically: true, encoding: .utf8)

        let second = try await database.backupIfNeeded(to: backupsDirectory, keep: 2)
        guard case .alreadyExists(let url, let removed) = second else {
            Issue.record("应为 .alreadyExists，实际 \(second)")
            return
        }
        #expect(url.lastPathComponent == "shike-2026-09-23.sqlite")
        #expect(removed.map(\.lastPathComponent) == ["shike-2026-09-21.sqlite"])

        let names = try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path).sorted()
        #expect(names == ["shike-2026-09-22.sqlite", "shike-2026-09-23.sqlite"])
    }

    @Test("轮换：8 份匹配文件删最旧 1 份；不匹配模式与 shike-before-* 保持不动")
    func rotationKeepsNewestAndSparesOthers() throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }

        for day in 1...8 {
            let name = String(format: "shike-2026-01-%02d.sqlite", day)
            try "junk".write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try "junk".write(to: directory.appendingPathComponent("shike-before-v2-test-2026-01-01.sqlite"), atomically: true, encoding: .utf8)
        try "junk".write(to: directory.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)

        let removed = try AppDatabase.rotate(in: directory, keep: 7)
        #expect(removed.map(\.lastPathComponent) == ["shike-2026-01-01.sqlite"])

        let names = Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
        #expect(!names.contains("shike-2026-01-01.sqlite"))
        #expect(names.contains("shike-2026-01-02.sqlite"))
        #expect(names.contains("shike-2026-01-08.sqlite"))
        #expect(names.contains("shike-before-v2-test-2026-01-01.sqlite"))
        #expect(names.contains("notes.txt"))
    }

    @Test("跨日边界：UTC 2026-09-23 16:30 在 Asia/Shanghai 下为 shike-2026-09-24.sqlite")
    func timeZoneDateBoundary() {
        let utcInstant = Date(timeIntervalSince1970: 1_790_181_000) // 2026-09-23 16:30:00 UTC
        let name = AppDatabase.backupFileName(for: utcInstant, timeZone: TimeZone(identifier: "Asia/Shanghai")!)
        #expect(name == "shike-2026-09-24.sqlite")

        // 同一时刻在 UTC 下是 09-23，证明与系统的区域设置无关
        let utcName = AppDatabase.backupFileName(for: utcInstant, timeZone: TimeZone(identifier: "UTC")!)
        #expect(utcName == "shike-2026-09-23.sqlite")
    }

    @Test("残留的临时文件先被清理，再照常备份")
    func cleansLeftoverTemporaries() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try "partial".write(
            to: backupsDirectory.appendingPathComponent(".shike-2026-01-01.sqlite.partial"),
            atomically: true,
            encoding: .utf8
        )

        let database = try makeDatabase(in: root.appendingPathComponent("Data", isDirectory: true))
        _ = try await database.backupIfNeeded(to: backupsDirectory, keep: 7)

        let names = try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path)
        #expect(!names.contains(".shike-2026-01-01.sqlite.partial"))
        #expect(names.count == 1)
    }

    @Test("simulateWriteFailure 开启时备份照常执行并返回 .created")
    func backupIgnoresSimulatedWriteFailure() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let database = try AppDatabase.inMemory(options: .init(simulateWriteFailure: true))

        let outcome = try await database.backupIfNeeded(
            to: root.appendingPathComponent("Backups", isDirectory: true),
            keep: 7
        )
        guard case .created = outcome else {
            Issue.record("应为 .created，实际 \(outcome)")
            return
        }
    }

    @Test("备份目录不可写：抛 backupFailed，主库不受影响")
    func failsWhenDirectoryNotWritable() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let backupsDirectory = root.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: backupsDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backupsDirectory.path)
        }

        let database = try makeDatabase(in: root.appendingPathComponent("Data", isDirectory: true))
        let noteRepository = NoteRepository(database: database)
        _ = try await noteRepository.create(content: "主库数据")

        do {
            _ = try await database.backupIfNeeded(to: backupsDirectory, keep: 7)
            Issue.record("应抛出 backupFailed")
        } catch let error as ShikeDataError {
            guard case .backupFailed = error else {
                Issue.record("应为 backupFailed，实际 \(error)")
                return
            }
        }

        // 主库不受影响：数据仍在，目录中没有残留文件
        let count = try await noteCount(of: database)
        #expect(count == 1)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path)
        #expect(leftovers.isEmpty)
    }
}
