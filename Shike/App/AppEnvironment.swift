// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 唯一的组装点（app-shell.md「组件契约」）：
/// 由它创建仓储与各项服务，测试可以用内存库和独立偏好组装整个 App 逻辑。
/// 除它之外没有全局单例；它不创建任何窗口，也不创建菜单栏图标。
@MainActor
public final class AppEnvironment {
    public let database: AppDatabase
    public let preferences: Preferences
    public let dataDirectory: URL
    public let noteRepository: NoteRepository
    public let todoRepository: TodoRepository
    public let stickyCardRepository: StickyCardRepository
    let panelModel: PanelModel
    let backupService: BackupService
    let hotkeyService: HotkeyService

    public init(database: AppDatabase, preferences: Preferences, dataDirectory: URL) {
        self.database = database
        self.preferences = preferences
        self.dataDirectory = dataDirectory
        let noteRepository = NoteRepository(database: database)
        let todoRepository = TodoRepository(database: database)
        self.noteRepository = noteRepository
        self.todoRepository = todoRepository
        self.stickyCardRepository = StickyCardRepository(database: database)
        self.panelModel = PanelModel(noteRepository: noteRepository, todoRepository: todoRepository)
        self.backupService = BackupService(
            database: database,
            backupsDirectory: dataDirectory.appendingPathComponent("Backups", isDirectory: true),
            keepCount: { preferences.backupKeepCount }
        )
        // 只读偏好、不触碰系统热键；register(onAction:) 由 AppDelegate 在面板就绪后调用。
        self.hotkeyService = HotkeyService(preferences: preferences)
    }
}
