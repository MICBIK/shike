// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Combine
import os
import ShikeData
import SwiftUI

/// 卡片管理器（S3-01，03 §10；NFR24）：
/// 消费 `StickyCardRepository.observeVisible()`（便签软删除的卡片自动从流中消失，恢复即回来），
/// 经 CardDiff 对账出 create/update/close 三种操作，驱动每张卡片的 StickyCardPanel。
/// 监听器、控制器按"存在几张建几张"惰性管理；启动调用 start() 即完成 04 §6.1 的"恢复卡片"。
@MainActor
final class CardManager {
    /// 卡片写路径的出口：由 AppEnvironment 接仓储（含失败上报与重试）。
    struct Actions {
        /// 钉出时计算新卡初始 frame 的屏幕（面板所在屏）。
        var screenProvider: () -> NSScreen
        /// 拖动结束：持久化新位置。
        var moveCard: (Note.ID, CardFrame) -> Void
        /// 取消钉住（✕）。
        var unpin: (Note.ID) -> Void
        /// 层级按钮循环（携带完整当前选项，写回时只换层级）。
        var cycleLevel: (Note.ID, StickyCardOptions) -> Void
        /// 卡片菜单改动选项（自动隐藏开关/延迟/不透明度，S3-03）。
        var updateOptions: (Note.ID, StickyCardOptions) -> Void
    }

    /// 钉出定位与拖动钳制用的屏幕（面板所在屏；AppDelegate 在状态项就绪后设置）。
    nonisolated(unsafe) var screenProvider: () -> NSScreen = {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private var actions: Actions?
    private let cardRepository: StickyCardRepository
    private var task: Task<Void, Never>?
    private var controllers: [Note.ID: CardController] = [:]
    /// 上一帧快照（CardDiff 的 old 输入；首帧为空 = 启动恢复全部 create）。
    private var previousSnapshot: [VisibleCard] = []
    /// 系统外观观察（打磨 R4）：深浅色切换即时推送全部卡片。
    private var appearanceObservation: NSKeyValueObservation?
    /// 自动隐藏共享轮询（S3-03，ADR-025 结论 1）：30Hz，仅当存在开启自动隐藏的卡片时运行。
    private var autoHideTimer: Timer?

    /// 外观判定的纯函数（便于 L2）：darkAqua 视为深色。
    nonisolated static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    init(cardRepository: StickyCardRepository) {
        self.cardRepository = cardRepository
    }

    func start(actions: Actions) {
        self.actions = actions
        // 外观观察（R4）：初始 + 变化时推送全部卡片（KVO 回调线程不定，转主 actor）。
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) {
            [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                let isDark = Self.isDarkAppearance(NSApp.effectiveAppearance)
                for controller in self.controllers.values {
                    controller.apply(appearance: isDark)
                }
            }
        }
        guard task == nil else { return }
        task = Task { [cardRepository] in
            do {
                for try await visible in cardRepository.observeVisible() {
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.apply(visible) }
                }
            } catch is CancellationError {
            } catch {
                // 观察流异常结束：与面板读取失败同一策略——记日志；重试入口随 S3-07 恢复逻辑评估。
                Log.app.error("卡片观察流异常结束：\(String(describing: error), privacy: .public)")
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
        previousSnapshot = []
    }

    /// 当前卡片 frame（钉出错开定位的输入）。
    func existingFrames() -> [CardFrame] {
        controllers.values.compactMap { controller in
            controller.currentFrame()
        }
    }

    /// 观察流快照 → 窗口操作。
    private func apply(_ visible: [VisibleCard]) {
        for operation in CardDiff.operations(old: previousSnapshot, new: visible) {
            switch operation {
            case .create(let noteID):
                createController(for: visible.first { $0.card.noteID == noteID }!)
            case .update(let noteID):
                guard let controller = controllers[noteID],
                      let item = visible.first(where: { $0.card.noteID == noteID }) else { continue }
                controller.apply(card: item.card, note: item.note)
            case .close(let noteID):
                controllers[noteID]?.close()
                controllers[noteID] = nil
            }
        }
        previousSnapshot = visible
        syncAutoHideTimer()
    }

    /// 有开自动隐藏的卡片才跑共享 30Hz 轮询（NFR24：全局一个监听器）。
    private func syncAutoHideTimer() {
        let needed = controllers.values.contains { $0.model.options.autoHide }
        if needed, autoHideTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.tickAutoHide()
                }
            }
            RunLoop.main.add(timer, forMode: .common) // .common：菜单跟踪期间也继续 tick
            autoHideTimer = timer
        } else if !needed, let timer = autoHideTimer {
            timer.invalidate()
            autoHideTimer = nil
        }
    }

    private func tickAutoHide() {
        let now = ProcessInfo.processInfo.systemUptime
        let mouse = NSEvent.mouseLocation
        for controller in controllers.values {
            let enabled = controller.model.options.autoHide
            let inside = enabled && controller.panel.frame.contains(mouse)
            if let state = controller.tickAutoHide(now: now, mouseInside: inside, enabled: enabled) {
                controller.applyAutoHideState(alpha: state.alpha, ignoresMouseEvents: state.ignoresMouseEvents)
            }
        }
    }

    private func createController(for item: VisibleCard) {
        guard actions != nil, controllers[item.card.noteID] == nil else { return }
        // 已有控制器缺失（理论不发生）时按新卡定位；正常创建用库里的 frame。
        let controller = CardController(
            card: item.card,
            note: item.note,
            screenVisibleFrame: actions?.screenProvider().visibleFrame ?? NSScreen.main!.visibleFrame,
            isDark: Self.isDarkAppearance(NSApp.effectiveAppearance),
            onMove: { [weak self] noteID, frame in
                self?.actions?.moveCard(noteID, frame)
            },
            onUnpin: { [weak self] noteID in
                self?.actions?.unpin(noteID)
            },
            onLevelCycle: { [weak self] noteID, options in
                self?.actions?.cycleLevel(noteID, options)
            },
            onOptionsChange: { [weak self] noteID, options in
                self?.actions?.updateOptions(noteID, options)
            }
        )
        controllers[item.card.noteID] = controller
        controller.show()
    }
}

