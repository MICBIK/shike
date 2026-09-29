// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
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
    let typingBuffer = TypingBuffer()
    let launchAtLoginService = LaunchAtLoginService()
    /// 通知接缝与动作协调（S2-04）：L2 可注入内存替身保持零系统调用。
    let notificationScheduling: NotificationScheduling
    let notificationCoordinator: NotificationCoordinator
    let reminderScheduler: ReminderScheduler
    /// 桌面卡片管理器（S3-01）：start(actions:) 由 AppDelegate 在状态项就绪后调用。
    let cardManager: CardManager

    init(
        database: AppDatabase,
        preferences: Preferences,
        dataDirectory: URL,
        notificationScheduling: NotificationScheduling = SystemNotificationScheduling()
    ) {
        self.database = database
        self.preferences = preferences
        self.dataDirectory = dataDirectory
        self.notificationScheduling = notificationScheduling
        let noteRepository = NoteRepository(database: database)
        let todoRepository = TodoRepository(database: database)
        self.noteRepository = noteRepository
        self.todoRepository = todoRepository
        self.stickyCardRepository = StickyCardRepository(database: database)
        self.panelModel = PanelModel(noteRepository: noteRepository, todoRepository: todoRepository, preferences: preferences)
        self.backupService = BackupService(
            database: database,
            backupsDirectory: dataDirectory.appendingPathComponent("Backups", isDirectory: true),
            keepCount: { preferences.backupKeepCount }
        )
        // 只读偏好、不触碰系统热键；register(onAction:) 由 AppDelegate 在面板就绪后调用。
        self.hotkeyService = HotkeyService(preferences: preferences)
        // 提交带时间待办时请求通知权限（S2-10；系统对重复调用幂等），请求后刷新状态。
        panelModel.notificationPermissionRequester = { [weak panelModel, notificationScheduling] in
            Task {
                _ = await notificationScheduling.requestAuthorization()
                await panelModel?.refreshNotificationAuthorization()
            }
        }
        // 授权状态判定与系统设置跳转（S2-10）。
        panelModel.notificationDeniedChecker = { [notificationScheduling] in
            await notificationScheduling.authorizationStatus() == .denied
        }
        panelModel.openNotificationSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
        // 通知动作协调（S2-04）。
        let notificationCoordinator = NotificationCoordinator(
            scheduling: notificationScheduling,
            handlers: .init()
        )
        self.notificationCoordinator = notificationCoordinator
        // 提醒调度（S2-05）：待办数据变化的合并对账在 AppDelegate 接线（todoChanged 钩子）。
        let reminderScheduler = ReminderScheduler(
            scheduling: notificationScheduling,
            todosProvider: { [weak panelModel] in panelModel?.todos ?? [] },
            preferences: preferences,
            timeZoneProvider: { [weak panelModel] in panelModel?.timeZone ?? .current }
        )
        self.reminderScheduler = reminderScheduler
        // 桌面卡片（S3-01，03 §10）：管理器先创建并落属性（后面闭包捕获 self 需全部属性就绪），
        // 面板动作注入与观察流启动在本 init 末尾。
        let cardManager = CardManager(cardRepository: stickyCardRepository)
        self.cardManager = cardManager
        // 通知动作（S2-04）：全部存储属性已就绪，接回调（闭包访问 self.panelModel）。
        // snoozeMinutes 动作发生时读偏好；面板的打开与定位由 AppDelegate 接线。
        notificationCoordinator.handlers.complete = { [weak self] uuid in
            Task { await self?.panelModel.completeTodo(uuid: uuid) }
        }
        notificationCoordinator.handlers.snooze = { [weak self] uuid, date in
            Task { await self?.panelModel.snoozeTodo(uuid: uuid, until: date) }
        }
        notificationCoordinator.handlers.snoozeMinutes = {
            let stored = preferences.reminderSnoozeMinutes
            return SettingsModel.snoozeOptions.contains(stored) ? stored : 10
        }
        // 定位与钳制是 App 层几何（CardGeometry），写库失败走面板同一提示条（NFR19）。
        panelModel.pinNoteToDesktop = { [weak self, weak cardManager] noteID in
            guard let self, let cardManager else { return }
            let frame = CardGeometry.initialFrame(
                existingFrames: cardManager.existingFrames(),
                screenVisibleFrame: cardManager.screenProvider().visibleFrame,
                size: CardGeometry.defaultSize
            )
            do {
                _ = try await stickyCardRepository.pin(
                    noteID,
                    frame: frame,
                    options: preferences.cardDefaultOptions
                )
            } catch {
                panelModel.reportCardWriteFailure(error, retry: { [weak self] in
                    Task { await self?.pinCard(noteID) }
                })
            }
        }
        panelModel.unpinNoteFromDesktop = { [weak self] noteID in
            await self?.unpinCard(noteID)
        }
        cardManager.start(actions: CardManager.Actions(
            screenProvider: { [weak cardManager] in
                // 卡片是窗口功能，必有屏幕会话；cardManager 与环境同生命周期。
                cardManager?.screenProvider() ?? NSScreen.main ?? NSScreen.screens[0]
            },
            moveCard: { [weak self] noteID, frame in
                Task { await self?.moveCard(noteID, frame) }
            },
            unpin: { [weak self] noteID in
                Task { await self?.unpinCard(noteID) }
            },
            updateOptions: { [weak self] noteID, options in
                Task { await self?.updateCardOptions(noteID, options) }
            },
            updateNoteContent: { [weak self] noteID, text in
                // 面板同语义（清空=删除入撤销栈、未变跳过、失败提示条）
                Task { await self?.panelModel.saveNoteContent(noteID, text) }
            },
            showInPanel: { [weak cardManager] uuid in
                cardManager?.showInPanelHandler(uuid)
            }
        ))
    }

    // MARK: 卡片写路径（S3-01）：失败上报与重试复用面板提示条（NFR19）

    func pinCard(_ noteID: Note.ID) async {
        await panelModel.pinNoteToDesktop(noteID)
    }

    private func unpinCard(_ noteID: Note.ID) async {
        do {
            try await stickyCardRepository.unpin(noteID)
        } catch {
            panelModel.reportCardWriteFailure(error, retry: { [weak self] in
                Task { await self?.unpinCard(noteID) }
            })
        }
    }

    private func moveCard(_ noteID: Note.ID, _ frame: CardFrame) async {
        do {
            try await stickyCardRepository.updateFrame(noteID, frame: frame)
        } catch {
            panelModel.reportCardWriteFailure(error, retry: { [weak self] in
                Task { await self?.moveCard(noteID, frame) }
            })
        }
    }

    private func updateCardOptions(_ noteID: Note.ID, _ options: StickyCardOptions) async {
        do {
            try await stickyCardRepository.updateOptions(noteID, options: options)
        } catch {
            panelModel.reportCardWriteFailure(error, retry: { [weak self] in
                Task { await self?.updateCardOptions(noteID, options) }
            })
        }
    }
}
