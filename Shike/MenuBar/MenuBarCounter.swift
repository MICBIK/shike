// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 菜单栏计数口径（S2-08，04 §5.5 `menuBar.counter`）：
/// 不显示 / 逾期+今天（默认）/ 全部未完成。
enum MenuBarCounter: String, CaseIterable {
    case none
    case overdueAndToday
    case allIncomplete

    /// 存储值非法时回落逾期+今天（消费端回落口径）。
    static func resolve(_ rawValue: String) -> MenuBarCounter {
        MenuBarCounter(rawValue: rawValue) ?? .overdueAndToday
    }

    /// 计数（纯函数，注入 now/timeZone，NFR22）：nil 表示不显示。
    /// overdueAndToday = 逾期 + 今天的未完成；allIncomplete = 全部未完成（无日期计入）。
    static func count(_ mode: MenuBarCounter, todos: [Todo], now: Date, timeZone: TimeZone) -> Int? {
        switch mode {
        case .none:
            return nil
        case .overdueAndToday:
            let groups = TodoGrouping.group(todos: todos, now: now, timeZone: timeZone)
            return groups.overdue.count + groups.today.count
        case .allIncomplete:
            return todos.filter { $0.completedAt == nil }.count
        }
    }
}
