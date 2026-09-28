// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// Story 1.14：迁移前备份（ADR-018；data-layer.md「迁移前备份」与「L1 测试清单」）。
struct PreMigrationBackupTests {
    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shike-tests-premig-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private var options: AppDatabase.Options {
        .init(timeZone: TimeZone(identifier: "Asia/Shanghai")!, clock: { TestClock.t0 })
    }

    private func v1ThenV2TestMigrator() -> DatabaseMigrator {
        AppDatabase.makeMigrator(additionalMigrations: [
            (identifier: "v2-test", migrate: { db in
                try db.create(table: "premig_test") { table in
                    table.autoIncrementedPrimaryKey("id")
                }
            }),
        ])
    }

    private func backupFileNames(in directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
    }

    @Test("v1 库追加 v2-test 后打开：先生成 shike-before-v2-test-日期.sqlite（内容为迁移前数据），迁移随后执行")
    func backsUpBeforeMigrating() async throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let dataDirectory = root.appendingPathComponent("Data", isDirectory: true)
        let backupsDirectory = dataDirectory.appendingPathComponent("Backups", isDirectory: true)

        // 第一阶段：只注册 v1，写入一条数据
        let first = try AppDatabase.open(directory: dataDirectory, options: options)
        let noteRepository = NoteRepository(database: first)
        _ = try await noteRepository.create(content: "迁移前的便签")
        let v1Count = try await first.writer.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM note") }
        #expect(v1Count == 1)

        // 第二阶段：带 v2-test 重新打开
        let second = try AppDatabase.open(directory: dataDirectory, options: options, migrator: v1ThenV2TestMigrator())

        let names = try backupFileNames(in: backupsDirectory)
        #expect(names == ["shike-before-v2-test-2026-09-23.sqlite"]) // T0 = 2026-09-23 +08:00

        // 备份内容与迁移前的库一致（复制到独立位置打开）
        let copyURL = root.appendingPathComponent("restored.sqlite")
        try FileManager.default.copyItem(at: backupsDirectory.appendingPathComponent(names[0]), to: copyURL)
        let restored = try DatabaseQueue(path: copyURL.path)
        // 独立打开：journal_mode 为 delete，内容是迁移前的快照（有 note、无 premig_test）
        let mode = try await restored.read { db in
            try String.fetchOne(db, sql: "PRAGMA journal_mode")
        }
        #expect(mode == "delete")
        let restoredCount = try await restored.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note")
        }
        #expect(restoredCount == 1)
        let tables = try await restored.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type='table'")
        }
        #expect(tables.contains("note"))
        #expect(!tables.contains("premig_test"))

        // 迁移随后执行完成
        let migrations = try await second.writer.read { db in
            try String.fetchAll(db, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        #expect(migrations == ["v1", "v2-test"])
    }

    @Test("新建的空库不做迁移前备份")
    func skipsBackupForFreshDatabase() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let dataDirectory = root.appendingPathComponent("Data", isDirectory: true)

        _ = try AppDatabase.open(directory: dataDirectory, options: options, migrator: v1ThenV2TestMigrator())

        let backupsDirectory = dataDirectory.appendingPathComponent("Backups", isDirectory: true)
        #expect(try backupFileNames(in: backupsDirectory).isEmpty)
    }

    @Test("同一天同一迁移已有备份时不再重复生成")
    func doesNotDuplicateSameDayBackup() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let dataDirectory = root.appendingPathComponent("Data", isDirectory: true)
        let backupsDirectory = dataDirectory.appendingPathComponent("Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try "既有备份".write(
            to: backupsDirectory.appendingPathComponent("shike-before-v2-test-2026-09-23.sqlite"),
            atomically: true,
            encoding: .utf8
        )

        // 先注册 v1（绕过备份步骤：手工建库），再带 v2-test 打开
        _ = try AppDatabase.open(directory: dataDirectory, options: options)
        _ = try AppDatabase.open(directory: dataDirectory, options: options, migrator: v1ThenV2TestMigrator())

        let names = try backupFileNames(in: backupsDirectory)
        #expect(names == ["shike-before-v2-test-2026-09-23.sqlite"])
        // 既有文件未被覆盖
        let content = try String(contentsOf: backupsDirectory.appendingPathComponent(names[0]), encoding: .utf8)
        #expect(content == "既有备份")
    }

    @Test("备份目录不可写：openFailed，不执行迁移，库停留在 v1")
    func failsOpenWhenBackupDirectoryNotWritable() throws {
        let root = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(root) }
        let dataDirectory = root.appendingPathComponent("Data", isDirectory: true)
        let backupsDirectory = dataDirectory.appendingPathComponent("Backups", isDirectory: true)

        // 第一阶段：装 v1
        let first = try AppDatabase.open(directory: dataDirectory, options: options)

        // 备份目录设为只读
        try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: backupsDirectory.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: backupsDirectory.path)
        }

        do {
            _ = try AppDatabase.open(directory: dataDirectory, options: options, migrator: v1ThenV2TestMigrator())
            Issue.record("备份目录只读时 open 被接受了（可能以 root 运行）")
        } catch let error as ShikeDataError {
            guard case .openFailed(let reason) = error else {
                Issue.record("应为 openFailed，实际 \(error)")
                return
            }
            // 只读目录映射为权限或 I/O 类原因（failures 表），不落入 simulated 等调试类别
            #expect(reason == .permissionDenied || reason == .ioError, "实际原因 \(reason)")
        }

        // 库仍停留在 v1
        let migrations = try first.writer.read {
            try String.fetchAll($0, sql: "SELECT identifier FROM grdb_migrations ORDER BY identifier")
        }
        #expect(migrations == ["v1"])
    }
}
