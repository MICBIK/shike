// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 偏好设置：类型化地读写 UserDefaults。
/// 键名只在 `Preferences.Key` 中定义，默认值在同一处注册（conventions.md）。
/// 测试使用独立 suite 的 UserDefaults，并在结束时清除该 suite。
///
/// UserDefaults 线程安全但未标注 Sendable，故本类型不声明 Sendable；
/// 它由 AppEnvironment（@MainActor）持有，随主_actor 使用。
public struct Preferences {
    /// 全部偏好键（04 §5.5）。新键随所属能力在对应阶段加入。
    public enum Key {
        public static let backupKeepCount = "backup.keepCount"
        public static let panelSize = "panel.size"
        public static let hotkeyTogglePanelEnabled = "hotkey.togglePanel.enabled"
        public static let panelLastMode = "panel.lastMode"
        public static let panelOpenMode = "panel.openMode"
        public static let panelDraftNote = "panel.draft.note"
        public static let panelDraftTodo = "panel.draft.todo"
        public static let menuBarCounter = "menuBar.counter"
        public static let reminderAllDayMinutes = "reminder.allDayMinutes"
        public static let reminderSnoozeMinutes = "reminder.snoozeMinutes"
    }

    /// 默认值注册表：与 Key 同处维护（计算属性，避免非 Sendable 静态共享状态）。
    private static var defaultValues: [String: Any] {
        [
            Key.backupKeepCount: 7,
            Key.panelSize: "360.0x520.0",
            Key.hotkeyTogglePanelEnabled: true,
            Key.panelLastMode: "note",
            Key.panelOpenMode: "last",
            Key.panelDraftNote: "",
            Key.panelDraftTodo: "",
            Key.menuBarCounter: "overdueAndToday",
            Key.reminderAllDayMinutes: 540,
            Key.reminderSnoozeMinutes: 10,
        ]
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        defaults.register(defaults: Self.defaultValues)
    }

    /// 每日备份保留份数（默认 7）。
    public var backupKeepCount: Int {
        get { defaults.integer(forKey: Key.backupKeepCount) }
        set { defaults.set(newValue, forKey: Key.backupKeepCount) }
    }

    /// 面板尺寸（S1-01，03 §3）。以"宽x高"文本存储，便于在 defaults 中直接检查；
    /// 存储值无法解析时回落默认尺寸，绝不 crash。setter 是 nonmutating：本类型只是
    /// UserDefaults 的门面，不持有可变状态（backupKeepCount 的 setter 同理，仅因历史原因保持默认）。
    public var panelSize: CGSize {
        get {
            guard let raw = defaults.string(forKey: Key.panelSize) else {
                return PanelSizing.defaultSize
            }
            return Self.parsePanelSize(raw) ?? PanelSizing.defaultSize
        }
        nonmutating set {
            defaults.set("\(newValue.width)x\(newValue.height)", forKey: Key.panelSize)
        }
    }

    /// "宽x高"（两个正数）的解析；供测试与读取共用。
    static func parsePanelSize(_ raw: String) -> CGSize? {
        let parts = raw.split(separator: "x")
        guard parts.count == 2,
              let width = Double(parts[0]), width > 0,
              let height = Double(parts[1]), height > 0 else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    /// 全局快捷键是否启用（S1-02，03 §13）：默认开启；关闭状态由 KeyboardShortcuts
    /// 的 enable/disable 与本键共同持久化。
    public var hotkeyTogglePanelEnabled: Bool {
        get { defaults.object(forKey: Key.hotkeyTogglePanelEnabled) == nil
            ? true
            : defaults.bool(forKey: Key.hotkeyTogglePanelEnabled) }
        nonmutating set { defaults.set(newValue, forKey: Key.hotkeyTogglePanelEnabled) }
    }

    /// 上次使用的面板模式（S1-03，03 §9）：值来自 PanelModel.Mode.rawValue；
    /// 存储值非法时回落 note。
    public var panelLastMode: String {
        get { defaults.string(forKey: Key.panelLastMode) ?? "note" }
        nonmutating set { defaults.set(newValue, forKey: Key.panelLastMode) }
    }

    /// 呼出时进入哪个模式（S1-03，03 §9）：last / note / todo；非法值回落 last。
    public var panelOpenMode: String {
        get { defaults.string(forKey: Key.panelOpenMode) ?? "last" }
        nonmutating set { defaults.set(newValue, forKey: Key.panelOpenMode) }
    }

    /// 便签模式的未提交草稿（S1-04，03 §4）。
    public var panelDraftNote: String {
        get { defaults.string(forKey: Key.panelDraftNote) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.panelDraftNote) }
    }

    /// 待办模式的未提交草稿（S1-04，03 §4）。
    public var panelDraftTodo: String {
        get { defaults.string(forKey: Key.panelDraftTodo) ?? "" }
        nonmutating set { defaults.set(newValue, forKey: Key.panelDraftTodo) }
    }

    /// 菜单栏计数口径（S2-08，03 §9）：none / overdueAndToday（默认）/ allIncomplete；
    /// 存储值非法时由消费端回落 overdueAndToday。
    public var menuBarCounter: String {
        get { defaults.string(forKey: Key.menuBarCounter) ?? "overdueAndToday" }
        nonmutating set { defaults.set(newValue, forKey: Key.menuBarCounter) }
    }

    /// 全天待办的提醒时刻（S2-03，03 §9）：从 0 点起的分钟数，默认 540（09:00）。
    /// 键被外部写坏成非数字时 integer(forKey:) 会返回 0（=00:00），因此用 object 强转回落
    /// 默认值（盲审 F2）；越界值由消费端钳制到 0...1439。
    public var reminderAllDayMinutes: Int {
        get { (defaults.object(forKey: Key.reminderAllDayMinutes) as? Int) ?? 540 }
        nonmutating set { defaults.set(newValue, forKey: Key.reminderAllDayMinutes) }
    }

    /// "稍后提醒"的时长（S2-04，03 §9/§11）：分钟数，默认 10；合法档位 5/10/15/30/60，
    /// 非法值由消费端回落 10（读取同样防非数字写坏）。
    public var reminderSnoozeMinutes: Int {
        get { (defaults.object(forKey: Key.reminderSnoozeMinutes) as? Int) ?? 10 }
        nonmutating set { defaults.set(newValue, forKey: Key.reminderSnoozeMinutes) }
    }
}
