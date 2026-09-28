// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import ShikeData
import SwiftUI

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
    private var licenseWindowController: LicenseWindowController?

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

        // 设置窗口（单实例）与图标右键菜单。
        let settingsWindowController = SettingsWindowController(
            onViewLicense: { [weak self] in
                self?.showLicenseWindow()
            },
            hotkeyService: environment.hotkeyService
        )
        self.settingsWindowController = settingsWindowController
        let statusMenu = StatusMenu(actions: .init(
            openSettings: { [weak self] in self?.openSettings() },
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
            environment?.panelModel.endEditingIfNeeded() ?? false
        }
        environment.panelModel.resizeCurrentSize = { [weak popoverController] in
            popoverController.map {
                CGSize(width: $0.popover.contentSize.width, height: $0.popover.contentSize.height)
            } ?? CGSize(width: PanelSizing.defaultSize.width, height: PanelSizing.defaultSize.height)
        }
        environment.panelModel.resizeApply = { [weak popoverController] proposed, isFinal in
            popoverController?.applyResize(proposed, isFinal: isFinal)
        }
        let statusItemController = StatusItemController(popoverController: popoverController)
        self.statusItemController = statusItemController
        statusItemController.menuProvider = { [weak statusMenu] in statusMenu?.buildMenu() }

        // 全局快捷键（S1-02）：动作与点击图标等价——以图标按钮为锚点开关面板。
        environment.hotkeyService.register { [weak self] in
            guard let self,
                  let button = self.statusItemController?.statusBarButton else { return }
            popoverController.toggle(from: button)
        }
        environment.panelModel.start()

        // 每日备份（§3 节点 I/J）：后台执行一次，跨天再备份；不等待完成。
        environment.backupService.start()

        Log.app.info("启动完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        popoverController?.stop()
        environment?.panelModel.stop()
        environment?.backupService.stop()
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
