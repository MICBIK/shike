// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

extension AppDatabase {
    /// 每日备份的结果（data-layer.md「备份」）；removed 是本次轮换删除的文件。
    public enum BackupOutcome: Equatable, Sendable {
        case created(URL, removed: [URL])
        case alreadyExists(URL, removed: [URL])
    }

    /// 每日备份：当天已存在时跳过（仍轮换）；否则在线备份、目标库改 journal_mode、原子改名。
    /// `keep` 至少为 1。任何失败都删除临时文件并抛出 `backupFailed(原因)`，主库不受影响。
    public func backupIfNeeded(to directory: URL, keep keepCount: Int) async throws -> BackupOutcome {
        let fileName = Self.backupFileName(for: options.clock(), timeZone: options.timeZone)
        let keep = max(keepCount, 1)

        return try await Task.detached(priority: .utility) {
            do {
                let fileManager = FileManager.default
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try Self.cleanLeftoverTemporaries(in: directory)

                let finalURL = directory.appendingPathComponent(fileName)

                if fileManager.fileExists(atPath: finalURL.path) {
                    let removed = try Self.rotate(in: directory, keep: keep)
                    return BackupOutcome.alreadyExists(finalURL, removed: removed)
                }

                let temporaryURL = directory.appendingPathComponent("." + fileName + ".partial")
                do {
                    try Self.writeOnlineBackup(from: self.writer, to: temporaryURL)
                    try fileManager.moveItem(at: temporaryURL, to: finalURL)
                } catch {
                    // 失败时删除临时文件（含边车）；主库未被备份过程改动。
                    Self.removeTemporaryArtifacts(at: temporaryURL)
                    throw ShikeDataError.backupFailed(mapFailure(error))
                }

                let removed = try Self.rotate(in: directory, keep: keep)
                return BackupOutcome.created(finalURL, removed: removed)
            } catch let error as ShikeDataError {
                throw error
            } catch {
                // 目录创建、残留清理、轮换的失败同样按备份失败抛出（data-layer.md「备份」）。
                throw ShikeDataError.backupFailed(mapFailure(error))
            }
        }.value
    }

    /// 在线备份（GRDB 文档模式）：目标端在无事务的 barrier 写中完成备份；
    /// 目标库复制了源库的 WAL 页头，紧跟着在同一连接上改回 journal_mode=DELETE
    /// （PRAGMA 不能在事务中执行，fetchOne 同时消费其返回行）。
    /// DatabaseQueue 在函数返回时释放连接，journal_mode 落盘。
    private static func writeOnlineBackup(from writer: any DatabaseWriter, to targetURL: URL) throws {
        let targetQueue = try DatabaseQueue(path: targetURL.path)
        try targetQueue.writeWithoutTransaction { destination in
            try writer.read { source in
                try source.backup(to: destination)
            }
            _ = try String.fetchOne(destination, sql: "PRAGMA journal_mode = DELETE")
        }
        removeSidecars(of: targetURL)
    }

    /// 只删除 SQLite 边车（-wal/-shm/-journal）；备份中途退出时目标库可能留下它们。
    /// 边车残留不影响备份正确性，删除失败可以忽略。
    static func removeSidecars(of url: URL) {
        let fileManager = FileManager.default
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fileManager.removeItem(atPath: url.path + suffix)
        }
    }

    /// 删除临时文件及 SQLite 边车（-wal/-shm/-journal）。
    /// 边车残留不影响备份正确性，删除失败可以忽略。
    static func removeTemporaryArtifacts(at temporaryURL: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: temporaryURL)
        for suffix in ["-wal", "-shm", "-journal"] {
            try? fileManager.removeItem(atPath: temporaryURL.path + suffix)
        }
    }

    /// 文件名 `shike-YYYY-MM-DD.sqlite`：公历 + 指定时区，en_US_POSIX 与系统区域无关。
    static func backupFileName(for date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "shike-\(formatter.string(from: date)).sqlite"
    }

    /// 清理上次中断残留的临时文件（`.shike-*.sqlite.partial` 及其边车）。
    static func cleanLeftoverTemporaries(in directory: URL) throws {
        let fileManager = FileManager.default
        for item in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let name = item.lastPathComponent
            let isMain = name.hasPrefix(".") && name.hasSuffix(".sqlite.partial")
            let isSidecar = name.hasPrefix(".") && (name.hasSuffix(".sqlite.partial-wal")
                || name.hasSuffix(".sqlite.partial-shm")
                || name.hasSuffix(".sqlite.partial-journal"))
            if isMain || isSidecar {
                try fileManager.removeItem(at: item)
            }
        }
    }

    /// 轮换：只处理 `^shike-\d{4}-\d{2}-\d{2}\.sqlite$`，按文件名日期保留最新 `keep` 份。
    static func rotate(in directory: URL, keep: Int) throws -> [URL] {
        let fileManager = FileManager.default
        let pattern = /^shike-(\d{4})-(\d{2})-(\d{2})\.sqlite$/

        let backups = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .compactMap { url -> (URL, String)? in
                guard let match = url.lastPathComponent.firstMatch(of: pattern) else { return nil }
                let (year, month, day) = (match.1, match.2, match.3)
                return (url, "\(year)-\(month)-\(day)")
            }
            .sorted { $0.1 > $1.1 } // 文件名日期即字典序

        guard backups.count > keep else { return [] }
        let removed = backups.suffix(from: keep).map(\.0)
        for url in removed {
            try fileManager.removeItem(at: url)
        }
        return removed
    }
}
