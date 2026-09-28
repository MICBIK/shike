// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo AppDelegate 的面板相关部分（togglePopover、外部点击监听、didClose/didShow 兜底）
// 与 MainPopoverSizing.swift 拆成独立控制器；去掉 EventKit 授权与单例；尺寸改为 03 §3 的
// 360×520（最小 300×360、最大 600×1000）；activate(ignoringOtherApps:) 改为 activate()（2026-09-27）。
// S1-01：初始尺寸读自 panel.size；新增 applyResize（把手钳制与持久化）、Esc 本地监听
// （结束编辑 → 收起面板）与 escapeOutcome/persistSize/escapeHandler 回调（2026-09-28）。

import AppKit
import Combine
import SwiftUI

/// 面板尺寸常量（03 §3）；调整把手由 S1-01 使用。
enum PanelSizing {
    static let defaultSize = NSSize(width: 360, height: 520)
    static let minSize = NSSize(width: 300, height: 360)
    static let maxSize = NSSize(width: 600, height: 1_000)
    static let minWidthPadding: CGFloat = 80
    static let minHeightPadding: CGFloat = 120
}

/// 承载常驻面板内容的弹出面板：左键开关、外部点击兜底、防"刚关上又弹开"。
@MainActor
final class PopoverController {
    let popover = NSPopover()

    /// 菜单栏按钮；由 StatusItemController 在 toggle 时传入，用于判断点击是否落在图标上。
    private weak var statusBarButton: NSStatusBarButton?

    private var didCloseCancellationToken: AnyCancellable?
    private var didShowCancellationToken: AnyCancellable?
    /// 最近一次面板收起的时间；10 毫秒内的点击不再重新打开（移植自 demo 的 didCloseEventDate）。
    private var didCloseEventDate = Date.distantPast
    private var globalOutsideClickMonitor: Any?
    private var localOutsideClickMonitor: Any?
    private var localEscapeMonitor: Any?

    /// Esc 的第一级"结束编辑"（S1-01：结束编辑 → 收起面板）。
    /// 由 App 接到 PanelModel 的编辑状态；返回 true 表示编辑已被结束（本次 Esc 只做这一级）。
    /// 阶段 1 的 2.6/2.7 接入真实编辑状态；列表编辑未实现时保持默认 false。
    var escapeHandler: () -> Bool = { false }
    /// 尺寸持久化（S1-01）：applyResize 钳制后且 isFinal 时调用；由 App 接到 Preferences.panelSize。
    var persistSize: (CGSize) -> Void = { _ in }
    /// 面板弹出（S1-03）：每次呼出应用"呼出时进入"设置；由 App 接到 PanelModel.applyOpenMode。
    var onShow: () -> Void = {}
    /// 面板收起（S1-04）：呼出即打字的缓冲在此丢弃；由 App 接到 TypingBuffer.reset。
    var onClose: () -> Void = {}
    /// ⌘1/⌘2 切模式（S1-03）：参数为数字字符（"1"/"2"）；返回 true 表示已消费。
    var modeKeyHandler: (String) -> Bool = { _ in false }
    /// 面板内 ⌘Z 撤销最近一次删除（S1-07，非编辑态）；返回 true 表示已消费。
    var undoKeyHandler: () -> Bool = { false }

    init(contentViewController: NSViewController, initialSize: CGSize = PanelSizing.defaultSize) {
        popover.animates = false
        popover.behavior = .transient
        popover.contentSize = Self.clampedSize(
            NSSize(width: initialSize.width, height: initialSize.height),
            visibleFrame: Self.visibleFrame(for: nil)
        )
        popover.contentViewController = contentViewController // 启动时创建一次，之后常驻

        configureDidCloseNotification()
        configureDidShowNotification()
    }

    /// 与 App 同生命周期（AppDelegate 持有）；监听在 applicationWillTerminate 经 stop() 停止，
    /// 不在 deinit 里做主线程清理（Swift 6 严格并发下 deinit 非主线程隔离）。
    func stop() {
        didCloseCancellationToken?.cancel()
        didShowCancellationToken?.cancel()
        stopOutsideClickMonitors()
        stopEscapeMonitor()
    }