/// 一张卡片 = 一个控制器：窗口 + 界面模型 + 动作回调 + 自动隐藏状态机（S3-03）。
@MainActor
final class CardController {
    let panel: StickyCardPanel
    let model: CardModel
    var autoHide = AutoHideStateMachine(parameters: .init(hideDelay: 3))
    private let screenVisibleFrame: NSRect
    private let onMove: (Note.ID, CardFrame) -> Void
    private let onUnpin: (Note.ID) -> Void
    private let onLevelCycle: (Note.ID, StickyCardOptions) -> Void
    private let onOptionsChange: (Note.ID, StickyCardOptions) -> Void
    /// 最近一次已应用到窗口的自动隐藏状态（tick 未变化时不重复做动画）。
    private var appliedAutoHide: (alpha: Double, ignoresMouseEvents: Bool)?

    init(
        card: StickyCard,
        note: Note,
        screenVisibleFrame: NSRect,
        isDark: Bool,
        onMove: @escaping (Note.ID, CardFrame) -> Void,
        onUnpin: @escaping (Note.ID) -> Void,
        onLevelCycle: @escaping (Note.ID, StickyCardOptions) -> Void,
        onOptionsChange: @escaping (Note.ID, StickyCardOptions) -> Void
    ) {
        self.screenVisibleFrame = screenVisibleFrame
        self.onMove = onMove
        self.onUnpin = onUnpin
        self.onLevelCycle = onLevelCycle
        self.onOptionsChange = onOptionsChange
        let frame = NSRect(
            x: card.frame.x, y: card.frame.y,
            width: card.frame.width, height: card.frame.height
        )
        panel = StickyCardPanel(noteID: card.noteID, contentRect: frame)
        model = CardModel(content: note.content, options: card.options, isDark: isDark)
        autoHide = AutoHideStateMachine(parameters: .init(hideDelay: card.options.hideDelay))
        autoHide.hiddenAlpha = card.options.hiddenOpacity
        panel.apply(options: card.options)
        panel.contentView = NSHostingView(
            rootView: CardContentView(
                model: model,
                onClose: { [weak self] in self?.closeRequested() },
                onLevelCycle: { [weak self] in self?.levelCycleRequested() },
                onDragStarted: { [weak self] in self?.setDragging(true) },
                onDragEnded: { [weak self] in self?.dragEnded() },
                onOptionsChange: { [weak self] options in
                    guard let self else { return }
                    self.model.options = options
                    self.syncAutoHideParameters()
                    self.onOptionsChange(self.panel.noteID, options)
                }
            )
        )
    }

