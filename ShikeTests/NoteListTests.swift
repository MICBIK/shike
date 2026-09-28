// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 2.6：便签列表与编辑（app-shell.md「组件契约」、03 §5、NFR17）。
@MainActor
struct NoteListTests {
    private let timeZone = TimeZone(identifier: "Asia/Shanghai")!

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: components)!
    }

    // - MARK: 相对时间（纯函数）

    @Test("RelativeTimeFormatter：边界与五种格式（03 §5）")
    func relativeTimeFormats() {
        let now = date(2026, 9, 23, 14, 20)
        // 刚刚：不足 1 分钟（含 59 秒边界）
        #expect(RelativeTimeFormatter.format(date(2026, 9, 23, 14, 20), now: now, timeZone: timeZone) == "刚刚")
        #expect(RelativeTimeFormatter.format(date(2026, 9, 23, 14, 19, 1), now: now, timeZone: timeZone) == "刚刚")
        // 分钟：1～59 分钟前
        #expect(RelativeTimeFormatter.format(date(2026, 9, 23, 13, 50), now: now, timeZone: timeZone) == "30 分钟前")
        #expect(RelativeTimeFormatter.format(date(2026, 9, 23, 13, 21), now: now, timeZone: timeZone) == "59 分钟前")
        // 60 分钟落入"今天 HH:mm"
        #expect(RelativeTimeFormatter.format(date(2026, 9, 23, 13, 20), now: now, timeZone: timeZone) == "今天 13:20")
        #expect(RelativeTimeFormatter.format(date(2026, 9, 23, 9, 5), now: now, timeZone: timeZone) == "今天 09:05")
        #expect(RelativeTimeFormatter.format(date(2026, 9, 22, 23, 50), now: now, timeZone: timeZone) == "昨天")
        #expect(RelativeTimeFormatter.format(date(2026, 9, 20, 8, 0), now: now, timeZone: timeZone) == "9月20日")
        #expect(RelativeTimeFormatter.format(date(2026, 1, 2, 8, 0), now: now, timeZone: timeZone) == "1月2日") // 跨年不显示年份
    }

    // - MARK: 列表行为（内存库）

    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        return (environment, suiteName)
    }

    @Test("分组：置顶组在前、空置顶组不显示；分组随置顶变化")
    func groupingFollowsPinState() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let a = try await environment.noteRepository.create(content: "甲")
        let b = try await environment.noteRepository.create(content: "乙")
        try await waitUntilList(model) { $0.notes.count == 2 }

        #expect(model.pinnedNotes.isEmpty)
        #expect(model.unpinnedNotes.count == 2)

        try await environment.noteRepository.setPinned(b.id, true)
        try await waitUntilList(model) { $0.pinnedNotes.count == 1 }
        #expect(model.pinnedNotes.map { $0.note.content } == ["乙"])
        #expect(model.unpinnedNotes.map { $0.note.content } == ["甲"])

        // 置顶组按置顶时间降序：后置顶的在前（03 §5）；时间戳精度毫秒，先让出间隔
        try await Task.sleep(for: .milliseconds(10))
        try await environment.noteRepository.setPinned(a.id, true)
        try await waitUntilList(model) { $0.pinnedNotes.count == 2 }
        #expect(model.pinnedNotes.map { $0.note.content } == ["甲", "乙"])

        try await environment.noteRepository.setPinned(b.id, false)
        try await waitUntilList(model) { $0.pinnedNotes.count == 1 && $0.unpinnedNotes.count == 1 }
        #expect(model.pinnedNotes.map { $0.note.content } == ["甲"])
    }

    @Test("原位编辑：endEditingIfNeeded 保存改动并退出编辑态；内容未变不写库")
    func inlineEditSavesViaEndEditing() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "原始内容")
        try await waitUntilList(model) { !$0.notes.isEmpty }

        // 无编辑态：Esc 落到收起面板
        #expect(model.endEditingIfNeeded() == false)

        // 进入编辑、改文字、Esc 结束（第一级消费，保存）
        model.editingNoteID = note.id
        model.editingNoteText = "改过的内容"
        #expect(model.endEditingIfNeeded() == true)
        #expect(model.editingNoteID == nil)
        try await waitUntilList(model) { $0.notes[0].note.content == "改过的内容" }

        // 内容未变：endEditing 不写库（updatedAt 不变）
        model.editingNoteID = note.id
        model.editingNoteText = "改过的内容"
        let updatedAtBefore = model.notes[0].note.updatedAt
        #expect(model.endEditingIfNeeded() == true)
        try await Task.sleep(for: .milliseconds(150))
        #expect(model.notes[0].note.updatedAt == updatedAtBefore)
    }

    @Test("编辑清空视为删除（03 §5/§7；撤销条在 2.8 接入）")
    func clearingEditDeletes() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "将被清空")
        try await waitUntilList(model) { !$0.notes.isEmpty }

        await model.saveNoteContent(note.id, "   ")
        try await waitUntilList(model) { $0.notes.isEmpty }
    }

    @Test("置顶与删除动作：setNotePinned/deleteNote 走仓储并反映到列表")
    func pinAndDeleteActions() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        model.start()

        let note = try await environment.noteRepository.create(content: "待删除")
        try await waitUntilList(model) { !$0.notes.isEmpty }

        await model.setNotePinned(note.id, true)
        try await waitUntilList(model) { !$0.pinnedNotes.isEmpty }

        await model.deleteNote(note.id)
        try await waitUntilList(model) { $0.notes.isEmpty }
    }

    private func waitUntilList(
        _ model: PanelModel,
        timeoutSeconds: Double = 2,
        _ condition: (PanelModel) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition(model) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if condition(model) { return }
        let snapshot = model.notes.map { "\($0.note.content)|pinned=\($0.note.pinnedAt != nil)" }.joined(separator: ", ")
        Issue.record("等待列表条件超时：notes=[\(snapshot)]")
    }
}
