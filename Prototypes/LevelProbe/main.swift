// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 层级压盖对照实验 v4（矩阵）：跨 app 激活下，哪个配置因素让 normal 层的
// panel 压在激活 app 的普通窗口之上。z 序是全局序，无需窗口相交（2026-09-29）。

import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

final class KeyPanel: NSPanel {
    let canKey: Bool
    init(canKey: Bool, styleMask: NSWindow.StyleMask, x: CGFloat) {
        self.canKey = canKey
        super.init(
            contentRect: NSRect(x: x, y: 640, width: 280, height: 150),
            styleMask: styleMask, backing: .buffered, defer: false
        )
    }
    override var canBecomeKey: Bool { canKey }
}

// A：拾刻当前配置（nonactivating + joinAll+stationary+noCycle + canBecomeKey=false）
let a = KeyPanel(canKey: false, styleMask: [.borderless, .nonactivatingPanel], x: 40)
a.level = .normal; a.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
a.backgroundColor = .systemRed; a.isOpaque = true
// B：nonactivating + 无 collectionBehavior
let b = KeyPanel(canKey: false, styleMask: [.borderless, .nonactivatingPanel], x: 340)
b.level = .normal; b.collectionBehavior = []
b.backgroundColor = .systemGreen; b.isOpaque = true
// C：nonactivating + joinAll+stationary+noCycle + canBecomeKey=true（唯一变量：canKey）
let c = KeyPanel(canKey: true, styleMask: [.borderless, .nonactivatingPanel], x: 640)
c.level = .normal; c.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
c.backgroundColor = .systemBlue; c.isOpaque = true
// D：无 nonactivatingPanel（普通 borderless NSWindow）+ 同 A 的 cb（变量：styleMask）
let d = KeyPanel(canKey: false, styleMask: [.borderless], x: 940)
d.level = .normal; d.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
d.backgroundColor = .systemOrange; d.isOpaque = true

for p in [a, b, c, d] { p.orderFrontRegardless() }

NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/TextEdit.app"))

func dump() {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else { return }
    print("=== front-to-back（TextEdit 激活后；靠前=在上层）===")
    for w in list {
        let owner = w[kCGWindowOwnerName as String] as? String ?? ""
        guard owner == "level-probe" || owner == "TextEdit" || owner == "文本编辑" else { continue }
        let bd = w[kCGWindowBounds as String] as? [String: NSNumber]
        let x = bd?["X"]?.intValue ?? -1
        let label: String
        if owner != "level-probe" { label = "TextEdit" }
        else if x < 100 { label = "A nonact+joinAll+canKeyNO(拾刻当前)" }
        else if x < 400 { label = "B nonact+nocb" }
        else if x < 700 { label = "C nonact+joinAll+canKeyYES" }
        else { label = "D 无nonact+joinAll" }
        print("x=\(x) => \(label)")
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
    NSWorkspace.shared.runningApplications
        .first { $0.bundleURL?.path == "/System/Applications/TextEdit.app" }?
        .activate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        dump()
        exit(0)
    }
}

RunLoop.main.run()
