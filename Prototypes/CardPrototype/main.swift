// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// S3-00 技术验证原型（ADR-025 证据采集，阶段 3）：
// 独立可执行，不依赖 Shike 工程与数据目录。用脚本化时序采集四组结论的机器证据：
//   1) 唤回：全局 mouseMoved 监听能否安装（无 TCC）+ NSEvent.mouseLocation 轮询单价；
//   2) 层级：floating / normal / desktop 三档 level 设置与回读；
//   3) 空间：canJoinAllSpaces / moveToActiveSpace / fullScreenAuxiliary 组合回读；
//   4) 焦点：无 .activatable 的 borderless 窗口 makeKey 后 firstResponder 与文字插入。
// 运行：CardPrototype [--duration 秒]（默认 10；期间可用 screencapture 截屏看卡片）。

import AppKit

// MARK: - 卡片窗口：borderless、不激活应用、可按需成为 key

final class CardWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

final class CardView: NSView {
    let label: String
    private var tracking: NSTrackingArea?

    init(label: String, color: NSColor) {
        self.label = label
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = color.cgColor
        layer?.cornerRadius = 10
        layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
    }

    required init?(coder: NSCoder) { fatalError("原型不支持") }

    override func layout() {
        super.layout()
        if tracking == nil {
            tracking = NSTrackingArea(
                rect: bounds,
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self
            )
            addTrackingArea(tracking!)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.labelColor.set()
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.textColor,
        ]
        (label as NSString).draw(at: NSPoint(x: 14, y: bounds.height - 34), withAttributes: attrs)
    }
}

// MARK: - 证据输出

func emit(_ key: String, _ value: String) {
    print("EVIDENCE\t\(key)\t\(value)")
    fflush(stdout)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

var duration = 10.0
if let idx = CommandLine.arguments.firstIndex(of: "--duration"), idx + 1 < CommandLine.arguments.count {
    duration = Double(CommandLine.arguments[idx + 1]) ?? 10.0
}

let screen = NSScreen.main!
let visible = screen.visibleFrame

// MARK: 1) 三张卡片，三档层级

func makeCard(_ title: String, rect: NSRect, color: NSColor) -> CardWindow {
    let window = CardWindow(
        contentRect: rect,
        styleMask: [.borderless],
        backing: .buffered,
        defer: false
    )
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.contentView = CardView(label: title, color: color)
    window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    return window
}

// kCGDesktopWindowLevelKey = 2（宏在 Swift 不可见，用原始 key 值取级别）
let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(CGWindowLevelKey(rawValue: 2)!)))
let cards: [(String, CardWindow, NSWindow.Level)] = [
    ("原型·浮在最上层 floating", makeCard("原型·浮在最上层 floating", rect: NSRect(x: visible.midX - 300, y: visible.midY + 10, width: 240, height: 180), color: NSColor(red: 1.0, green: 0.96, blue: 0.75, alpha: 0.97)), .floating),
    ("原型·普通窗口 normal", makeCard("原型·普通窗口 normal", rect: NSRect(x: visible.midX, y: visible.midY + 10, width: 240, height: 180), color: NSColor(red: 0.78, green: 0.92, blue: 0.86, alpha: 0.97)), .normal),
    ("原型·贴桌面层 desktop", makeCard("原型·贴桌面层 desktop", rect: NSRect(x: visible.midX - 150, y: visible.midY - 190, width: 240, height: 180), color: NSColor(red: 0.86, green: 0.88, blue: 0.95, alpha: 0.97)), desktopLevel),
]

for (title, window, level) in cards {
    window.level = level
    window.makeKeyAndOrderFront(nil)
    emit("level.\(title)", "set=\(level.rawValue) readback=\(window.level.rawValue) visible=\(window.isVisible)")
}

// MARK: 2) 空间行为组合回读

let spaceCombos: [(String, NSWindow.CollectionBehavior)] = [
    ("canJoinAllSpaces+fullScreenAuxiliary", [.canJoinAllSpaces, .fullScreenAuxiliary]),
    ("moveToActiveSpace", [.moveToActiveSpace]),
    ("canJoinAllSpaces", [.canJoinAllSpaces]),
]
for (name, behavior) in spaceCombos {
    cards[0].1.collectionBehavior = behavior
    emit("space.\(name)", "readback=\(cards[0].1.collectionBehavior.rawValue) want=\(behavior.rawValue)")
}