    /// 系统深浅色切换（打磨 R4）。
    func apply(appearance isDark: Bool) {
        model.isDark = isDark
    }

    /// 选项变化后同步状态机参数（延迟/隐藏不透明度/开关）；
    /// 共享轮询的启停经写库→观察流回环（apply → syncAutoHideTimer），不在这里直呼。
    private func syncAutoHideParameters() {
        autoHide.parameters.hideDelay = model.options.hideDelay
        autoHide.hiddenAlpha = model.options.hiddenOpacity
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        // 非激活面板不会把拾刻变成前台应用（ADR-025 结论 4）；确保窗口可见即可。
        panel.orderFrontRegardless()
    }

    func apply(card: StickyCard, note: Note) {
        model.content = note.content
        model.options = card.options
        autoHide.parameters.hideDelay = card.options.hideDelay
        autoHide.hiddenAlpha = card.options.hiddenOpacity
        panel.apply(options: card.options)
        let newFrame = NSRect(
            x: card.frame.x, y: card.frame.y,
            width: card.frame.width, height: card.frame.height
        )
        if panel.frame != newFrame {
            panel.setFrame(newFrame, display: true)
        }
    }

    func currentFrame() -> CardFrame? {
        panel.isVisible ? CardFrame(
            x: panel.frame.minX, y: panel.frame.minY,
            width: panel.frame.width, height: panel.frame.height
        ) : nil
    }

    func close() {
        panel.orderOut(nil)
    }

    // - MARK: 自动隐藏（S3-03）

    /// 轮询 tick：推进状态机；返回需要应用到窗口的新状态（与上次相同则返回 nil）。
    /// 关闭自动隐藏的卡片若停在隐藏态，强制回显一次。
    func tickAutoHide(now: TimeInterval, mouseInside: Bool, enabled: Bool) -> (alpha: Double, ignoresMouseEvents: Bool)? {
        if !enabled {
            if autoHide.phase != .visible {
                autoHide.setBusy(true, now: now) // busy 强制回显
                autoHide.setBusy(false, now: now)
            } else if appliedAutoHide != nil {
                appliedAutoHide = nil
                return (1, false)
            } else {
                return nil
            }
        } else {
            autoHide.update(now: now, mouseInside: mouseInside)
        }
        let state = (alpha: autoHide.targetAlpha, ignoresMouseEvents: autoHide.ignoresMouseEvents)
        if let applied = appliedAutoHide,
           applied.alpha == state.alpha, applied.ignoresMouseEvents == state.ignoresMouseEvents
        {
            return nil
        }
        return state
    }

    /// 把状态应用到窗口（淡入淡出时长随相位；减弱动态效果直切）。
    func applyAutoHideState(alpha: Double, ignoresMouseEvents: Bool) {
        appliedAutoHide = (alpha, ignoresMouseEvents)
        panel.ignoresMouseEvents = ignoresMouseEvents
        let duration: TimeInterval
        switch autoHide.phase {
        case .fadingOut: duration = autoHide.parameters.fadeOutDuration
        case .fadingIn: duration = autoHide.parameters.fadeInDuration
        default: duration = 0
        }
        if Motion.reduce || duration == 0 {
            panel.alphaValue = alpha
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().alphaValue = alpha
            }
        }
    }

    /// 拖动期间不隐藏（03 §10.4）；结束时重置离开计时。
    func setDragging(_ dragging: Bool) {
        autoHide.setBusy(dragging, now: ProcessInfo.processInfo.systemUptime)
    }

    /// ✕ / 菜单取消钉住（便签保留）。
    private func closeRequested() {
        onUnpin(panel.noteID)
    }

    /// 层级按钮循环：floating → normal → desktop（03 §10.3；持久化经动作出口）。
    private func levelCycleRequested() {
        onLevelCycle(panel.noteID, model.options)
    }

    /// 拖动结束：钳制进所在可见区域后持久化（03 §10.2 移动）。
    private func dragEnded() {
        setDragging(false)
        let clamped = CardGeometry.clampedFrame(panel.frame, in: panel.screen?.visibleFrame ?? screenVisibleFrame)
        panel.setFrame(
            NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height),
            display: true
        )
        onMove(panel.noteID, clamped)
    }
}
