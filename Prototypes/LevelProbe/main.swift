// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 层级压盖对照实验 v5：orderBack 对 [canJoinAllSpaces, .stationary] 的
// nonactivatingPanel 是否有效（ADR-029 让位逻辑的关键原语，2026-09-29）。

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

// 还原拾刻：borderless + nonactivating + joinAllSpaces+stationary+noCycle，level=normal
let panel = CardPanel(
    contentRect: NSRect(x: 200, y: 400, width: 300, height: 200),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered, defer: false
)
panel.level = .normal
panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
panel.backgroundColor = .systemRed
panel.isOpaque = true
panel.orderFrontRegardless()

// 场景 1：panel 在前（模拟 level setter 放到层内最前）→ TextEdit 激活 → 验证 orderBack
func dump(_ tag: String) {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return }
    print("=== \(tag) ===")
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        guard owner == "level-probe" || owner == "TextEdit" || owner == "文本编辑" else { continue }
        let bd = w[kCGWindowBounds as String] as? [String: NSNumber]
        print("x=\(bd?["X"]?.intValue ?? -1) y=\(bd?["Y"]?.intValue ?? -1) w=\(bd?["Width"]?.intValue ?? -1) owner=\(owner) layer=\(w[kCGWindowLayer as String] as? Int ?? -999)")
    }
}

NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/TextEdit.app"))
DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    NSWorkspace.shared.runningApplications
        .first { $0.bundleURL?.path == "/System/Applications/TextEdit.app" }?
        .activate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
        dump("TextEdit 激活后（panel 应已被压住=正常）")
        // 模拟"用户把面板提到层内最前再 orderBack"（ADR-029 的让位路径）
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dump("orderFrontRegardless 后（panel 应在最前）")
            panel.orderBack(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dump("orderBack 后（panel 若仍在最前=orderBack 对此窗口无效，真凶）")
                exit(0)
            }
        }
    }
}

RunLoop.main.run()