// MARK: 3) 隐藏与穿透参数回读

let hiddenCard = cards[2].1
hiddenCard.alphaValue = 0.2
hiddenCard.ignoresMouseEvents = true
emit(
    "hide.params",
    "alpha=\(hiddenCard.alphaValue) ignoresMouse=\(hiddenCard.ignoresMouseEvents)"
)

// MARK: 4) 焦点：无 .activatable（borderless 本就不激活）能否 key + 插入文字

let focusCard = cards[0].1
let textView = NSTextView(frame: NSRect(x: 8, y: 8, width: 200, height: 120))
textView.string = ""
focusCard.contentView?.addSubview(textView)
app.activate()
focusCard.makeKey()
focusCard.makeFirstResponder(textView)
textView.insertText("焦点验证")
let responderIsText = focusCard.firstResponder is NSTextView
emit(
    "focus.borderless",
    "firstResponderIsTextView=\(responderIsText) isKey=\(focusCard.isKeyWindow) text=\(textView.string)"
)

// MARK: 4b) NSPanel(.nonactivatingPanel)：点击不激活应用仍能成为 key 的标准路线

let panel = NSPanel(
    contentRect: NSRect(x: visible.midX + 10, y: visible.midY - 190, width: 240, height: 180),
    styleMask: [.borderless, .nonactivatingPanel],
    backing: .buffered,
    defer: false
)
panel.isOpaque = false
panel.backgroundColor = .clear
panel.hasShadow = true
panel.level = .floating
panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
let panelView = CardView(label: "原型·NSPanel 非激活面板", color: NSColor(red: 1.0, green: 0.87, blue: 0.87, alpha: 0.97))
panel.contentView = panelView
let panelText = NSTextView(frame: NSRect(x: 8, y: 8, width: 200, height: 120))
panelText.string = ""
panelView.addSubview(panelText)
panel.makeKeyAndOrderFront(nil)
panel.makeFirstResponder(panelText)
panelText.insertText("面板焦点验证")
emit(
    "focus.nonactivatingPanel",
    "firstResponderIsTextView=\(panel.firstResponder is NSTextView) isKey=\(panel.isKeyWindow) canBecomeKey=\(panel.canBecomeKey) text=\(panelText.string)"
)

// MARK: 5) 唤回两条路线

// 路线 A：全局 mouseMoved 监听——能否安装（权限证据；真实投递需 L3 真人移动鼠标）
var globalMoveCount = 0
var monitorInstalled = false
if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .otherMouseDragged]) { _ in
    globalMoveCount += 1
} {
    monitorInstalled = true
    // 保存以延长生命周期到计时结束
    objc_setAssociatedObject(app, "protoMonitor", monitor, .OBJC_ASSOCIATION_RETAIN)
}
emit("recall.globalMonitor", "installed=\(monitorInstalled)（true=无 TCC 也能安装；投递计数见 recall.globalMoveCount）")

// 路线 B：轮询 NSEvent.mouseLocation 单价（30Hz 常驻的成本估算）
let reads = 100_000
let pollStart = Date()
var locations = 0
for _ in 0..<reads {
    _ = NSEvent.mouseLocation
    locations += 1
}
let pollElapsed = Date().timeIntervalSince(pollStart)
emit(
    "recall.pollCost",
    "reads=\(locations) totalMs=\(String(format: "%.2f", pollElapsed * 1000)) usPerRead=\(String(format: "%.3f", pollElapsed * 1_000_000 / Double(reads))) est30HzCpuMsPerSec=\(String(format: "%.3f", pollElapsed * 1_000_000 / Double(reads) * 30 / 1_000))"
)

// MARK: 常驻 duration 秒供截屏与真人移动鼠标（路线 A 的投递计数在退出前输出）

let deadline = Date().addingTimeInterval(duration)
while Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
}
emit("recall.globalMoveCount", "\(globalMoveCount)")
emit("done", "1")
exit(0)
