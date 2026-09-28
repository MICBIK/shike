// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 设置-提醒分页（S2-03/S2-04，03 §9）：全天待办提醒时刻与"稍后提醒"时长。
/// 通知权限状态行随 S2-10 加入。
struct ReminderSettingsView: View {
    @Bindable var model: SettingsModel
    /// 全天提醒时刻的选择器绑定值（当天 00:00 + allDayMinutes，按当前时区）。
    @State private var allDayTime: Date

    /// 注：`@State` 初值只在视图首次进入层次时读取；外部直接改偏好不会刷新选择器
    /// （当前无此场景）。onChange 滚轮滚动会逐 tick 写偏好——S2-05 的"设置变化对账"
    /// 需自行合并去抖（盲审 F7）。
    init(model: SettingsModel) {
        self.model = model
        _allDayTime = State(initialValue: Self.date(fromMinutes: model.reminderAllDayMinutes))
    }

    var body: some View {
        Form {
            DatePicker(
                String(localized: .settingsReminderAllDayTime),
                selection: $allDayTime,
                displayedComponents: .hourAndMinute
            )
            .onChange(of: allDayTime) { _, newValue in
                model.reminderAllDayMinutes = Self.minutes(from: newValue)
                model.onReminderSettingsChanged()
            }
            Picker(String(localized: .settingsReminderSnooze), selection: $model.reminderSnoozeMinutes) {
                ForEach(SettingsModel.snoozeOptions, id: \.self) { minutes in
                    Text(String(localized: .settingsReminderSnoozeMinutes(minutes))).tag(minutes)
                }
            }
            HStack {
                Text(String(localized: .settingsReminderPermission))
                Spacer()
                Text(permissionText)
                    .foregroundStyle(model.notificationPermission == .denied ? Color.red : Color.secondary)
                Button(String(localized: .bannerOpenSystemSettings)) {
                    model.openNotificationSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .onChange(of: model.reminderSnoozeMinutes) { _, _ in
                // 时长变化：重对账之外还需重注册类别（按钮括号文案随设置变化，盲审 3.4-F3）。
                model.onReminderSettingsChanged()
            }
        }
        .padding(20)
        .formStyle(.grouped)
        .task {
            await model.refreshNotificationPermission()
        }
    }

    private var permissionText: String {
        switch model.notificationPermission {
        case .granted: String(localized: .settingsReminderPermissionGranted)
        case .denied: String(localized: .settingsReminderPermissionDenied)
        case .notDetermined: String(localized: .settingsReminderPermissionNotDetermined)
        case .unknown: "—"
        }
    }

    // - MARK: 分钟数与时刻的换算（纯函数，L2 覆盖）

    /// 分钟数 → 当天 00:00 + 分钟（按当前时区；展示用，跨天钳制在 picker 内不发生）。
    static func date(fromMinutes minutes: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let dayStart = calendar.startOfDay(for: Date())
        return dayStart.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 时刻 → 从 0 点起的分钟数（钳制到 0...1439）。
    static func minutes(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return min(1439, max(0, hour * 60 + minute))
    }
}
