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
    }

    /// 默认值注册表：与 Key 同处维护（计算属性，避免非 Sendable 静态共享状态）。
    private static var defaultValues: [String: Any] {
        [Key.backupKeepCount: 7]
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
}
