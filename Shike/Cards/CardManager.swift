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
        /// 卡片菜单改动选项（自动隐藏开关/延迟/不透明度，S3-03）。
    var updateOptions: (Note.ID, StickyCardOptions) -> Void
    /// 卡片上编辑保存（S3-06）：防抖自动保存与收尾保存共用。
    var updateNoteContent: (Note.ID, String) -> Void
    /// 退出冲刷的同步写通道（W1）：AppEnvironment 接 SyncFlush + NoteRepository
    /// （快照语义同既有写路径取面板快照）；默认空实现供测试组装。
    var syncUpdateNoteContent: (Note.ID, String) -> Void = { _, _ in }
    /// 在面板中显示（S3-08）：打开面板 + 切便签 + 定位（AppDelegate 接线）。
    var showInPanel: (UUID) -> Void
}

    /// 钉出定位与拖动钳制用的屏幕（面板所在屏；AppDelegate 在状态项就绪后设置）。
    nonisolated(unsafe) var screenProvider: () -> NSScreen = {
        NSScreen.main ?? NSScreen.screens[0]
    }

    private var actions: Actions?
    private let cardRepository: StickyCardRepository
    /// 三面编辑互斥仲裁（W4）：卡片进入编辑时 claim，其他面编辑同一条时对方收尾。
    private let editArbiter: EditArbiter
    private var task: Task<Void, Never>?
    private var controllers: [Note.ID: CardController] = [:]
    /// 上一帧快照（CardDiff 的 old 输入；首帧为空 = 启动恢复全部 create）。
    private var previousSnapshot: [VisibleCard] = []
    /// 启动恢复期（首帧 apply 进行中）：恢复出的普通层级卡片要让位，用户主动新钉不让（ADR-029）。
    private var isRestoringFirstSnapshot = true
    /// 系统外观观察（打磨 R4）：深浅色切换即时推送全部卡片。
    private var appearanceObservation: NSKeyValueObservation?
    /// 自动隐藏共享轮询（S3-03，ADR-025 结论 1）：30Hz，仅当存在开启自动隐藏的卡片时运行。
    private var autoHideTimer: Timer?
    /// 显示器变化（S3-07）：断开/改分辨率后把出屏卡片移回可见区域。
    private var screenChangeObserver: NSObjectProtocol?
    /// 全部隐藏（S3-09）：临时内存标记，不改卡片设置；true 时所有面板收起、轮询暂停。
    private(set) var isHiddenAll = false
    /// "在面板中显示"的出口（AppDelegate 接线：开面板 + 切便签 + 定位）。
    nonisolated(unsafe) var showInPanelHandler: (UUID) -> Void = { _ in }

    /// 外观判定的纯函数（便于 L2）：darkAqua 视为深色。
    nonisolated static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    init(cardRepository: StickyCardRepository, editArbiter: EditArbiter = EditArbiter()) {
        self.cardRepository = cardRepository
        self.editArbiter = editArbiter
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
        // 显示器变化（S3-07）：把出屏卡片钳回可见区域并持久化移动
        screenChangeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reclampAllToVisibleArea()
            }
        }
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
        if let screenChangeObserver {
            NotificationCenter.default.removeObserver(screenChangeObserver)
        }
        screenChangeObserver = nil
        for controller in controllers.values {
            controller.close()
        }
        controllers.removeAll()
        previousSnapshot = []
    }

    /// 退出冲刷（W1，applicationWillTerminate 在各 stop() 之前调用）：把在编辑
    /// 卡片的文字经注入的同步写通道落库。编辑态在捕获时收尾（teardownEditing
    /// 一并取消防抖）；文字未变的卡返回 nil 跳过，空→软删除的语义在
    /// SyncFlush.noteContent（AppEnvironment 注入）。
    func flushEditingContentsSynchronously() {
        for controller in controllers.values {
            guard let edit = controller.takeEditingForFlush() else { continue }
            actions?.syncUpdateNoteContent(edit.noteID, edit.text)
        }
    }

    // - MARK: 屏幕变化与全部显示/隐藏（S3-07 / S3-09）

    /// 显示器断开/分辨率变化：全部卡片钳回当前所在屏可见区域，移动过的持久化。
    private func reclampAllToVisibleArea() {
        for controller in controllers.values {
            guard let current = controller.currentFrame() else { continue }
            let visible = controller.panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            guard let visible else { continue }
            let clamped = CardGeometry.clampedFrame(
                NSRect(x: current.x, y: current.y, width: current.width, height: current.height),
                in: visible
            )
            if clamped.x != current.x || clamped.y != current.y {
                controller.panel.setFrame(
                    NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height),
                    display: true
                )
                actions?.moveCard(controller.panel.noteID, clamped)
            }
        }
    }

    /// 隐藏所有卡片（03 §10.6）：临时收起，不改设置不入库。
    func hideAllCards() {
        isHiddenAll = true
        autoHideTimer?.invalidate()
        autoHideTimer = nil
        for controller in controllers.values {
            controller.close()
        }
    }

    /// 显示所有卡片（03 §10.6）：恢复收起前的显示状态（隐藏期间新建/关闭由观察流对账兜住）。
    func showAllCards() {
        isHiddenAll = false
        for controller in controllers.values {
            controller.restoreForShowAll()
            controller.show()
        }
        syncAutoHideTimer()
    }

    /// 是否存在卡片记录（菜单项显示与否）。
    var hasCards: Bool { !controllers.isEmpty }

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
        isRestoringFirstSnapshot = false
        syncAutoHideTimer()
    }

    /// 有开自动隐藏的卡片才跑共享 30Hz 轮询（NFR24：全局一个监听器）；全部隐藏时暂停。
    private func syncAutoHideTimer() {
        let needed = !isHiddenAll && controllers.values.contains { $0.model.options.autoHide }
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
            editArbiter: editArbiter,
            isDark: Self.isDarkAppearance(NSApp.effectiveAppearance),
            onMove: { [weak self] noteID, frame in
                self?.actions?.moveCard(noteID, frame)
            },
            onUnpin: { [weak self] noteID in
                self?.actions?.unpin(noteID)
            },
            onOptionsChange: { [weak self] noteID, options in
                self?.actions?.updateOptions(noteID, options)
            },
            onContentChange: { [weak self] noteID, text in
                self?.actions?.updateNoteContent(noteID, text)
            },
            onShowInPanelRequest: { [weak self] uuid in
                self?.actions?.showInPanel(uuid)
            }
        )
        controllers[item.card.noteID] = controller
        if !isHiddenAll {
            controller.show()
            // ADR-029：启动恢复的普通层级卡片让位（沉到普通窗口链底部）——
            // 用户主动钉出的新卡仍提到最前（刚操作完要看到它）。
            if isRestoringFirstSnapshot, item.card.options.level == .normal {
                controller.sendToBack()
            }
        }
    }
}

