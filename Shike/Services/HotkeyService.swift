// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo 的 KeyboardShortcutService.swift 移植；去掉单例，偏好与启用开关经
// 注入的 Preferences 与闭包完成（L2 可用替身，不真实注册系统热键）；快捷键名换成
// togglePanel，默认 ⌃⌥N 且默认开启（ADR-015、03 §13）（2026-09-28）。

import AppKit
import KeyboardShortcuts

/// 全局快捷键名（S1-02）：呼出 / 收起面板，默认 ⌃⌥N（03 §13；阶段 1 实测无冲突后定稿）。
extension KeyboardShortcuts.Name {
    static let togglePanel = Self(
        "togglePanel",
        initial: .init(.n, modifiers: [.control, .option])
    )
}

/// 全局快捷键服务（ADR-015）：包装 KeyboardShortcuts 的注册与启用开关。
/// 默认开启；关闭状态持久化在 `hotkey.togglePanel.enabled`。
/// 测试经 `enable:`/`disable:` 注入替身，不触碰真实系统热键。
@MainActor
final class HotkeyService {
    private(set) var isEnabled: Bool
    private let preferences: Preferences
    private let enableAction: () -> Void
    private let disableAction: () -> Void
    private var onKeyDown: (() -> Void)?
    private var registered = false

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
                self?.fireAction()
            }
        }
        applyEnabled()
    }

    /// 设置-快捷键分页的启用开关（03 §9）。
    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        preferences.hotkeyTogglePanelEnabled = enabled
        applyEnabled()
    }

    private func applyEnabled() {
        if isEnabled {
            enableAction()
        } else {
            disableAction()
        }
    }

    private func fireAction() {
        onKeyDown?()
    }
}
