// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit

// AppDelegate 由全局常量强持有：NSApplication.delegate 是弱引用（app-shell.md）。
let appDelegate = AppDelegate()

NSApplication.shared.delegate = appDelegate
NSApplication.shared.run()
