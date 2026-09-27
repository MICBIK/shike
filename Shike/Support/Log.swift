// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import os

/// 日志出口（conventions.md「日志」）：category 只取 app、data、backup、ui 之一。
/// 不记录便签和待办的内容；错误分类和错误代码用 .public，其余信息保持默认隐私级别。
enum Log {
    static let app = Logger(subsystem: "io.github.micbik.shike", category: "app")
    static let data = Logger(subsystem: "io.github.micbik.shike", category: "data")
    static let backup = Logger(subsystem: "io.github.micbik.shike", category: "backup")
    static let ui = Logger(subsystem: "io.github.micbik.shike", category: "ui")
}
