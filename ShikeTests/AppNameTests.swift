// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Testing

@testable import Shike

/// Story 1.1 的验收：字符串目录生成的符号能读到 `app.name`。
/// 若 CI 的 Xcode 26.6 不支持符号生成，回退 `String(localized: "app.name")`（stack.md）。
struct AppNameTests {
    @Test("通过生成的符号读取 app.name，得到「拾刻」")
    func readsAppNameThroughGeneratedSymbol() {
        #expect(String(localized: .appName) == "拾刻")
    }
}
