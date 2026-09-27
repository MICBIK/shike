// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Observation
import ShikeData

/// 面板状态（app-shell.md「组件契约」）：模式、两个列表的数据与提示条。
/// 观察流的消费（start）与提示条由 Story 1.10 接入。
@MainActor
@Observable
final class PanelModel {
    /// 顶栏分段控件的模式（03 §3）；默认便签，重启回到便签，不写入偏好设置。
    enum Mode: String, CaseIterable, Sendable {
        case note
        case todo
    }

    var mode: Mode = .note

    private(set) var notes: [NoteListItem] = []
    private(set) var todos: [Todo] = []
}