/// 一张卡片 = 一个控制器：窗口 + 界面模型 + 动作回调 + 自动隐藏状态机（S3-03）。
@MainActor
final class CardController: NSObject, NSWindowDelegate {
    let panel: StickyCardPanel
    let model: CardModel
    var autoHide = AutoHideStateMachine(parameters: .init(hideDelay: 3))
    private let screenVisibleFrame: NSRect
    private let onMove: (Note.ID, CardFrame) -> Void
    private let onUnpin: (Note.ID) -> Void
    private let onOptionsChange: (Note.ID, StickyCardOptions) -> Void
    private let onContentChange: (Note.ID, String) -> Void
    private let onShowInPanelRequest: (UUID) -> Void
    /// 便签 uuid（"在面板中显示"定位用，S3-08）。
    let noteUUID: UUID
    /// 最近一次已应用到窗口的自动隐藏状态（tick 未变化时不重复做动画）。
    private var appliedAutoHide: (alpha: Double, ignoresMouseEvents: Bool)?
    /// 最近一次已持久化（或正持久化）的窗口位置：windowDidMove 兜底落库的去重基准（ADR-027）。
    private var lastPersistedFrame: CardFrame?
    /// 编辑防抖任务（0.5 秒，03 §10.2）。
    private var autosaveTask: Task<Void, Never>?
    /// 三面编辑互斥仲裁（W4）：由 CardManager 下传（AppEnvironment 装配的环境级单份）。
    private let editArbiter: EditArbiter

