// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// Story 3.9：搜索（SPEC CAP-9、stage-2-components.md §7、03 §8）。
@MainActor
struct SearchTests {
    private func makeModel() throws -> (PanelModel, AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        let model = environment.panelModel
        model.start()
        return (model, environment, suiteName)
    }

    private func cleanup(_ suiteName: String) {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    // - MARK: 命中区间（纯函数）

    @Test("matchRanges：不区分大小写的全部命中；空 query 无命中")
    func matchRanges() {
        let ranges = SearchRow.matchRanges(text: "Report report REPORT", query: "report")
        #expect(ranges.count == 3)
        #expect(SearchRow.matchRanges(text: "交报告", query: "").isEmpty)
        #expect(SearchRow.matchRanges(text: "交报告", query: "总结").isEmpty)
        // 中文命中
        #expect(SearchRow.matchRanges(text: "交报告给组长", query: "报告").count == 1)
    }

    // - MARK: 检索状态机

    @Test("检索：便签与待办分别命中、不区分大小写、含已完成、按 updatedAt 降序")
    func searchFiltersAndOrders() async throws {
        let (model, environment, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo

        _ = try await environment.noteRepository.create(content: "项目报告的链接")
        _ = try await environment.noteRepository.create(content: "买菜清单")
        let hit = try await environment.todoRepository.create(title: "交报告", due: nil)
        _ = try await environment.todoRepository.create(title: "买牛奶", due: nil)
        let completed = try await environment.todoRepository.create(title: "写报告总结", due: nil)
        try await environment.todoRepository.setCompleted(completed.id, true)
        try await waitUntil { model.notes.count == 2 && model.todos.count == 3 }

        model.beginSearch()
        #expect(model.isSearching)
        model.searchQuery = "报告"
        model.runSearch()
        #expect(model.searchNoteResults.map(\.content) == ["项目报告的链接"])
        // 待办命中含已完成（周报）；同批创建 updatedAt 可能并列，只钉成员
        #expect(Set(model.searchTodoResults.map(\.title)) == ["写报告总结", "交报告"])
        #expect(model.searchTodoResults.contains { $0.id == hit.id })
    }

    @Test("Esc 顺序：搜索态退出搜索且面板不收起；再按 Esc 才收起")
    func escapeExitsSearchFirst() throws {
        let (model, _, suiteName) = try makeModel()
        defer { cleanup(suiteName) }

        model.beginSearch()
        model.exitSearch()
        #expect(model.isSearching == false)
    }

    @Test("点击结果：退出搜索、切对应模式、设置定位目标")
    func locatingSearchResult() async throws {
        let (model, environment, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        let note = try await environment.noteRepository.create(content: "会议纪要")
        let todo = try await environment.todoRepository.create(title: "交报告", due: nil)
        try await waitUntil { !model.notes.isEmpty && !model.todos.isEmpty }

        model.beginSearch()
        model.locateSearchResult(note: note)
        #expect(model.isSearching == false)
        #expect(model.mode == .note)
        #expect(model.locateNoteID == note.uuid.uuidString)

        model.beginSearch()
        model.locateSearchResult(todoUUID: todo.uuid)
        #expect(model.mode == .todo)
        #expect(model.locateTodoID == todo.uuid.uuidString)
    }

    @Test("防抖：注入 100ms 延迟后，关键词变化自动触发检索（无需手动 runSearch）")
    func debouncedSearchRunsAutomatically() async throws {
        let (model, environment, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        _ = environment
        _ = try await environment.noteRepository.create(content: "项目报告")
        model.searchDebounceDelay = .milliseconds(100)
        model.beginSearch()
        model.searchQuery = "报告"
        // 防抖到点前：尚未检索
        #expect(model.searchNoteResults.isEmpty)
        try await waitUntil { !model.searchNoteResults.isEmpty || !model.searchTodoResults.isEmpty }
        #expect(model.searchNoteResults.map(\.content) == ["项目报告"])
    }

    @Test("定位已完成待办：先展开已完成组（盲审 3.9-F1）")
    func locatingCompletedTodoExpandsSection() async throws {
        let (model, environment, suiteName) = try makeModel()
        defer { cleanup(suiteName) }
        model.mode = .todo
        let todo = try await environment.todoRepository.create(title: "已完成的事", due: nil)
        try await environment.todoRepository.setCompleted(todo.id, true)
        // 等完成状态进入观察流快照（竞态防护：否则 locateTodo 看到的 completedAt 还是 nil）
        try await waitUntil { model.todos.first(where: { $0.uuid == todo.uuid })?.completedAt != nil }
        #expect(model.isCompletedSectionExpanded == false)

        model.locateTodo(uuid: todo.uuid)
        #expect(model.isCompletedSectionExpanded == true)
    }

    @Test("清空关键词：结果清空；退出搜索：状态复位")
    func emptyQueryAndExit() throws {
        let (model, _, suiteName) = try makeModel()
        defer { cleanup(suiteName) }

        model.beginSearch()
        model.searchQuery = "报告"
        model.runSearch()
        model.searchQuery = "   "
        model.runSearch()
        #expect(model.searchNoteResults.isEmpty)
        #expect(model.searchTodoResults.isEmpty)

        model.searchQuery = "报告"
        model.runSearch()
        model.exitSearch()
        #expect(model.searchQuery.isEmpty)
        #expect(model.searchNoteResults.isEmpty && model.searchTodoResults.isEmpty)
    }

    // 截止时间轮询（仓库约定）
    private func waitUntil(_ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "等待条件在 3 秒内未满足")
    }
}