    func toggle(from button: NSStatusBarButton) {
        statusBarButton = button
        let intervalSinceClose = Date().timeIntervalSince(didCloseEventDate)
        if Self.shouldDebounceClose(isShown: popover.isShown, intervalSinceClose: intervalSinceClose) {
            didCloseEventDate = .distantPast
            popover.performClose(button)
        } else {
            popover.contentSize = Self.clampedSize(popover.contentSize, visibleFrame: Self.visibleFrame(for: button))
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate()
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// 纯函数：toggle 是否应走"关闭/不打开"分支（移植自 demo 的防"刚关又开"：
    /// 已显示时关闭；刚收起 10 毫秒内不重新打开）。
    nonisolated static func shouldDebounceClose(
        isShown: Bool,
        intervalSinceClose: TimeInterval,
        window: TimeInterval = 0.01
    ) -> Bool {
        isShown || intervalSinceClose < window
    }

    // - MARK: 尺寸（03 §3：默认 360×520；最小 300×360；最大 600×1000，且不超出所在屏幕的可见区域）

    static func visibleFrame(for button: NSStatusBarButton?) -> NSRect {
        if let screen = button?.window?.screen {
            return screen.visibleFrame
        }
        return NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_440, height: 900)
    }

    /// 纯函数：按可见区域与上下限钳制尺寸（L2 直接验证）。
    nonisolated static func clampedSize(_ size: NSSize, visibleFrame: NSRect) -> NSSize {
        let maxWidth = (visibleFrame.width - PanelSizing.minWidthPadding)
            .constrainedTo(min: PanelSizing.minSize.width, max: PanelSizing.maxSize.width)
        let width = size.width.constrainedTo(min: PanelSizing.minSize.width, max: maxWidth)

        let maxHeight = (visibleFrame.height - PanelSizing.minHeightPadding)
            .constrainedTo(min: PanelSizing.minSize.height, max: PanelSizing.maxSize.height)
        let height = size.height.constrainedTo(min: PanelSizing.minSize.height, max: maxHeight)

        return NSSize(width: width, height: height)
    }

    // - MARK: 尺寸把手（S1-01）与 Esc（03 §3、§13）

    /// 把手回调：实时钳制并应用；isFinal 时持久化。
    func applyResize(_ proposed: CGSize, isFinal: Bool) {
        let clamped = Self.clampedSize(
            NSSize(width: proposed.width, height: proposed.height),
            visibleFrame: Self.visibleFrame(for: statusBarButton)
        )
        popover.contentSize = clamped
        if isFinal {
            persistSize(CGSize(width: clamped.width, height: clamped.height))
        }
    }

    /// Esc 的处理结果（纯函数，03 §13 的顺序在阶段 1 只有两级）。
    enum EscapeOutcome {
        /// 第一级：编辑已被结束，本次 Esc 到此为止。
        case consumedByEditing
        /// 收起面板。
        case closesPanel
    }

    nonisolated static func escapeOutcome(editingHandled: Bool) -> EscapeOutcome {
        editingHandled ? .consumedByEditing : .closesPanel
    }

    private func startEscapeMonitor() {
        stopEscapeMonitor()
        localEscapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // 面板内按键（03 §13）：裸 Esc 与 ⌘1/⌘2 在此消费，其余放行。
            // assumeIsolated 的闭包是 @Sendable，只返回布尔，事件本身在监听闭包（非 @Sendable）中处理。
            let swallow = MainActor.assumeIsolated { () -> Bool in
                guard let self else { return false }
                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == 53, modifiers.isEmpty {
                    // 输入法组合态（候选窗/下划线）：Esc 交还输入法，不结束编辑也不收起面板（03 §4/S1-05）。
                    if let textView = NSApp.keyWindow?.firstResponder as? NSTextView,
                       textView.hasMarkedText() {
                        return false
                    }
                    switch Self.escapeOutcome(editingHandled: self.escapeHandler()) {
                    case .consumedByEditing:
                        return true
                    case .closesPanel:
                        self.popover.performClose(nil)
                        return true
                    }
                }
                if modifiers.subtracting([.numericPad, .function, .capsLock]) == .command {
                    // ⌘Z：非编辑态撤销最近一次删除；编辑态返回 false 交回文字撤销（03 §7）。
                    if event.charactersIgnoringModifiers == "z" {
                        return self.undoKeyHandler()
                    }
                    if let digit = event.charactersIgnoringModifiers,
                       digit == "1" || digit == "2" {
                        return self.modeKeyHandler(digit)
                    }
                }
                return false
            }
            return swallow ? nil : event
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = localEscapeMonitor {
            NSEvent.removeMonitor(monitor)
            localEscapeMonitor = nil
        }
    }

    // - MARK: 面板收起/弹出的兜底（移植自 demo）

    private func configureDidCloseNotification() {
        // NOTE（移植注释）：点击菜单栏按钮的上半部分关闭面板时，会先收到 didClose 再触发 toggle，
        // 导致"刚关上又弹开"；记录收起时间，10 毫秒内的 toggle 视为刚关闭。
        didCloseCancellationToken = NotificationCenter.default
            .publisher(for: NSPopover.didCloseNotification, object: popover)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.didCloseEventDate = Date()
                    self?.stopOutsideClickMonitors()
                    self?.stopEscapeMonitor()
                    self?.onClose()
                }
            }
    }

    private func configureDidShowNotification() {
        // NOTE（移植注释）：SwiftUI 控件在 NSPopover 里偶尔会打断系统 transient 收起行为；
        // 面板显示期间安装外部点击兜底监听，收起时移除。
        didShowCancellationToken = NotificationCenter.default
            .publisher(for: NSPopover.didShowNotification, object: popover)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.startOutsideClickMonitors()
                    self?.startEscapeMonitor()
                    self?.onShow()
                }
            }
    }

    private func startOutsideClickMonitors() {
        stopOutsideClickMonitors()

        globalOutsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            MainActor.assumeIsolated {
                if self?.isClickOutsidePopover(event: event) ?? false {
                    self?.popover.performClose(nil)
                }
            }
        }

        localOutsideClickMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            // 返回 nil 吞掉事件，贴合系统 transient 面板的收起行为（移植注释）。
            let shouldClose = MainActor.assumeIsolated {
                self?.isClickOutsidePopover(event: event) ?? false
            }
            if shouldClose {
                self?.popover.performClose(nil)
            }
            return shouldClose ? nil : event
        }
    }

    private func stopOutsideClickMonitors() {
        if let monitor = globalOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalOutsideClickMonitor = nil
        }
        if let monitor = localOutsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            localOutsideClickMonitor = nil
        }
    }

    private func isClickOutsidePopover(event: NSEvent) -> Bool {
        guard popover.isShown else { return false }

        let mouseLocation = NSEvent.mouseLocation

        // 点在菜单栏图标上：交给 toggle 处理，不算外部点击
        if isMouseInsideStatusBarButton(mouseLocation) {
            return false
        }

        if let popoverWindow = popover.contentViewController?.view.window,
           popoverWindow.frame.contains(mouseLocation) {
            return false
        }

        if let window = NSApp.window(withWindowNumber: event.windowNumber),
           window.frame.contains(mouseLocation) {
            return false
        }

        return true
    }

    private func isMouseInsideStatusBarButton(_ mouseLocation: NSPoint) -> Bool {
        guard let button = statusBarButton,
              let window = button.window else {
            return false
        }

        let rectInWindow = button.convert(button.bounds, to: nil)
        let rectOnScreen = window.convertToScreen(rectInWindow)
        return rectOnScreen.contains(mouseLocation)
    }
}

private extension Comparable {
    /// 移植自 demo 的 Comparable+Extensions.swift。
    func constrainedTo(min lower: Self, max upper: Self) -> Self {
        min(max(self, lower), upper)
    }
}
