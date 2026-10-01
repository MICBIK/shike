// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData

/// 打磨轮回归（2026-10-01 冲刺夜）：
/// R4 面板行迟到防抖守卫——0.5 秒防抖窗内切行，迟到的防抖不得把其它行的
/// 文字写进刚编辑的行（此前无守卫，属静默数据污染；主窗口模型层一直有同款守卫）。
@MainActor
struct LateDebounceGuardTests {
    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = AppEnvironment(
            database: try AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-late-debounce-\(UUID().uuidString)", isDirectory: true)
        )
        return (environment, suiteName)
    }

    private func oneShotNotes(_ items: [NoteListItem]) -> AsyncThrowingStream<[NoteListItem], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    private func activeNotes(_ environment: AppEnvironment) async throws -> [NoteListItem] {
        var iterator = environment.noteRepository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    /// 轮询直到条件成立或超时（写路径是 fire-and-forget Task）。
    private func waitUntil(
        _ label: String,
        timeoutSeconds: Double = 2,
        _ condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if try await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("等待超时：\(label)")
    }

    @Test("R4 便签行：切行后迟到的防抖不落库（A 行保持切行时的收尾保存，不被 B 行文字污染）")
    func lateNoteDebounceDoesNotCrossWrite() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let noteA = try await environment.noteRepository.create(content: "A 原文")
        let noteB = try await environment.noteRepository.create(content: "B 原文")
        await model.runNotes(oneShotNotes([
            NoteListItem(note: noteA, isPinnedToDesktop: false),
            NoteListItem(note: noteB, isPinnedToDesktop: false),
        ]))

        // 编辑 A（防抖已排）→ 0.5 秒窗内切到 B：A 走收尾保存，编辑态换到 B
        model.beginNoteEditing(noteA.id, content: noteA.content)
        model.editingNoteText = "A 的新文字"
        model.beginNoteEditing(noteB.id, content: noteB.content)

        // 切行时的收尾保存落库
        try await waitUntil("A 行收尾保存") {
            try await self.activeNotes(environment).first(where: { $0.note.id == noteA.id })?.note.content == "A 的新文字"
        }

        // 迟到的防抖此刻到达：必须被守卫拒绝（无守卫会把"B 原文"写进 A）
        model.saveEditingNoteContentIfEditing(noteA.id)
        try await Task.sleep(for: .milliseconds(120))
        #expect(try await activeNotes(environment).first(where: { $0.note.id == noteA.id })?.note.content == "A 的新文字")
    }

    @Test("R4 便签行：仍在编辑的行照常受理防抖保存")
    func inFlightNoteDebounceStillSaves() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let note = try await environment.noteRepository.create(content: "原文")
        await model.runNotes(oneShotNotes([NoteListItem(note: note, isPinnedToDesktop: false)]))

        model.beginNoteEditing(note.id, content: note.content)
        model.editingNoteText = "防抖保存的文字"
        model.saveEditingNoteContentIfEditing(note.id)
        try await waitUntil("防抖保存落库") {
            try await self.activeNotes(environment).first?.note.content == "防抖保存的文字"
        }
    }

    @Test("R4 待办行：切行后迟到的防抖不落库；在编辑的行照常受理")
    func lateTodoDebounceGuard() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let todoA = try await environment.todoRepository.create(title: "A 原标题", due: nil)
        let todoB = try await environment.todoRepository.create(title: "B 原标题", due: nil)
        await model.runTodos(AsyncThrowingStream { continuation in
            continuation.yield([todoA, todoB])
            continuation.finish()
        })

        model.editingTodoID = todoA.id
        model.editingTodoText = "A 新标题"
        model.editingTodoID = todoB.id // 切行（等价 begin 之后的编辑态）
        model.editingTodoText = "B 新标题"

        // A 的迟到防抖：拒绝
        model.saveEditingTodoTitleIfEditing(todoA.id)
        // B 在编辑：受理
        model.saveEditingTodoTitleIfEditing(todoB.id)
        try await waitUntil("B 行防抖保存") {
            var iterator = environment.todoRepository.observeActive().makeAsyncIterator()
            let rows = try await iterator.next() ?? []
            return rows.first(where: { $0.id == todoB.id })?.title == "B 新标题"
        }
        try await Task.sleep(for: .milliseconds(120))
        var iterator = environment.todoRepository.observeActive().makeAsyncIterator()
        let rows = try await iterator.next() ?? []
        // A 行只应有编辑态切换前的旧标题（此用例未走收尾保存路径），不被"B 新标题"污染
        #expect(rows.first(where: { $0.id == todoA.id })?.title == "A 原标题")
    }
}
