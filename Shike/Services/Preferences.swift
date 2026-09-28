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
    }

    /// 默认值注册表：与 Key 同处维护（计算属性，避免非 Sendable 静态共享状态）。
    private static var defaultValues: [String: Any] {
        [Key.backupKeepCount: 7, Key.panelSize: "360.0x520.0"]
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
}
