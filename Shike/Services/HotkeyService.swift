// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo 的 KeyboardShortcutService.swift 移植；去掉单例，偏好与启用开关经
// 注入的 Preferences 与闭包完成（L2 可用替身，不真实注册系统热键）；快捷键名换成
// togglePanel，默认 ⌃⌥N 且默认开启（ADR-015、03 §13）（2026-09-28）。
// 追加：macOS 26 起 Carbon 回调不触发，激活改经 CGEventTap 兜底通道（ADR-021），
// 两条通道共用 dispatchHotkeyAction 去重入口（2026-09-28）。

import AppKit
import KeyboardShortcuts
import Observation

/// 全局快捷键名（S1-02）：呼出 / 收起面板，默认 ⌃⌥N（03 §13；阶段 1 实测无冲突后定稿）。
extension KeyboardShortcuts.Name {
    static let togglePanel = Self(
        "togglePanel",
        initial: .init(.n, modifiers: [.control, .option])
    )
}

/// 全局快捷键服务（ADR-015）：录制与存储经 KeyboardShortcuts（Recorder/defaults）；
/// 激活走 CGEventTap 兜底通道（ADR-021，macOS 26 起 Carbon 回调不触发）。
/// 默认开启；关闭状态持久化在 `hotkey.togglePanel.enabled`。
/// 测试经 `enable:`/`disable:` 注入替身，且默认不接入 tap 通道，对系统无副作用。
@Observable
@MainActor
final class HotkeyService {
    private(set) var isEnabled: Bool
    private let preferences: Preferences
    private let enableAction: () -> Void
    private let disableAction: () -> Void
    private var onKeyDown: (() -> Void)?
    private var registered = false

    // - MARK: CGEventTap 兜底通道（ADR-021）

    /// tap 通道接缝：默认全为惰性空实现（L2 不触碰系统），App 启动时经 activateTapChannel 接入。
    @ObservationIgnored private var tapInstaller: (_ keyCode: Int, _ carbonModifiers: Int, _ onMatch: @escaping () -> Void) -> Bool = { _, _, _ in false }
    @ObservationIgnored private var tapRemover: () -> Void = {}
    @ObservationIgnored private var shortcutProvider: () -> (keyCode: Int, carbonModifiers: Int)? = { nil }
    @ObservationIgnored private(set) var isTapChannelActive = false
    /// 辅助功能未授权导致 tap 安装失败（设置页据此提示）。
    private(set) var tapAuthorizationDenied = false
    @ObservationIgnored private var lastFireAt = Date.distantPast

    init(
        preferences: Preferences,
        enable: @escaping () -> Void = { KeyboardShortcuts.enable(.togglePanel) },
        disable: @escaping () -> Void = { KeyboardShortcuts.disable(.togglePanel) }
    ) {
        self.preferences = preferences
        self.enableAction = enable
        self.disableAction = disable
        // 只读偏好，不触碰 KeyboardShortcuts——AppEnvironment 组装（含 L2）保持惰性。
        self.isEnabled = preferences.hotkeyTogglePanelEnabled
    }

    /// 注册快捷键动作并应用启用状态；App 启动时调用一次。
    func register(onAction: @escaping () -> Void) {
        onKeyDown = onAction
        guard !registered else {
            applyEnabled()
            return
        }
        registered = true
        // Carbon 热键回调在主线程派发；assumeIsolated 切回主 actor。
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            MainActor.assumeIsolated {
                self?.dispatchHotkeyAction()
            }
        }
        applyEnabled()
    }

    /// 接入真实 CGEventTap 通道（ADR-021）。仅 App 调用一次；接入后立即按当前状态安装。
    func activateTapChannel(
        shortcutProvider: @escaping () -> (keyCode: Int, carbonModifiers: Int)?,
        installer: @escaping (_ keyCode: Int, _ carbonModifiers: Int, _ onMatch: @escaping () -> Void) -> Bool,
        remover: @escaping () -> Void
    ) {
        self.shortcutProvider = shortcutProvider
        self.tapInstaller = installer
        self.tapRemover = remover
        isTapChannelActive = true
        refreshTap()
    }

    /// 以当前存储的组合键重装 tap：启动、辅助功能授权后、录制新组合（Recorder onChange）时调用。
    func refreshTap() {
        guard isTapChannelActive, isEnabled else { return }
        guard let shortcut = shortcutProvider() else {
            // 用户清空了快捷键：撤下 tap（无键可生效），授权标记一并清除。
            tapRemover()
            tapAuthorizationDenied = false
            return
        }
        let installed = tapInstaller(shortcut.keyCode, shortcut.carbonModifiers) { [weak self] in
            self?.dispatchHotkeyAction()
        }
        tapAuthorizationDenied = !installed
    }

    /// App 退出：卸载 tap（KeyboardShortcuts 的 Carbon 注册随进程终止释放）。
    func stopTapChannel() {
        tapRemover()
        isTapChannelActive = false
    }

    /// 设置-快捷键分页的启用开关（03 §9）。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        preferences.hotkeyTogglePanelEnabled = enabled
        applyEnabled()
    }

    /// Carbon onKeyDown 与 CGEventTap 的共同入口：150ms 内的重复触发折叠为一次——
    /// 未来若 Carbon 回调恢复，两条通道对同一次按键只执行一次动作（ADR-021）。
    func dispatchHotkeyAction() {
        guard acceptFire(now: Date()) else { return }
        onKeyDown?()
    }

    /// 触发去重；独立出来便于用合成时间测试（不真等 150ms）。
    func acceptFire(now: Date) -> Bool {
        guard now.timeIntervalSince(lastFireAt) > Self.fireDebounceInterval else { return false }
        lastFireAt = now
        return true
    }

    static let fireDebounceInterval: TimeInterval = 0.15

    private func applyEnabled() {
        if isEnabled {
            enableAction()
            refreshTap()
        } else {
            disableAction()
            tapRemover()
            tapAuthorizationDenied = false
        }
    }
}
