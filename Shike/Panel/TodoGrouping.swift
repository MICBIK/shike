// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 待办五分组（S2-06，03 §6）：逾期（红）/ 今天 / 以后 / 无日期 / 已完成（折叠）。
/// 全部注入 now 与时区（NFR22）；组内排序：逾期/今天/以后按 due 升序，
/// 无日期按创建时间降序（保持"新条目在顶部"），已完成按完成时间降序。
struct TodoGroups: Equatable {
    let overdue: [Todo]
    let today: [Todo]
    let later: [Todo]
    let noDate: [Todo]
    let completed: [Todo]

    /// 除已完成外全空（空状态视图的判定）。
    var hasNoActive: Bool {
        overdue.isEmpty && today.isEmpty && later.isEmpty && noDate.isEmpty
    }
}

enum TodoGrouping {
    /// 以本地时区的当天 [00:00, 24:00) 为界划分（03 §6）。
    static func group(todos: [Todo], now: Date, timeZone: TimeZone) -> TodoGroups {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayStart = calendar.startOfDay(for: now)
        // 日历日推进（非 +86400）：DST 时区的春/秋令时当天日长 ≠ 24 小时（盲审 F1）。
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        var overdue: [Todo] = []
        var today: [Todo] = []
        var later: [Todo] = []
        var noDate: [Todo] = []
        var completed: [Todo] = []

        for todo in todos {
            if todo.completedAt != nil {
                completed.append(todo)
            } else if let due = todo.due {
                if due.date < todayStart {
                    overdue.append(todo)
                } else if due.date < tomorrowStart {
                    today.append(todo)
                } else {
                    later.append(todo)
                }
            } else {
                noDate.append(todo)
            }
        }

        func byDueAscending(_ a: Todo, _ b: Todo) -> Bool {
            (a.due?.date ?? .distantFuture) < (b.due?.date ?? .distantFuture)
        }
        return TodoGroups(
            overdue: overdue.sorted(by: byDueAscending),
            today: today.sorted(by: byDueAscending),
            later: later.sorted(by: byDueAscending),
            // 并列时以 id 决胜（sort 非稳定；无日期序与阶段 1 流序 createdAt DESC, id DESC 对齐，盲审 F5）
            noDate: noDate.sorted { ($0.createdAt, $0.id.rawValue) > ($1.createdAt, $1.id.rawValue) },
            completed: completed.sorted {
                (($0.completedAt ?? .distantPast), $0.id.rawValue) > (($1.completedAt ?? .distantPast), $1.id.rawValue)
            }
        )
    }

    /// 行尾时间文案（03 §6）：今年内不显示年份、全天不显示时刻。
    static func timeText(for todo: Todo, now: Date, timeZone: TimeZone) -> String? {
        guard let due = todo.due else { return nil }
        return TimeDisplay.text(for: due.date, hasTime: due.hasTime, now: now, timeZone: timeZone)
    }

    /// 是否逾期（行尾时间红色显示）：未完成且 due 早于今天 0 点。
    static func isOverdue(_ todo: Todo, now: Date, timeZone: TimeZone) -> Bool {
        guard todo.completedAt == nil, let due = todo.due else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return due.date < calendar.startOfDay(for: now)
    }
}
