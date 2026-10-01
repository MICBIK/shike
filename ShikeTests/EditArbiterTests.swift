// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData

/// 同一条便签的三面编辑互斥（W4）：面板/主窗口/卡片同时编辑同一条时，
/// "后来者拿走"——新面 claim 时旧面收尾（触发各自保存语义）；per-note 粒度
/// 互不干扰；探活过期的条目自愈（不误伤）。
@MainActor
struct EditArbiterTests {
    /// 记录闭包调用的盒子（闭包里不能改捕获的局部 var，用类装）。
    private final class Log {
        var calls: [String] = []
        func record(_ name: String) { calls.append(name) }
    }

    @Test("仲裁：后来者拿走——旧 owner 的结束闭包被调并返回在编文字，新 owner 授权")
    func laterClaimEvictsPreviousOwner() {
        let arbiter = EditArbiter()
        let log = Log()
        let id = Note.ID(rawValue: 1)

        arbiter.claim(noteID: id, owner: .panel, isEditing: { true }, endEditing: { _ in log.record("panel.end"); return "面板在编文字" })
        #expect(arbiter.currentOwner(noteID: id) == .panel)

        let evicted = arbiter.claim(noteID: id, owner: .mainWindow, isEditing: { true }, endEditing: { _ in log.record("main.end"); return nil })
        #expect(arbiter.currentOwner(noteID: id) == .mainWindow)
        #expect(log.calls == ["panel.end"])
        #expect(evicted == "面板在编文字") // 接手面必须用它播种（打磨 R1）
    }

    @Test("仲裁：探活过期自愈——旧面已不在编辑时不误触发其结束闭包，返回 nil")
    func staleEntryIsSilentlyReplaced() {
        let arbiter = EditArbiter()
        let log = Log()
        let id = Note.ID(rawValue: 1)

        // 面板编辑过第 1 条但已收尾（探活 false 的过期条目留在表里）
        arbiter.claim(noteID: id, owner: .panel, isEditing: { false }, endEditing: { _ in log.record("panel.end"); return "不该被读到的字" })
        let evicted = arbiter.claim(noteID: id, owner: .card, isEditing: { true }, endEditing: { _ in log.record("card.end"); return nil })
        #expect(log.calls.isEmpty)
        #expect(evicted == nil)
        #expect(arbiter.currentOwner(noteID: id) == .card)
    }

    @Test("仲裁：per-note 粒度——编辑第 2 条不打扰第 1 条的在编状态")
    func perNoteGranularity() {
        let arbiter = EditArbiter()
        let log = Log()
        let first = Note.ID(rawValue: 1)
        let second = Note.ID(rawValue: 2)

        arbiter.claim(noteID: first, owner: .panel, isEditing: { true }, endEditing: { _ in log.record("panel.end"); return nil })
        arbiter.claim(noteID: second, owner: .mainWindow, isEditing: { true }, endEditing: { _ in log.record("main.end"); return nil })
        #expect(log.calls.isEmpty) // 不同便签互不干扰
        #expect(arbiter.currentOwner(noteID: first) == .panel)
        #expect(arbiter.currentOwner(noteID: second) == .mainWindow)
    }

    @Test("仲裁：同面重复 claim 不触发自己的结束闭包")
    func sameFaceReclaimIsNoop() {
        let arbiter = EditArbiter()
        let log = Log()
        let id = Note.ID(rawValue: 1)

        arbiter.claim(noteID: id, owner: .panel, isEditing: { true }, endEditing: { _ in log.record("panel.end"); return nil })
        arbiter.claim(noteID: id, owner: .panel, isEditing: { true }, endEditing: { _ in log.record("panel.end"); return nil })
        #expect(log.calls.isEmpty)
        #expect(arbiter.currentOwner(noteID: id) == .panel)
    }

    @Test("接线冒烟：面板在编辑 → 主窗口 beginEditing 同一条 → 面板编辑态已收")
    func mainWindowTakesOverFromPanel() async throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-arbiter-\(UUID().uuidString)", isDirectory: true)
        )
        let controller = MainWindowController(environment: environment)
        let panelModel = environment.panelModel
        let note = try await environment.noteRepository.create(content: "互斥冒烟")
        // 播种两份快照（面板与主窗口各自的行渲染源）
        let item = NoteListItem(note: note, isPinnedToDesktop: false)
        await panelModel.runNotes(AsyncThrowingStream { $0.yield([item]); $0.finish() })
        await controller.notesModel.runNotes(AsyncThrowingStream { $0.yield([item]); $0.finish() })

        // 面板进入编辑 → 主窗口拿走
        panelModel.beginNoteEditing(note.id, content: note.content)
        #expect(panelModel.editingNoteID == note.id)
        controller.notesModel.beginEditing(note.id)
        #expect(panelModel.editingNoteID == nil) // 面板编辑态已收（保存语义在 W1 用例覆盖）
        #expect(controller.notesModel.editingNoteID == note.id)

        // 反向：面板再拿走 → 主窗口编辑态已收
        panelModel.beginNoteEditing(note.id, content: note.content)
        #expect(controller.notesModel.editingNoteID == nil)
        #expect(panelModel.editingNoteID == note.id)
    }

    @Test("接线：接交播种新鲜（打磨 R1）——面板未保存的编辑被主窗口拿走时文字不回退")
    func takeoverSeedsUnsavedText() async throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-arbiter-\(UUID().uuidString)", isDirectory: true)
        )
        let controller = MainWindowController(environment: environment)
        let panelModel = environment.panelModel
        let note = try await environment.noteRepository.create(content: "原文")
        let item = NoteListItem(note: note, isPinnedToDesktop: false)
        await panelModel.runNotes(AsyncThrowingStream { $0.yield([item]); $0.finish() })
        await controller.notesModel.runNotes(AsyncThrowingStream { $0.yield([item]); $0.finish() })

        // 面板改了字尚未保存（行快照仍是"原文"）→ 主窗口拿走：必须拿到"新文字"
        panelModel.beginNoteEditing(note.id, content: note.content)
        panelModel.editingNoteText = "面板刚打的字"
        controller.notesModel.beginEditing(note.id)
        #expect(controller.notesModel.editingNoteText == "面板刚打的字")

        // 反向：主窗口改字尚未保存 → 面板拿走：同样不回退
        controller.notesModel.editingNoteText = "主窗口刚打的字"
        panelModel.beginNoteEditing(note.id, content: note.content)
        #expect(panelModel.editingNoteText == "主窗口刚打的字")
    }

    @Test("接线冒烟：环境级单份——面板/主窗口/卡片共享同一仲裁器")
    func environmentWiresSingleArbiter() throws {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-arbiter-\(UUID().uuidString)", isDirectory: true)
        )
        let controller = MainWindowController(environment: environment)
        // 同一实例：面板 claim 后主窗口经同表可见（currentOwner 是面板）——
        // 用行为验证同一性：面板 claim → 主窗口 claim → 面板被收尾（上面用例已验）。
        // 这里直接断言注入的是同一实例（=== 身份比较）。
        #expect(environment.panelModel.editArbiter === environment.editArbiter)
        #expect(controller.notesModel.editArbiter === environment.editArbiter)
    }
}
