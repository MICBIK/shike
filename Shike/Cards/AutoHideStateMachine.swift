// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 自动隐藏状态机（S3-03，03 §10.4；NFR25）：
///
/// 显示中 ──鼠标离开满 N 秒（非 busy）──▶ 淡出中(0.3s) ──▶ 隐藏中
///   ▲                    隐藏中 --鼠标停留 0.2 秒--> 淡入中(0.15s) ──┘
///   └──────────────────────── busy（编辑/菜单/拖动）强制回显 ◀────────┘
///
/// 纯逻辑：时间由外部注入（now: TimeInterval，单调秒）、鼠标是否在卡片上由
/// 轮询方（CardManager 共享定时器）喂入；输出 targetAlpha / ignoresMouseEvents，
/// 视图层按相位时长做动画（减弱动态效果时直切）。
struct AutoHideStateMachine {
    enum Phase: Equatable {
        case visible
        case fadingOut
        case hidden
        case fadingIn
    }

    struct Parameters {
        /// 鼠标离开多少秒后开始淡出（03 §10.4：1/3 默认/5/10）。
        var hideDelay: TimeInterval
        /// 隐藏后鼠标停留多久唤回（0.2 秒）。
        var recallDelay: TimeInterval = 0.2
        var fadeOutDuration: TimeInterval = 0.3
        var fadeInDuration: TimeInterval = 0.15
    }

    var parameters: Parameters
    /// 隐藏态不透明度（0～0.6，随卡片选项更新）。
    var hiddenAlpha: Double = 0.2
    /// 编辑/菜单/拖动中不隐藏。
    var isBusy = false

    private(set) var phase: Phase = .visible
    private(set) var targetAlpha: Double = 1
    private(set) var ignoresMouseEvents = false

    private var phaseStartedAt: TimeInterval = 0
    private var mouseOutsideSince: TimeInterval?
    private var mouseInsideSince: TimeInterval?

    /// 每个轮询 tick 调用（30Hz）。
    mutating func update(now: TimeInterval, mouseInside: Bool) {
        switch phase {
        case .visible:
            if isBusy || mouseInside {
                mouseOutsideSince = nil
                return
            }
            let since = mouseOutsideSince ?? now
            mouseOutsideSince = since
            if now - since >= parameters.hideDelay {
                enter(.fadingOut, now: now)
            }
        case .fadingOut:
            if isBusy || mouseInside {
                // 淡出中途回鼠标/busy：直接转入淡入
                enter(.fadingIn, now: now)
                return
            }
            if now - phaseStartedAt >= parameters.fadeOutDuration {
                enter(.hidden, now: now)
            }
        case .hidden:
            if mouseInside {
                let since = mouseInsideSince ?? now
                mouseInsideSince = since
                if now - since >= parameters.recallDelay {
                    enter(.fadingIn, now: now)
                }
            } else {
                mouseInsideSince = nil
            }
        case .fadingIn:
            if now - phaseStartedAt >= parameters.fadeInDuration {
                enter(.visible, now: now)
            }
        }
    }

    /// busy 置位立即回显；解除后重置离开计时（避免立刻又淡出）。
    mutating func setBusy(_ busy: Bool, now: TimeInterval) {
        isBusy = busy
        if busy {
            if phase != .visible {
                enter(.visible, now: now)
            }
        } else {
            mouseOutsideSince = now
        }
    }

    private mutating func enter(_ newPhase: Phase, now: TimeInterval) {
        phase = newPhase
        phaseStartedAt = now
        mouseInsideSince = nil
        switch newPhase {
        case .visible, .fadingIn:
            targetAlpha = 1
            ignoresMouseEvents = false
            if newPhase == .visible {
                mouseOutsideSince = nil
            }
        case .fadingOut:
            targetAlpha = hiddenAlpha
            ignoresMouseEvents = false
        case .hidden:
            targetAlpha = hiddenAlpha
            ignoresMouseEvents = true
        }
    }
}
