// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo 的 NewReminderTypingCoordinator.swift 与 ContentView.swift 的按键监听部分
// 移植；去单例与 EventKit 条件，缓冲上限 200（丢弃最早）；判断提为纯函数 isTypingEvent
// （回车 "\r" 显式入缓冲——AC 要求回放执行提交）；截获条件经注入的 shouldInterceptKeys
// 判定"呼出空窗"（输入框未就绪且焦点不在其它键窗），回放按"裸回车=提交"语义（2026-09-28）。

import AppKit

/// 呼出即打字（S1-04，03 §4）：呼出到输入框就绪之间的可打印按键缓存与回放，一个不丢。
/// 面板显示后到达的按键属于输入框的正常输入，不经过本缓冲；面板收起即丢弃。
@MainActor
final class TypingBuffer {
    /// 缓冲上限：超出丢弃最早的（03 §4 规格之外的防御，防极端粘贴类输入撑爆内存）。
    static let maximumPendingEvents = 200

    private(set) var pendingEvents: [NSEvent] = []

    /// 面板未显示期间的本地按键监听安装标志。
    private var keyMonitor: Any?

    // - MARK: 判断（纯函数，L1 覆盖）

    /// 是否为"应缓冲"的按键：不带 ⌘/⌃ 修饰的可打印字符，或裸回车（"\r"——
    /// AC 明确要求回车被缓存且回放执行提交；⌘↩/⌃↩ 是命令不缓冲）。
    /// 注意：回放统一按"裸回车=提交"处理（见 CaptureNSTextView.isReplayingKeys），
    /// 空窗期 ⇧↩ 的换行语义在回放中退化为提交（极端场景，接受）。
    nonisolated static func isTypingEvent(
        modifiers: NSEvent.ModifierFlags,
        characters: String?
    ) -> Bool {
        let nonTypingModifiers: NSEvent.ModifierFlags = [.command, .control]
        guard modifiers.intersection(.deviceIndependentFlagsMask).isDisjoint(with: nonTypingModifiers),
              let characters,
              !characters.isEmpty else {
            return false
        }
        if characters == "\r" { return true }
        return characters.unicodeScalars.allSatisfy {
            !Self.nonPrintableCategories.contains($0.properties.generalCategory)
        }
    }

    /// 缓冲推入后的结果（纯函数，L1 覆盖上限语义）。
    static func appended(_ buffer: [NSEvent], with event: NSEvent, limit: Int = maximumPendingEvents) -> [NSEvent] {
        var buffer = buffer
        buffer.append(event)
        if buffer.count > limit {
            buffer.removeFirst(buffer.count - limit)
        }
        return buffer
    }

    /// Set 与 GeneralCategory 均为 Sendable，可 nonisolated 共享（供 nonisolated 纯函数读取）。
    nonisolated private static let nonPrintableCategories: Set<Unicode.GeneralCategory> = [
        .control, .format, .surrogate, .privateUse, .unassigned,
    ]

    // - MARK: 缓冲与回放

    func enqueue(_ event: NSEvent) {
        pendingEvents = Self.appended(pendingEvents, with: event)
    }

    /// 把缓冲按键按序回放进刚获得焦点的文本视图，然后清空。
    func replayPendingEvents(in textView: NSTextView) {
        guard !pendingEvents.isEmpty else { return }
        let events = pendingEvents
        pendingEvents.removeAll()
        events.forEach { textView.keyDown(with: $0) }
    }

    func reset() {
        pendingEvents.removeAll()
    }

    // - MARK: 监听安装（由 AppDelegate 在面板就绪前调用）

    /// 安装本地按键监听。`shouldInterceptKeys` 返回是否处于"呼出空窗"（输入框未就绪、
    /// 且键盘焦点不在应用内其它窗口——避免吞掉设置窗口等场景的按键）。
    /// 空窗期的可打印按键与回车截获入缓冲，其余放行。
    func installMonitor(shouldInterceptKeys: @escaping () -> Bool) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, shouldInterceptKeys(),
                  Self.isTypingEvent(modifiers: event.modifierFlags, characters: event.characters) else {
                return event
            }
            // assumeIsolated 闭包是 @Sendable，只返回布尔；事件在监听闭包（非 @Sendable）中处理。
            let buffered = MainActor.assumeIsolated { () -> Bool in
                self.enqueue(event)
                return true
            }
            return buffered ? nil : event
        }
    }

    func stopMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
