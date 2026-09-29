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

    init(cardRepository: StickyCardRepository) {
        self.cardRepository = cardRepository
    }

    func start(actions: Actions) {
        self.actions = actions
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
    }

    private func createController(for item: VisibleCard) {
        guard actions != nil, controllers[item.card.noteID] == nil else { return }
        // 已有控制器缺失（理论不发生）时按新卡定位；正常创建用库里的 frame。
        let controller = CardController(
            card: item.card,
            note: item.note,
            screenVisibleFrame: actions?.screenProvider().visibleFrame ?? NSScreen.main!.visibleFrame,
            onMove: { [weak self] noteID, frame in
                self?.actions?.moveCard(noteID, frame)
            },
            onUnpin: { [weak self] noteID in
                self?.actions?.unpin(noteID)
            },
            onLevelCycle: { [weak self] noteID, options in
                self?.actions?.cycleLevel(noteID, options)
            }
        )
        controllers[item.card.noteID] = controller
        controller.show()
    }
}

/// 一张卡片 = 一个控制器：窗口 + 界面模型 + 动作回调。
@MainActor
final class CardController {
    let panel: StickyCardPanel
    let model: CardModel
    private let screenVisibleFrame: NSRect
    private let onMove: (Note.ID, CardFrame) -> Void
    private let onUnpin: (Note.ID) -> Void
    private let onLevelCycle: (Note.ID, StickyCardOptions) -> Void

    init(
        card: StickyCard,
        note: Note,
        screenVisibleFrame: NSRect,
        onMove: @escaping (Note.ID, CardFrame) -> Void,
        onUnpin: @escaping (Note.ID) -> Void,
        onLevelCycle: @escaping (Note.ID, StickyCardOptions) -> Void
    ) {
        self.screenVisibleFrame = screenVisibleFrame
        self.onMove = onMove
        self.onUnpin = onUnpin
        self.onLevelCycle = onLevelCycle
        let frame = NSRect(
            x: card.frame.x, y: card.frame.y,
            width: card.frame.width, height: card.frame.height
        )
        panel = StickyCardPanel(noteID: card.noteID, contentRect: frame)
        model = CardModel(content: note.content, options: card.options)
        panel.apply(options: card.options)
        panel.contentView = NSHostingView(
            rootView: CardContentView(
                model: model,
                onClose: { [weak self] in self?.closeRequested() },
                onLevelCycle: { [weak self] in self?.levelCycleRequested() },
                onDragEnded: { [weak self] in self?.dragEnded() }
            )
        )
    }

    func show() {
        panel.makeKeyAndOrderFront(nil)
        // 非激活面板不会把拾刻变成前台应用（ADR-025 结论 4）；确保窗口可见即可。
        panel.orderFrontRegardless()
    }

    func apply(card: StickyCard, note: Note) {
        model.content = note.content
        model.options = card.options
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
        let clamped = CardGeometry.clampedFrame(panel.frame, in: panel.screen?.visibleFrame ?? screenVisibleFrame)
        panel.setFrame(
            NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height),
            display: true
        )
        onMove(panel.noteID, clamped)
    }
}
