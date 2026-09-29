// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import os

/// CGEventTap 全局快捷键激活（ADR-021）。
/// macOS 26 起 Carbon `RegisterEventHotKey` 的回调不再触发（本机实测，社区亦有记录，
/// 如 voiceTyper 迁移记录），KeyboardShortcuts 3.1.0 尚未修复；录制与存储仍交给
/// KeyboardShortcuts（Recorder/defaults），激活改由本类以 CGEventTap 兜底：
/// 命中组合即消费按键并回调动作。`cghidEventTap` 的 `defaultTap` 需要"辅助功能"权限，
/// 未授权时 install 返回 false 并可触发系统授权提示。
/// 生命周期与 App 相同；App 退出时经 HotkeyService 调 remove()。
@MainActor
final class HotkeyEventTap {
    private var machPort: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyCode: Int64 = 0
    private var wantedFlags: CGEventFlags = []
    private var onMatch: () -> Void = {}

    var isInstalled: Bool { machPort != nil }

    /// 安装 tap（已安装则先卸载）。返回是否成功。
    /// 未授权"辅助功能"时弹出系统提示并返回 false，待授权后经 refreshTap 重试。
    @discardableResult
    func install(keyCode: Int, carbonModifiers: Int, onMatch: @escaping () -> Void) -> Bool {
        remove()
        let trusted = AXIsProcessTrustedWithOptions([
            "AXTrustedCheckOptionPrompt" as String: true, // kAXTrustedCheckOptionPrompt 的常量值（全局 var 过不了严格并发检查）
        ] as CFDictionary)
        Log.app.info("快捷键 tap：辅助功能授权=\(trusted, privacy: .public)")
        guard trusted else { return false }
        return installAfterAuthorization(keyCode: keyCode, carbonModifiers: carbonModifiers, onMatch: onMatch)
    }

    /// 卸载 tap；未安装时为空操作。
    func remove() {
        if let machPort {
            CGEvent.tapEnable(tap: machPort, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let machPort {
            CFMachPortInvalidate(machPort)
        }
        self.machPort = nil
        self.runLoopSource = nil
    }

    private func installAfterAuthorization(keyCode: Int, carbonModifiers: Int, onMatch: @escaping () -> Void) -> Bool {
        self.onMatch = onMatch
        self.keyCode = Int64(keyCode)
        // 只比较四个修饰键位：系统会在事件上附加 SecondaryFn（实测 0x2000_0000）等额外位，
        // 且 CapsLock/NonCoalesced 与组合无关，一并不参与比较。
        wantedFlags = Self.cgFlags(fromCarbon: carbonModifiers)

        let mask: CGEventMask = 1 << CGEventType.keyDown.rawValue
        guard let machPort = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Log.app.error("快捷键 tap：tapCreate 失败（已授权但仍失败）")
            return false
        }
        Log.app.info("快捷键 tap：已安装（CGEventTap）")
        let runLoopSource = CFMachPortCreateRunLoopSource(nil, machPort, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: machPort, enable: true)
        self.machPort = machPort
        self.runLoopSource = runLoopSource
        return true
    }

    /// 命中判定。返回 true 表示按键已消费（不下传给前台应用，与 Carbon 热键行为一致）。
    /// 仅在主线程运行（source 挂在主 RunLoop）；键码与标志位以 Sendable 值传入，
    /// 避免把非 Sendable 的 CGEvent 跨过隔离边界。
    fileprivate func handle(keyCode: Int64, flagsRaw: UInt64) -> Bool {
        guard keyCode == self.keyCode else { return false }
        let flags = CGEventFlags(rawValue: flagsRaw).intersection([
            .maskControl, .maskAlternate, .maskCommand, .maskShift,
        ])
        guard flags == wantedFlags else { return false }
        onMatch()
        return true
    }

    /// Carbon 修饰键位 → CGEventFlags（只含四个组合键修饰）。
    static func cgFlags(fromCarbon carbon: Int) -> CGEventFlags {
        var flags: CGEventFlags = []
        if carbon & controlKey != 0 { flags.insert(.maskControl) }
        if carbon & optionKey != 0 { flags.insert(.maskAlternate) }
        if carbon & shiftKey != 0 { flags.insert(.maskShift) }
        if carbon & cmdKey != 0 { flags.insert(.maskCommand) }
        return flags
    }

    private static let callback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else { return nil }
        let holder = Unmanaged<HotkeyEventTap>.fromOpaque(refcon).takeUnretainedValue()
        switch type {
        case .tapDisabledByTimeout:
            // 系统在回调超时后禁用 tap：重新启用，避免快捷键永久失灵。
            if let machPort = holder.machPort {
                CGEvent.tapEnable(tap: machPort, enable: true)
            }
            return nil
        case .keyDown:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            let flagsRaw = event.flags.rawValue
            let consumed = MainActor.assumeIsolated {
                holder.handle(keyCode: keyCode, flagsRaw: flagsRaw)
            }
            return consumed ? nil : Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
