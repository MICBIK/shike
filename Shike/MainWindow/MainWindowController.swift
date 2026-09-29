// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 主窗口左栏三入口（03 §16.2，S3.5-02）：选中态记忆在 @AppStorage。
enum MainSection: String, CaseIterable, Identifiable {
    case notes
    case todos
    case trash

    var id: Self { self }

    var title: String {
        switch self {
        case .notes: String(localized: .mainSectionNotes)
        case .todos: String(localized: .mainSectionTodos)
        case .trash: String(localized: .mainSectionTrash)
        }
    }

    var icon: String {
        switch self {
        case .notes: "note.text"
        case .todos: "checklist"
        case .trash: "trash"
        }
    }
}

/// 主窗口内容（03 §16，ADR-023：面板承载全部现有能力，主窗口只做增量）。
/// 左栏三入口 + 右侧内容区；S3.5-03/04/05 的视图随对应故事落地，
/// 未落地前显示诚实占位（不冒充完成）。
struct MainRootView: View {
    @AppStorage("main.section") private var section: MainSection = .notes

    var body: some View {
        NavigationSplitView {
            List(selection: $section) {
                ForEach(MainSection.allCases) { entry in
                    Label(entry.title, systemImage: entry.icon)
                        .tag(entry)
                }
            }
            .navigationSplitViewColumnWidth(180)
            .listStyle(.sidebar)
        } detail: {
            switch section {
            case .notes:
                placeholder(String(localized: .mainSectionNotes), icon: "note.text")
            case .todos:
                placeholder(String(localized: .mainSectionTodos), icon: "checklist")
            case .trash:
                placeholder(String(localized: .mainSectionTrash), icon: "trash")
            }
        }
        .frame(minWidth: 560, minHeight: 360)
    }

    /// 未实现视图的诚实占位（S3.5-02 AC 4）。
    private func placeholder(_ title: String, icon: String) -> some View {
        ContentUnavailableView(
            title,
            systemImage: icon,
            description: Text(String(localized: .mainComingSoon))
        )
    }
}

/// 主窗口单例（03 §16.1，S3.5-01）：右键菜单/设置打开；已有窗口前置聚焦，不重复开窗；
/// 尺寸与位置经 frameAutosave 记住；关闭只是关窗，拾刻继续驻留菜单栏（重开状态都在——
/// 控制器与窗口常驻，仅 orderOut/重前置）。
@MainActor
final class MainWindowController {
    private var window: NSWindow?

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "拾刻" // 应用名不翻译
        // 控制器强持有窗口：关掉默认的 close-即-release，避免 ARC 下过释放（打磨 P1）
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MainRootView())
        // 记住尺寸与位置：返回 false 表示没有已存 frame，居中放置
        if !window.setFrameAutosaveName("Main Window") {
            window.center()
        }
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