    init(
        card: StickyCard,
        note: Note,
        screenVisibleFrame: NSRect,
        editArbiter: EditArbiter,
        isDark: Bool,
        onMove: @escaping (Note.ID, CardFrame) -> Void,
        onUnpin: @escaping (Note.ID) -> Void,
        onOptionsChange: @escaping (Note.ID, StickyCardOptions) -> Void,
        onContentChange: @escaping (Note.ID, String) -> Void,
        onShowInPanelRequest: @escaping (UUID) -> Void
    ) {
        // NSObject 子类：先初始化全部存储属性 → super.init() → 才能使用 self（闭包捕获）
        self.screenVisibleFrame = screenVisibleFrame
        self.editArbiter = editArbiter
        self.onMove = onMove
        self.onUnpin = onUnpin
        self.onOptionsChange = onOptionsChange
        self.onContentChange = onContentChange
        self.onShowInPanelRequest = onShowInPanelRequest
        self.noteUUID = note.uuid
        let frame = NSRect(
            x: card.frame.x, y: card.frame.y,
            width: card.frame.width, height: card.frame.height
        )
        panel = StickyCardPanel(noteID: card.noteID, contentRect: frame)
        model = CardModel(content: note.content, options: card.options, isDark: isDark)
        autoHide = AutoHideStateMachine(parameters: .init(hideDelay: card.options.hideDelay))
        autoHide.hiddenAlpha = card.options.hiddenOpacity
        panel.apply(options: card.options)
        super.init()
        panel.delegate = self // 失去 key（点击外部）即结束编辑（03 §10.2）
        panel.contentView = CardHostingView(
            rootView: CardContentView(
                model: model,
                onClose: { [weak self] in self?.closeRequested() },
                onDragStarted: { [weak self] in self?.setDragging(true) },
                onDragEnded: { [weak self] in self?.dragEnded() },
                onResizeEnded: { [weak self] in self?.resizeEnded() },
                onOptionsChange: { [weak self] options in
                    guard let self else { return }
                    self.model.options = options
                    self.syncAutoHideParameters()
                    self.onOptionsChange(self.panel.noteID, options)
                },
                onEditRequest: { [weak self] in self?.beginEditing() },
                onEditingTextChange: { [weak self] text in self?.scheduleAutosave(text: text) },
                onEditEnd: { [weak self] in self?.endEditing(save: true) },
                onShowInPanel: { [weak self] in
                    guard let self else { return }
                    self.onShowInPanelRequest(self.noteUUID)
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

    /// 沉到所在层级窗口链底部（ADR-029：启动恢复的普通层级卡片让位）。
    func sendToBack() {
        panel.orderBack(nil)
    }

    func apply(card: StickyCard, note: Note) {
        // 编辑中不改写正文（本地编辑是唯一真相，保存经观察流回流）
        if !model.isEditing {
            model.content = note.content
        }
        model.options = card.options
        autoHide.parameters.hideDelay = card.options.hideDelay
        autoHide.hiddenAlpha = card.options.hiddenOpacity
        // 编辑中冻结窗口层级/空间属性（编辑态卡片临时浮出，ADR-031），
        // 结束编辑时 endEditing 统一应用；内容/颜色/字号由 SwiftUI 随 model 即时渲染。
        if !model.isEditing {
            panel.apply(options: card.options)
        }
        // frame 不在这里回写窗口（ADR-027）：拖动落库是异步写，完成前的观察流回流
        // 带着旧位置，回写会把刚拖的卡片弹回初始位置（2026-09-29 用户真机反馈）。
        // 窗口层是 frame 的唯一作者：位移经 dragEnded/resizeEnded/windowDidMove
        // 持久化；DB 里的 frame 只在创建控制器时消费。
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

    /// 全部显示（S3-09，打磨 R9）：隐藏相位停着的卡片若只 orderFront 会保持
    /// 半透明+点击穿透——强制回显并重置自动隐藏计时。
    func restoreForShowAll() {
        autoHide.setBusy(true, now: 0)
        autoHide.setBusy(false, now: 0)
        panel.ignoresMouseEvents = false
        panel.alphaValue = 1
        appliedAutoHide = (1, false)
    }

    // - MARK: 卡片上编辑（S3-06，03 §10.2）

    /// 双击进入编辑：窗口允许成为 key（ADR-025 结论 4）并聚焦文本视图；编辑中不自动隐藏。
    /// 进入前先经仲裁器 claim（W4 三面互斥）：面板/主窗口正在编辑同一条便签时，
    /// 对方先收尾（触发保存），本卡拿到编辑（"后来者拿走"）。
    func beginEditing() {
        guard !model.isEditing else { return }
        editArbiter.claim(
            noteID: panel.noteID,
            owner: .card,
            isEditing: { [weak self] in self?.model.isEditing == true },
            endEditing: { [weak self] in self?.endEditing(save: true) }
        )
        autosaveTask?.cancel()
        model.editingText = model.content
        model.isEditing = true
        panel.allowsKey = true
        // 编辑时临时浮出（ADR-031）：普通层级卡片在 normal−1 层，可能整个被别的
        // 窗口盖住——浮到 floating 让输入可见；结束编辑按所选层级回落。
        panel.level = .floating
        panel.makeKey()
        panel.makeFirstResponder(nil) // 让 SwiftUI 的 FocusState 接管第一响应者
        autoHide.setBusy(true, now: ProcessInfo.processInfo.systemUptime)
    }

    /// 结束编辑（Esc/点击外部/关闭卡片）。save=false 仅用于卡片即将销毁的路径。
    func endEditing(save: Bool) {
        guard model.isEditing else { return }
        let text = teardownEditing()
        if save, text != model.content {
            // 面板同语义：内容未变跳过、清空=删除入撤销栈、失败上面板提示条
            onContentChange(panel.noteID, text)
        }
    }

    /// 收编辑态的公共收尾（endEditing 与退出冲刷共用）：取消防抖、复位编辑文字、
    /// 窗口层级回落、解除 busy；返回编辑文字供调用方决定保存路径。
    private func teardownEditing() -> String {
        autosaveTask?.cancel()
        autosaveTask = nil
        let text = model.editingText
        model.isEditing = false
        model.editingText = ""
        panel.allowsKey = false
        // 按所选层级回落（ADR-031）：普通层级回到 normal−1 并让位（apply 的
        // orderBack）；编辑期间用户若改了层级选项，也在这里统一生效。
        panel.apply(options: model.options)
        autoHide.setBusy(false, now: ProcessInfo.processInfo.systemUptime)
        return text
    }

    /// 退出冲刷接缝（W1）：取走在编辑文字并收编辑态（不走 onContentChange 的
    /// fire-and-forget 通道）；文字未变返回 nil（同保存语义的跳过）。
    func takeEditingForFlush() -> (noteID: Note.ID, text: String)? {
        guard model.isEditing else { return nil }
        let text = teardownEditing()
        guard text != model.content else { return nil }
        return (panel.noteID, text)
    }

    /// 停止输入 0.5 秒自动保存（03 §10.2；FR44 防抖同面板）。
    private func scheduleAutosave(text: String) {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.model.isEditing else { return }
                if text != self.model.content {
                    self.onContentChange(self.panel.noteID, text)
                }
            }
        }
    }

    /// ✕ / 菜单取消钉住（便签保留）。
    private func closeRequested() {
        endEditing(save: true) // 关闭前把未保存的编辑冲出去
        onUnpin(panel.noteID)
    }

    /// 拖动结束：钳制进所在可见区域后持久化（03 §10.2 移动）。
    private func dragEnded() {
        setDragging(false)
        let clamped = CardGeometry.clampedFrame(panel.frame, in: panel.screen?.visibleFrame ?? screenVisibleFrame)
        panel.setFrame(
            NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height),
            display: true
        )
        persistFrame(clamped)
    }

    /// 调整大小结束（03 §10.2，ADR-026）：把手跟踪期间已实时钳制最小尺寸，
    /// 这里再按可见区域钳制出屏部分并持久化（与移动同走 onMove）。
    private func resizeEnded() {
        setDragging(false) // 与拖动共用 busy 位，结束后重置自动隐藏计时
        let clamped = CardGeometry.clampedResize(frame: panel.frame, in: panel.screen?.visibleFrame ?? screenVisibleFrame)
        panel.setFrame(
            NSRect(x: clamped.x, y: clamped.y, width: clamped.width, height: clamped.height),
            display: true
        )
        persistFrame(clamped)
    }

    /// 位置持久化（去重基准在 lastPersistedFrame）：写失败走面板提示条与重试（NFR19）。
    private func persistFrame(_ frame: CardFrame) {
        lastPersistedFrame = frame
        onMove(panel.noteID, frame)
    }
}

/// 点击卡片外部（窗口失去 key）即结束编辑并保存（03 §10.2）。
extension CardController {
    func windowDidResignKey(_ notification: Notification) {
        if model.isEditing {
            endEditing(save: true)
        }
    }

    /// 位移兜底持久化（ADR-027）：手势收尾（dragEnded/resizeEnded）之外的任何窗口
    /// 移动也把最终位置落库；与已持久化值一致时跳过。
    /// 拖动/调整大小进行中跳过（performDrag 拖动过程会连续触发本回调，收尾路径
    /// 已统一落库——中途每次移动都写库是写库风暴，ADR-028）。
    func windowDidMove(_ notification: Notification) {
        guard panel.isVisible, !model.isDragging else { return }
        let clamped = CardGeometry.clampedFrame(panel.frame, in: panel.screen?.visibleFrame ?? screenVisibleFrame)
        if clamped != lastPersistedFrame {
            persistFrame(clamped)
        }
    }
}
