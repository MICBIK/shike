// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import os
import ShikeData

/// 每日自动备份（app-shell.md「组件契约」）：start() 在后台执行一次备份，
/// 并订阅 NSCalendarDayChanged，跨天时再执行一次。结果和失败只写日志（category backup）。
@MainActor
final class BackupService {
    private let database: AppDatabase
    private let backupsDirectory: URL
    private let keepCount: () -> Int
    private var dayChangedObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - keepCount: 每次备份时取值（来自 preferences.backup.keepCount）。
    init(database: AppDatabase, backupsDirectory: URL, keepCount: @escaping () -> Int) {
        self.database = database
        self.backupsDirectory = backupsDirectory
        self.keepCount = keepCount
    }

    // 与 App 同生命周期（AppDelegate 持有），Swift 6 严格并发下不在 deinit 里做主线程清理；
    // 跨天订阅经 stop() 移除（applicationWillTerminate 调用）。

    func start() {
        backupNow()
        // 跨天再备份；订阅只转发到可直调的 backupNow（L2 直接调用验证）。
        dayChangedObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.backupNow()
            }
        }
    }

    func stop() {
        if let observer = dayChangedObserver {
            NotificationCenter.default.removeObserver(observer)
            dayChangedObserver = nil
        }
    }

    /// 触发一次后台备份（不等待完成，不拖慢调用方）。
    func backupNow() {
        let keep = keepCount()
        Task.detached(priority: .utility) { [database, backupsDirectory] in
            await Self.perform(database: database, directory: backupsDirectory, keep: keep)
        }
    }

    /// 直调备份：等待完成，供 L2 与需要确定性的场景使用。
    func runBackup() async {
        await Self.perform(database: database, directory: backupsDirectory, keep: keepCount())
    }

    private nonisolated static func perform(database: AppDatabase, directory: URL, keep: Int) async {
        do {
            let outcome = try await database.backupIfNeeded(to: directory, keep: keep)
            switch outcome {
            case .created(_, let removed):
                Log.backup.info("备份完成，轮换删除 \(removed.count) 份")
            case .alreadyExists(_, let removed):
                Log.backup.info("当天备份已存在，轮换删除 \(removed.count) 份")
            }
        } catch let error as ShikeDataError {
            Log.backup.error("备份失败：\(error.classification, privacy: .public)")
        } catch {
            Log.backup.error("备份失败：未知错误")
        }
    }
}
