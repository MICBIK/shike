// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 菜单栏计数口径（S2-08，04 §5.5 `menuBar.counter`）：
/// 不显示 / 逾期+今天（默认）/ 全部未完成。计数求值随 3.8 接线。
enum MenuBarCounter: String, CaseIterable {
    case none
    case overdueAndToday
    case allIncomplete
}
