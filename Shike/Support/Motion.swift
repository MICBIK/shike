// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import SwiftUI

/// 动效辅助（视觉打磨批次，03 §3）：统一时长与缓动，并尊重系统"减弱动态效果"
/// （NSWorkspace.accessibilityDisplayShouldReduceMotion——开启时全部动效降级为直切）。
enum Motion {
    static var reduce: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// 标准出入场（提示条、chip、反馈条）；减弱动态效果时返回 nil（直切）。
    static func standard(_ duration: Double = 0.18) -> Animation? {
        reduce ? nil : .easeOut(duration: duration)
    }

    /// 列表行与勾选等更明显的形变（0.2–0.3s）；减弱动态效果时返回 nil。
    static func gentle(_ duration: Double = 0.25) -> Animation? {
        reduce ? nil : .easeInOut(duration: duration)
    }
}
