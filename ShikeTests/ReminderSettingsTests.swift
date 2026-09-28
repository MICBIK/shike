// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 3.3：提醒相关偏好与设置-提醒分页（SPEC CAP-3、04 §5.5、03 §9）。
@MainActor
struct ReminderSettingsTests {
    private func makePreferences() -> (Preferences, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        return (Preferences(defaults: UserDefaults(suiteName: suiteName)!), suiteName)
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    @Test("偏好键默认值与读写：menuBar.counter / allDayMinutes / snoozeMinutes")
    func preferenceDefaultsAndRoundtrip() {
        let (preferences, suiteName) = makePreferences()
        defer { cleanup(suiteName) }

        #expect(preferences.menuBarCounter == "overdueAndToday")
        #expect(preferences.reminderAllDayMinutes == 540)
        #expect(preferences.reminderSnoozeMinutes == 10)

        preferences.menuBarCounter = "allIncomplete"
        preferences.reminderAllDayMinutes = 600
        preferences.reminderSnoozeMinutes = 30
        #expect(preferences.menuBarCounter == "allIncomplete")
        #expect(preferences.reminderAllDayMinutes == 600)
        #expect(preferences.reminderSnoozeMinutes == 30)
    }

    @Test("SettingsModel 访问器：越界钳制与非法值回落")
    func settingsModelClamping() {
        let (preferences, suiteName) = makePreferences()
        defer { cleanup(suiteName) }
        let model = SettingsModel(
            hotkeyService: HotkeyService(preferences: preferences, enable: {}, disable: {}),
            launchAtLogin: LaunchAtLoginService(
                statusProvider: { .notRegistered },
                register: {},
                unregister: {},
                openSettings: {}
            ),
            preferences: preferences
        )

        #expect(model.menuBarCounter == .overdueAndToday)
        preferences.menuBarCounter = "bogus"
        #expect(model.menuBarCounter == .overdueAndToday) // 非法值回落
        model.menuBarCounter = .allIncomplete
        #expect(preferences.menuBarCounter == "allIncomplete")

        preferences.reminderAllDayMinutes = -5
        #expect(model.reminderAllDayMinutes == 0) // 下界钳制
        model.reminderAllDayMinutes = 1500
        #expect(model.reminderAllDayMinutes == 1439) // 上界钳制（0:00–23:59）

        preferences.reminderSnoozeMinutes = 7
        #expect(model.reminderSnoozeMinutes == 10) // 非法档位回落
        model.reminderSnoozeMinutes = 15
        #expect(preferences.reminderSnoozeMinutes == 15)
    }

    @Test("分钟数与时刻换算：往返一致、越界钳制（纯函数）")
    func minutesDateConversion() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = ReminderSettingsView.date(fromMinutes: 540)
        #expect(calendar.component(.hour, from: date) == 9)
        #expect(calendar.component(.minute, from: date) == 0)
        #expect(ReminderSettingsView.minutes(from: date) == 540)

        // 23:59 → 1439；钳制上界 1440
        let late = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: Date())!
        #expect(ReminderSettingsView.minutes(from: late) == 1439)
    }
}
