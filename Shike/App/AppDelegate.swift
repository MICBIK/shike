// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import KeyboardShortcuts
import ShikeData
import SwiftUI
import UserNotifications

/// 管理应用生命周期；启动流程见 architecture-diagrams.md §3。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// `-ShikeSimulateDatabaseOpenFailure` 只让第一次尝试失败（failure-modes.md「打开失败提示」）。
    private var simulatedOpenFailureUsed = false

    private(set) var environment: AppEnvironment?
    private var popoverController: PopoverController?
    private var statusItemController: StatusItemController?
    private var statusMenu: StatusMenu?
    private var settingsWindowController: SettingsWindowController?
    /// 主窗口单例（S3.5-01，03 §16.1）。
    private var mainWindowController: MainWindowController?
    private var licenseWindowController: LicenseWindowController?
    /// CGEventTap 兜底通道（ADR-021）；由 HotkeyService 的接缝弱引用，App 存续期间持有。
    private var hotkeyEventTap: HotkeyEventTap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 测试宿主下跳过全部启动步骤：不创建数据目录、不写真实偏好、不打开库（CAP-11）。
        guard ProcessInfo.processInfo.environment["SHIKE_TEST_HOST"] != "1" else { return }

        let launchOptions = LaunchOptions()

        // 数据目录：默认目录，或参数指定；无效路径不退回默认，走"打不开"提示。
        let dataDirectory: URL
        switch launchOptions.dataDirectory {
        case .default:
            dataDirectory = LaunchOptions.defaultDirectory
        case .custom(let url):
            dataDirectory = url
        case .invalid(let expandedPath):
            dataDirectory = URL(fileURLWithPath: expandedPath)
        }

        // 打开数据库；失败进入提示循环（architecture-diagrams.md §4）。
        let database: AppDatabase
        open: while true {
            do {
                database = try openDatabase(into: dataDirectory, launchOptions: launchOptions)
                break
            } catch {
                let dataError = (error as? ShikeDataError) ?? ShikeDataError.openFailed(.unknown(code: -1))
                Log.data.error("数据库打开失败：\(dataError.classification, privacy: .public)")
                alert: while true {
                    switch DatabaseOpenFailureAlert.present(error: dataError, dataDirectory: dataDirectory) {
                    case .retry:
                        continue open
                    case .openFolder:
                        DatabaseOpenFailureAlert.openInFinder(dataDirectory)
                        continue alert
                    case .quit:
                        NSApp.terminate(nil)
                        return
                    }
                }
            }
        }

        // 组装点：数据目录一并传入（app-shell.md「组件契约」）。
        environment = AppEnvironment(
            database: database,
            preferences: Preferences(defaults: .standard),
            dataDirectory: dataDirectory
        )

        // 隐藏主菜单（§3 节点 G：组装之后、创建图标之前）。
        NSApp.mainMenu = MainMenu.make()

        guard let environment else { return }

        // 默认快捷键迁移（ADR-015 补记，2026-09-29 ⌃⌥N → ⌥N）：KeyboardShortcuts 的
        // initial 只在首次启动写入 defaults；存量安装若仍存着旧默认组合则一次性改写，
        // 用户自录的其它组合（含清空）不动。
        let legacyDefault = KeyboardShortcuts.Shortcut(.n, modifiers: [.control, .option])
        if KeyboardShortcuts.getShortcut(for: .togglePanel) == legacyDefault {
            KeyboardShortcuts.setShortcut(
                KeyboardShortcuts.Shortcut(.n, modifiers: [.option]),
                for: .togglePanel
            )
        }

        // 设置窗口（单实例）与图标右键菜单。
        let settingsModel = SettingsModel(
            hotkeyService: environment.hotkeyService,
            launchAtLogin: environment.launchAtLoginService,
            preferences: environment.preferences
        )
        let settingsWindowController = SettingsWindowController(
            onViewLicense: { [weak self] in
                self?.showLicenseWindow()
            },
            model: settingsModel
        )
        self.settingsWindowController = settingsWindowController
        // 主窗口（S3.5-01）：菜单栏右键与设置-通用都能打开。
        let mainWindowController = MainWindowController()
        self.mainWindowController = mainWindowController
        settingsModel.openMainWindow = { [weak mainWindowController] in mainWindowController?.show() }
        let statusMenu = StatusMenu(actions: .init(
            openPanel: { [weak self] in
                guard let self, let button = self.statusItemController?.statusBarButton else { return }
                self.popoverController?.toggle(from: button)
            },
            openMainWindow: { [weak self] in self?.mainWindowController?.show() },
            openSettings: { [weak self] in self?.openSettings() },
            toggleLaunchAtLogin: { [weak environment] in
                guard let environment else { return }
                try? environment.launchAtLoginService.setEnabled(!environment.launchAtLoginService.isEnabled)
            },
            launchAtLoginEnabled: { [weak environment] in
                // 勾选态从系统重新读取（AC：用户在系统设置关闭后菜单立即反映）
                guard let environment else { return false }
                environment.launchAtLoginService.refresh()
                return environment.launchAtLoginService.isEnabled
            },
            hideAllCards: { [weak environment] in environment?.cardManager.hideAllCards() },
            showAllCards: { [weak environment] in environment?.cardManager.showAllCards() },
            hasCards: { [weak environment] in
                guard let environment else { return false }
                return environment.cardManager.hasCards
            },
            allCardsHidden: { [weak environment] in
                environment?.cardManager.isHiddenAll ?? false
            },
            openAbout: { [weak self] in self?.openAbout() }
        ))
        self.statusMenu = statusMenu

        // 菜单栏图标与常驻面板（§3 节点 H）。
        let popoverController = PopoverController(
            contentViewController: NSHostingController(
                rootView: PanelView(model: environment.panelModel)
            ),
            initialSize: environment.preferences.panelSize
        )
        self.popoverController = popoverController
        // S1-01：尺寸把手的持久化、Esc 的"结束编辑"经面板模型回调（无单例）。
        popoverController.persistSize = { [weak environment] size in
            guard let environment else { return }
            environment.preferences.panelSize = size
        }
        popoverController.escapeHandler = { [weak environment] in
            guard let environment else { return false }
            // Esc 顺序（03 §13）：结束编辑 → 退出搜索 → 收起面板（S2-09）。
            if environment.panelModel.endEditingIfNeeded() { return true }
            if environment.panelModel.isSearching {
                environment.panelModel.exitSearch()
                return true
            }
            return false
        }
        popoverController.searchKeyHandler = { [weak environment] in
            guard let environment else { return false }
            environment.panelModel.beginSearch()
            return true
        }
        // 收起面板时结束编辑（03 §5：收起面板自动保存）。
        // 面板内 ⌘Z（S1-07）：非编辑态撤销最近一次删除。
        popoverController.undoKeyHandler = { [weak environment] in
            environment?.panelModel.undoLastDeleteIfNeeded() ?? false
        }
        popoverController.onClose = { [weak environment] in
            environment?.typingBuffer.reset()
            _ = environment?.panelModel.endEditingIfNeeded()
            environment?.panelModel.endCaptureWindow()
        }
        environment.panelModel.resizeCurrentSize = { [weak popoverController] in
            popoverController.map {
                CGSize(width: $0.popover.contentSize.width, height: $0.popover.contentSize.height)
            } ?? CGSize(width: PanelSizing.defaultSize.width, height: PanelSizing.defaultSize.height)
        }
        environment.panelModel.resizeApply = { [weak popoverController] proposed, isFinal in
            popoverController?.applyResize(proposed, isFinal: isFinal)
        }
        // S1-03：每次呼出应用"呼出时进入"；⌘1/⌘2 切模式。
        popoverController.onShow = { [weak environment] in
            environment?.panelModel.applyOpenMode()
            environment?.panelModel.beginCaptureWindow()
        }
        popoverController.modeKeyHandler = { [weak environment] digit in
            guard let environment else { return false }
            switch digit {
            case "1": environment.panelModel.mode = .note
            case "2": environment.panelModel.mode = .todo
            default: return false
            }
            return true
        }
        let statusItemController = StatusItemController(popoverController: popoverController)
        self.statusItemController = statusItemController
        statusItemController.menuProvider = { [weak statusMenu] in statusMenu?.buildMenu() }

        // 全局快捷键（S1-02）：动作与点击图标等价——以图标按钮为锚点开关面板。
        environment.hotkeyService.register { [weak self] in
            guard let self,
                  let button = self.statusItemController?.statusBarButton else { return }
            Log.app.info("快捷键动作：toggle 面板")
            popoverController.toggle(from: button)
        }

        // ADR-021：macOS 26 起 Carbon 回调不触发，激活走 CGEventTap 兜底通道。
        let eventTap = HotkeyEventTap()
        hotkeyEventTap = eventTap
        environment.hotkeyService.activateTapChannel(
            shortcutProvider: {
                KeyboardShortcuts.getShortcut(for: .togglePanel).map {
                    (keyCode: $0.carbonKeyCode, carbonModifiers: $0.carbonModifiers)
                }
            },
            installer: { keyCode, carbonModifiers, onMatch, promptOnMissingTrust in
                eventTap.install(
                    keyCode: keyCode,
                    carbonModifiers: carbonModifiers,
                    onMatch: onMatch,
                    promptOnMissingTrust: promptOnMissingTrust
                )
            },
            remover: { eventTap.remove() }
        )

        // 呼出即打字（S1-04）：呼出空窗期（输入框未就绪且焦点不在其它键窗）的
        // 可打印按键与回车入缓冲，输入框就绪时回放（按"裸回车=提交"）；面板收起丢弃缓冲。
        environment.typingBuffer.installMonitor { [weak environment, weak popoverController] in
            guard let environment, let popoverController,
                  !environment.panelModel.isCaptureReady else { return false }
            // 搜索态：输入进搜索框，呼出即打字让位（S2-09）。
            if environment.panelModel.isSearching { return false }
            // 其它键窗（设置窗口等）拥有焦点时不截获，避免吞掉它们的键盘操作。
            if let keyWindow = NSApp.keyWindow,
               keyWindow !== popoverController.popover.contentViewController?.view.window {
                return false
            }
            return true
        }
        environment.panelModel.replayBufferedKeys = { [weak environment] textView in
            guard let environment else { return }
            (textView as? CaptureNSTextView)?.isReplayingKeys = true
            environment.typingBuffer.replayPendingEvents(in: textView)
            (textView as? CaptureNSTextView)?.isReplayingKeys = false
        }

        // 提醒通知（S2-04）：类别注册与 delegate；点本体 → 呼出面板、切待办、定位高亮。
        // delegate 在 didFinishLaunching 末段赋值：冷启动的通知动作到达时数据库已就绪。
        environment.notificationCoordinator.registerCategory(
            snoozeMinutes: {
                let stored = environment.preferences.reminderSnoozeMinutes
                return SettingsModel.snoozeOptions.contains(stored) ? stored : 10
            }()
        )
        environment.notificationCoordinator.openPanelHandler = { [weak self, weak environment] uuid in
            guard let self, let environment,
                  let button = self.statusItemController?.statusBarButton else { return }
            if !popoverController.popover.isShown {
                popoverController.toggle(from: button)
            }
            environment.panelModel.locateTodo(uuid: uuid)
        }
        UNUserNotificationCenter.current().delegate = environment.notificationCoordinator

        // 提醒调度（S2-05）：启动对账由观察流首帧触发（todosChanged 在首批数据即发射）——
        // 首帧前不拿到空快照做对账，避免清掉系统里已排的提醒（盲审 3.5-F1）；
        // 数据变化 0.5 秒合并；跨天/唤醒由调度器订阅；提醒设置变化 → 重对账 + 重注册类别。
        // 菜单栏计数（S2-08）：数据变化、跨天/唤醒、口径变化三种时机刷新。
        let updateCounter = { [weak self, weak environment] in
            guard let environment else { return }
            let mode = MenuBarCounter.resolve(environment.preferences.menuBarCounter)
            let count = MenuBarCounter.count(
                mode,
                todos: environment.panelModel.todos,
                now: Date(),
                timeZone: environment.panelModel.timeZone
            )
            self?.statusItemController?.updateCounter(count)
        }
        environment.panelModel.todosChanged = { [weak environment] in
            environment?.reminderScheduler.scheduleReconcile()
            updateCounter()
            Task { await environment?.panelModel.refreshNotificationAuthorization() }
        }
        environment.panelModel.timeContextChanged = {
            updateCounter()
        }
        environment.reminderScheduler.startObservingSystemEvents()
        settingsModel.onMenuBarCounterChanged = {
            updateCounter()
        }
        settingsModel.notificationAuthorizationReader = { [weak environment] in
            (await environment?.notificationScheduling.authorizationStatus()) ?? .notDetermined
        }
        settingsModel.openNotificationSettings = {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                NSWorkspace.shared.open(url)
            }
        }
        settingsModel.onReminderSettingsChanged = { [weak environment] in
            guard let environment else { return }
            environment.notificationCoordinator.registerCategory(
                snoozeMinutes: {
                    let stored = environment.preferences.reminderSnoozeMinutes
                    return SettingsModel.snoozeOptions.contains(stored) ? stored : 10
                }()
            )
            environment.reminderScheduler.scheduleReconcile()
        }
        environment.panelModel.start()

        // 桌面卡片的定位屏幕 = 面板所在屏（03 §10.2）；管理器的观察流已在环境组装时启动（S3-01）。
        environment.cardManager.screenProvider = { [weak self] in
            self?.statusItemController?.statusBarButton?.window?.screen
                ?? NSScreen.main
                ?? NSScreen.screens[0]
        }
        // 卡片菜单"在面板中显示"（S3-08）：开面板 + 切便签 + 定位高亮（同通知定位的组合方式）。
        environment.cardManager.showInPanelHandler = { [weak self, weak environment] uuid in
            guard let self, let environment,
                  let button = self.statusItemController?.statusBarButton else { return }
            if !popoverController.popover.isShown {
                popoverController.toggle(from: button)
            }
            environment.panelModel.locateNote(uuid: uuid)
        }

        // 每日备份（§3 节点 I/J）：后台执行一次，跨天再备份；不等待完成。
        environment.backupService.start()

        Log.app.info("启动完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 打磨 R6：退出前把在编辑的列表行立即冲进保存管线（原实现要等 0.5 秒防抖，
        // 立即退出有丢失窗口；deferred-work 2.8/阶段 1 收尾评估项）。
        _ = environment?.panelModel.endEditingIfNeeded()
        popoverController?.stop()
        environment?.panelModel.stop()
        environment?.cardManager.stop()
        environment?.backupService.stop()
        environment?.typingBuffer.stopMonitor()
        environment?.hotkeyService.stopTapChannel()
    }

    // - MARK: 设置窗口（主菜单与右键菜单共用；单实例）

    @objc func openSettingsFromMenu(_ sender: Any?) {
        openSettings()
    }

    private func openSettings() {
        settingsWindowController?.show()
    }

    private func openAbout() {
        settingsWindowController?.show(tab: .about)
    }

    /// 许可证窗口（单实例；断网可看，内容为打包的 LICENSE 全文）。
    private func showLicenseWindow() {
        if licenseWindowController == nil {
            licenseWindowController = LicenseWindowController()
        }
        licenseWindowController?.show()
    }

    private func openDatabase(into directory: URL, launchOptions: LaunchOptions) throws -> AppDatabase {
        if launchOptions.simulateDatabaseOpenFailure && !simulatedOpenFailureUsed {
            simulatedOpenFailureUsed = true
            throw ShikeDataError.openFailed(.simulated)
        }
        let options = AppDatabase.Options(simulateWriteFailure: launchOptions.simulateWriteFailure)
        return try AppDatabase.open(directory: directory, options: options)
    }
}
