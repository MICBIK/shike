// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import Shike

/// S3-03：自动隐藏状态机全路径（03 §10.4；NFR25 纯逻辑注入时钟）。
struct AutoHideStateMachineTests {
    /// 3 秒延迟、隐藏 20% 的标准机器。
    private func machine() -> AutoHideStateMachine {
        var m = AutoHideStateMachine(parameters: .init(hideDelay: 3))
        m.hiddenAlpha = 0.2
        return m
    }

    @Test("显示中：离开不满 N 秒不淡出，满 N 秒进入淡出（目标=隐藏不透明度）")
    func visibleToFadingOut() {
        var m = machine()
        m.update(now: 0, mouseInside: false)
        m.update(now: 2.9, mouseInside: false)
        #expect(m.phase == .visible)
        m.update(now: 3.0, mouseInside: false)
        #expect(m.phase == .fadingOut)
        #expect(m.targetAlpha == 0.2)
        #expect(!m.ignoresMouseEvents) // 淡出中仍可交互
    }

    @Test("淡出走完进入隐藏：点击穿透生效")
    func fadingOutToHidden() {
        var m = machine()
        m.update(now: 0, mouseInside: false)
        m.update(now: 3.0, mouseInside: false)
        m.update(now: 3.2, mouseInside: false) // 0.2 < 0.3 仍在淡出
        #expect(m.phase == .fadingOut)
        m.update(now: 3.35, mouseInside: false) // 0.35 > 0.3（避开 3.3-3.0 的浮点边界）
        #expect(m.phase == .hidden)
        #expect(m.targetAlpha == 0.2)
        #expect(m.ignoresMouseEvents)
    }

    @Test("隐藏中：鼠标停留满 0.2 秒唤回（淡入→显示）")
    func hiddenRecallOnHover() {
        var m = machine()
        m.update(now: 0, mouseInside: false)
        m.update(now: 3.0, mouseInside: false)
        m.update(now: 3.35, mouseInside: false)
        #expect(m.phase == .hidden)
        m.update(now: 3.5, mouseInside: true) // 停留 0 < 0.2
        #expect(m.phase == .hidden)
        m.update(now: 3.75, mouseInside: true) // 0.25 > 0.2 达标
        #expect(m.phase == .fadingIn)
        #expect(m.targetAlpha == 1)
        #expect(!m.ignoresMouseEvents)
        m.update(now: 3.95, mouseInside: true) // 0.2 > 0.15 淡入完成
        #expect(m.phase == .visible)
    }

    @Test("淡出中途回鼠标：直接转入淡入")
    func mouseBackDuringFadeOut() {
        var m = machine()
        m.update(now: 0, mouseInside: false)
        m.update(now: 3.0, mouseInside: false)
        #expect(m.phase == .fadingOut)
        m.update(now: 3.1, mouseInside: true)
        #expect(m.phase == .fadingIn)
        #expect(m.targetAlpha == 1)
    }

    @Test("离开计时在鼠标回卡时重置（出去 2 秒 → 回来 → 再出去要重新等满 3 秒）")
    func leaveTimerResetsOnReenter() {
        var m = machine()
        m.update(now: 0, mouseInside: false)
        m.update(now: 2.0, mouseInside: true) // 回卡重置
        m.update(now: 4.0, mouseInside: false) // 重新计时：4.9 时才 0.9 秒
        m.update(now: 6.5, mouseInside: false) // 距 4.0 已 2.5 秒，未满 3
        #expect(m.phase == .visible)
        m.update(now: 7.0, mouseInside: false) // 满 3 秒
        #expect(m.phase == .fadingOut)
    }

    @Test("busy 强制回显；解除 busy 后重置离开计时（不会立刻又隐藏）")
    func busyForcesVisible() {
        var m = machine()
        m.update(now: 0, mouseInside: false)
        m.update(now: 3.0, mouseInside: false)
        m.update(now: 3.35, mouseInside: false)
        #expect(m.phase == .hidden)
        m.setBusy(true, now: 3.4)
        #expect(m.phase == .visible)
        #expect(m.targetAlpha == 1)
        #expect(!m.ignoresMouseEvents)
        m.setBusy(false, now: 3.5)
        // 解除后即使鼠标不在卡上，也要重新等满 N 秒
        m.update(now: 5.0, mouseInside: false) // 距 3.5 为 1.5 秒
        #expect(m.phase == .visible)
        m.update(now: 6.5, mouseInside: false) // 满 3 秒
        #expect(m.phase == .fadingOut)
    }

    @Test("隐藏不透明度与延迟参数随卡片选项更新（每卡独立）")
    func parametersFollowOptions() {
        // 1 秒延迟档 + 60% 隐藏度（延迟/不透明度都来自卡片选项）
        var m = AutoHideStateMachine(parameters: .init(hideDelay: 1))
        m.hiddenAlpha = 0.6
        m.update(now: 0, mouseInside: false)
        m.update(now: 1.1, mouseInside: false) // 延迟 1 秒即淡出
        #expect(m.phase == .fadingOut)
        #expect(m.targetAlpha == 0.6)
        // 0% 完全看不见仍可唤回（02 验收项）
        var m2 = machine()
        m2.hiddenAlpha = 0.0
        m2.update(now: 0, mouseInside: false)
        m2.update(now: 3.0, mouseInside: false)
        m2.update(now: 3.35, mouseInside: false)
        #expect(m2.phase == .hidden)
        #expect(m2.targetAlpha == 0.0)
        #expect(m2.ignoresMouseEvents)
        m2.update(now: 3.5, mouseInside: true)
        m2.update(now: 3.75, mouseInside: true)
        #expect(m2.phase == .fadingIn)
        #expect(m2.targetAlpha == 1)
    }
}
