// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import SwiftUI

/// 设置时间弹层（S2-07，03 §6）：日历选日期、"包含时刻"开关、时刻选择；
/// 快捷按钮：今天、明天、下周一、清除时间。变更即时落库（autosave 风格）。
struct TodoTimeEditorView: View {
    let todo: Todo
    @Bindable var model: PanelModel

    @State private var day: Date
    @State private var hasTime: Bool
    @State private var timeOfDay: Date

    init(todo: Todo, model: PanelModel) {
        self.todo = todo
        self.model = model
        let timeZone = model.timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if let due = todo.due {
            _day = State(initialValue: calendar.startOfDay(for: due.date))
            _hasTime = State(initialValue: due.hasTime)
            if due.hasTime {
                let components = calendar.dateComponents([.hour, .minute], from: due.date)
                let reference = calendar.date(bySettingHour: components.hour ?? 9, minute: components.minute ?? 0, second: 0, of: Date()) ?? Date()
                _timeOfDay = State(initialValue: reference)
            } else {
                // 全天待办开启"包含时刻"：默认 09:00（不继承 00:00，盲审 F7）
                _timeOfDay = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
            }
        } else {
            _day = State(initialValue: calendar.startOfDay(for: Date()))
            _hasTime = State(initialValue: false)
            _timeOfDay = State(initialValue: calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date())
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DatePicker(
                String(localized: .timeEditorDate),
                selection: $day,
                displayedComponents: .date
            )
            .onChange(of: day) { _, newValue in
                apply(day: newValue)
            }
            Toggle(String(localized: .timeEditorHasTime), isOn: $hasTime)
                .onChange(of: hasTime) { _, newValue in
                    apply(hasTime: newValue)
                }
            if hasTime {
                DatePicker(
                    String(localized: .timeEditorTime),
                    selection: $timeOfDay,
                    displayedComponents: .hourAndMinute
                )
                .onChange(of: timeOfDay) { _, newValue in
                    apply(timeOfDay: newValue)
                }
            }
            HStack(spacing: 8) {
                quickButton(String(localized: .timeEditorQuickToday)) { Date() }
                quickButton(String(localized: .timeEditorQuickTomorrow)) {
                    Self.shiftDays(1, from: Date(), timeZone: model.timeZone)
                }
                quickButton(String(localized: .timeEditorQuickNextMonday)) {
                    Self.nextMonday(after: Date(), timeZone: model.timeZone)
                }
                Button(String(localized: .timeEditorClear), role: .destructive) {
                    Task {
                        await model.setDue(todo.id, nil)
                        model.editingTimeTarget = nil
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 300)
    }

    /// 快捷按钮（03 §6）：今天/明天/下周一都以**真实今天**为基准（绝对日期语义，
    /// 与当前选中日期无关，盲审 F1/F4）；只改 day，落库交给 onChange（避免双写，F6）。
    private func quickButton(_ title: String, action: @escaping () -> Date) -> some View {
        Button(title) {
            day = action()
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// 由弹层状态组合 TodoDue（day + hasTime + timeOfDay），写库（S2-07）。
    private func apply(day newDay: Date? = nil, hasTime newHasTime: Bool? = nil, timeOfDay newTime: Date? = nil) {
        let effectiveDay = newDay ?? day
        let effectiveHasTime = newHasTime ?? hasTime
        let effectiveTime = newTime ?? timeOfDay
        let due = Self.compose(
            day: effectiveDay,
            hasTime: effectiveHasTime,
            timeOfDay: effectiveTime,
            timeZone: model.timeZone
        )
        Task {
            await model.setDue(todo.id, due)
        }
    }

    // - MARK: 纯函数（L2 覆盖）

    /// 组合 due：hasTime 为否时存该日 00:00（04 §5.3；时区注入）。
    static func compose(day: Date, hasTime: Bool, timeOfDay: Date, timeZone: TimeZone) -> TodoDue? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: day)
        guard hasTime else {
            return TodoDue(date: dayStart, hasTime: false)
        }
        // bySettingHour（非 byAdding hour/minute）：DST 过渡日的墙上时刻不被偏移（盲审 F3）
        let hour = calendar.component(.hour, from: timeOfDay)
        let minute = calendar.component(.minute, from: timeOfDay)
        let date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: dayStart)
        return date.map { TodoDue(date: $0, hasTime: true) }
    }

    /// 顺延 N 个日历日（DST 安全；快捷"明天"）。
    static func shiftDays(_ count: Int, from day: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(byAdding: .day, value: count, to: calendar.startOfDay(for: day))!
    }

    /// 下一个周一（严格晚于 day 所在日；day 为周一则顺延一周）。全天 00:00。
    static func nextMonday(after day: Date, timeZone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let dayStart = calendar.startOfDay(for: day)
        // Calendar weekday：周日=1…周六=7
        let weekday = calendar.component(.weekday, from: dayStart)
        let daysUntilMonday = ((9 - weekday - 1) % 7) + 1 // 周一(2)→7，周二(3)→6，…，周日(1)→1
        return calendar.date(byAdding: .day, value: daysUntilMonday, to: dayStart)!
    }
}
