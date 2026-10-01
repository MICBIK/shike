// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Note/NoteListItem 的 memberwise init 是 internal（包内约定）

/// S3.5-03：主窗口便签模型（观察流分组/搜索/动作转发/流收尾）。
/// 环境同 PinCardFlowTests：AppEnvironment 组装真实仓储（内存库）+ 独立 UserDefaults suite。
/// 断言策略：写后新建观察流取首帧（首帧即当前全量），包成一次性流驱动 runNotes（确定性）；
/// start() 的非结构化任务用主 actor 轮询。
@MainActor
struct MainNotesModelTests {
    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-main-notes-\(UUID().uuidString)", isDirectory: true)
        )
        return (environment, suiteName)
    }

    /// 构造 NoteListItem（派生逻辑测试用，pinnedAt/updatedAt 显式给定不依赖时钟）。
    private func item(
        _ id: Int64,
        content: String,
        pinnedAt: Date? = nil,
        updatedAt: Date
    ) -> NoteListItem {
        NoteListItem(
            note: Note(
                id: Note.ID(rawValue: id),
                uuid: UUID(),
                content: content,
                pinnedAt: pinnedAt,
                createdAt: updatedAt,
                updatedAt: updatedAt,
                deletedAt: nil
            ),
            isPinnedToDesktop: false
        )
    }

    /// 写操作落库后新建观察流，取首帧（观察流首帧即当前全量）。
    private func firstFrame(_ environment: AppEnvironment) async throws -> [NoteListItem] {
        var iterator = environment.noteRepository.observeActive().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    /// 把快照包成一次性流：runNotes 消费完即返回，测试确定性收尾。
    private func oneShot(_ items: [NoteListItem]) -> AsyncThrowingStream<[NoteListItem], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 立即以读取失败收尾的流（观察流异常结束形态）。
    private func failingStream() -> AsyncThrowingStream<[NoteListItem], any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ShikeDataError.readFailed(.ioError))
        }
    }

    /// 主 actor 轮询直到条件成立或超时（start() 的任务没有可等待的句柄）。
    private func waitUntil(timeout: TimeInterval = 2, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("分组：置顶组只含置顶（按置顶时间降序），全部组含全部（含置顶，仓储序）")
    func groupingPinnedAndAll() async throws {
        // 用构造的快照驱动派生逻辑：pinnedAt 显式给定互不相同，排序断言不依赖
        // 真实时钟的毫秒并列，也不依赖 sort 的稳定性契约。
        let model = MainNotesModel(observeNotes: { AsyncThrowingStream { $0.finish() } })
        let t1 = Date(timeIntervalSince1970: 1_000)
        let t2 = Date(timeIntervalSince1970: 2_000)
        let t3 = Date(timeIntervalSince1970: 3_000)
        let first = item(1, content: "早的便签", pinnedAt: t1, updatedAt: t1)
        let second = item(2, content: "晚的便签", pinnedAt: t2, updatedAt: t2)
        let third = item(3, content: "未置顶", updatedAt: t3)

        // 仓储序（updatedAt 降序）：晚的在前
        await model.runNotes(oneShot([third, second, first]))

        #expect(model.notes.count == 3)
        #expect(model.allNotes.map(\.id) == [third.id, second.id, first.id])
        // 置顶组按置顶时间降序：晚置顶在前，未置顶不出现
        #expect(model.pinnedNotes.map(\.id) == [second.id, first.id])

        // 搜索不命中置顶便签：置顶组与全部组都为空（两组派生自同一过滤）
        model.searchText = "不命中"
        #expect(model.pinnedNotes.isEmpty)
        #expect(model.allNotes.isEmpty)
        model.searchText = ""
        #expect(model.pinnedNotes.map(\.id) == [second.id, first.id])
    }

    @Test("搜索：大小写不敏感 contains、首尾空白裁剪、不命中不清快照、清空恢复")
    func searchFiltersCaseInsensitively() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        _ = try await environment.noteRepository.create(content: "Hello 世界")
        _ = try await environment.noteRepository.create(content: "别的便签")

        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        await model.runNotes(oneShot(try await firstFrame(environment)))

        model.searchText = "hello"
        #expect(model.allNotes.count == 1)
        #expect(model.allNotes.first?.note.content == "Hello 世界")
        #expect(model.pinnedNotes.isEmpty)

        // 首尾空白裁剪后仍命中（且大小写不敏感）
        model.searchText = "  HELLO  "
        #expect(model.allNotes.count == 1)

        // 纯空白关键词视为不过滤（返回全量）
        model.searchText = "   "
        #expect(model.allNotes.count == 2)

        // 不命中：过滤为空，原始快照保留
        model.searchText = "不存在的关键词"
        #expect(model.allNotes.isEmpty)
        #expect(model.notes.count == 2)

        // 清空恢复全量
        model.searchText = ""
        #expect(model.allNotes.count == 2)
        #expect(model.pinnedNotes.isEmpty)
    }

    @Test("saveContent：防抖合并转发（只转发最后一次），非编辑中的行不受理")
    func saveContentDebouncesAndForwards() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        var saved: [(id: Note.ID, text: String)] = []
        model.saveNoteContent = { id, text in saved.append((id, text)) }
        model.saveDebounceDelay = .milliseconds(20)

        let id = Note.ID(rawValue: 1)
        model.beginEditing(id)
        model.editingNoteText = "第一次"
        model.saveContent(id, model.editingNoteText)
        model.editingNoteText = "第二次"
        model.saveContent(id, model.editingNoteText)

        // 防抖期内未转发
        #expect(saved.isEmpty)
        try await Task.sleep(for: .milliseconds(150))

        // 只转发最后一次
        #expect(saved.count == 1)
        #expect(saved.first?.id == id)
        #expect(saved.first?.text == "第二次")

        // 非编辑中的行不受理：编辑态复位瞬间的迟到 onChange 不会误存
        model.saveContent(Note.ID(rawValue: 2), "幽灵保存")
        try await Task.sleep(for: .milliseconds(60))
        #expect(saved.count == 1)
    }

    @Test("endEditing：立即转发当前文字并复位编辑态；重复调用幂等")
    func endEditingFlushesImmediately() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        var saved: [(id: Note.ID, text: String)] = []
        model.saveNoteContent = { id, text in saved.append((id, text)) }

        let id = Note.ID(rawValue: 3)
        model.beginEditing(id)
        model.editingNoteText = "收尾保存" // 模拟视图绑定写入
        model.endEditing()

        // 失焦/Esc 路径：无防抖等待，立即转发
        #expect(saved.count == 1)
        #expect(saved.first?.id == id)
        #expect(saved.first?.text == "收尾保存")
        #expect(model.editingNoteID == nil)
        #expect(model.editingNoteText == "")

        // 已不在编辑态：幂等，不再转发
        model.endEditing()
        #expect(saved.count == 1)
    }

    @Test("beginEditing：以行内容播种编辑文字；切换行先收尾上一行")
    func beginEditingSeedsAndFlushesPrevious() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let first = try await environment.noteRepository.create(content: "甲便签")
        let second = try await environment.noteRepository.create(content: "乙便签")

        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        await model.runNotes(oneShot(try await firstFrame(environment)))
        var saved: [(id: Note.ID, text: String)] = []
        model.saveNoteContent = { id, text in saved.append((id, text)) }

        model.beginEditing(first.id)
        #expect(model.editingNoteID == first.id)
        #expect(model.editingNoteText == "甲便签")

        // 切换行：上一行立即收尾转发（不等待防抖），新行播种行内容
        model.beginEditing(second.id)
        #expect(saved.count == 1)
        #expect(saved.first?.id == first.id)
        #expect(saved.first?.text == "甲便签")
        #expect(model.editingNoteID == second.id)
        #expect(model.editingNoteText == "乙便签")
    }

    @Test("beginEditing 同行重入：保留进行中文字，不触发收尾转发")
    func beginEditingSameRowPreservesInProgressText() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        var saved: [(id: Note.ID, text: String)] = []
        model.saveNoteContent = { id, text in saved.append((id, text)) }

        let id = Note.ID(rawValue: 5)
        model.beginEditing(id)
        model.editingNoteText = "改到一半"

        // 编辑态下右键菜单再点「编辑」（同一行）：守卫保文字，不收尾
        model.beginEditing(id)
        #expect(model.editingNoteID == id)
        #expect(model.editingNoteText == "改到一半")
        #expect(saved.isEmpty)
    }

    @Test("endEditing 抢先防抖：取消防抖任务，flush 后恰好一次转发")
    func endEditingCancelsPendingDebounce() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        var saved: [(id: Note.ID, text: String)] = []
        model.saveNoteContent = { id, text in saved.append((id, text)) }
        model.saveDebounceDelay = .milliseconds(50)

        let id = Note.ID(rawValue: 6)
        model.beginEditing(id)
        model.editingNoteText = "冲刷内容"
        model.saveContent(id, model.editingNoteText) // 挂起防抖
        model.endEditing() // 立即收尾：转发 + 取消防抖

        #expect(saved.count == 1)
        #expect(saved.first?.text == "冲刷内容")

        // 防抖窗已过：挂起任务被取消，不会对同一行再补一枪（双转发回归即挂）
        try await Task.sleep(for: .milliseconds(150))
        #expect(saved.count == 1)
    }

    @Test("编辑中的行从流消失（如清空保存=删除）：复位编辑态且挂起防抖不再转发")
    func editingRowDisappearingResetsState() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let kept = try await environment.noteRepository.create(content: "留下的")
        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        await model.runNotes(oneShot(try await firstFrame(environment)))
        var saved: [(id: Note.ID, text: String)] = []
        model.saveNoteContent = { id, text in saved.append((id, text)) }
        model.saveDebounceDelay = .milliseconds(50)

        // 编辑一条快照里不存在的行（等价于它已被删）：挂起一次防抖保存
        let deleted = Note.ID(rawValue: 99)
        model.beginEditing(deleted)
        model.editingNoteText = "即将消失的编辑"
        model.saveContent(deleted, model.editingNoteText)

        // 推入不含该行的新快照：编辑态立即复位（防误存守卫）
        await model.runNotes(oneShot(try await firstFrame(environment)))
        #expect(model.notes.map(\.id) == [kept.id])
        #expect(model.editingNoteID == nil)
        #expect(model.editingNoteText == "")

        // 防抖窗已过：挂起保存被取消，对已删行零转发
        try await Task.sleep(for: .milliseconds(150))
        #expect(saved.isEmpty)
    }

    @Test("动作转发：置顶/取消置顶/钉桌面/取消钉住/删除调用注入闭包")
    func actionsForwardToInjectedClosures() async throws {
        let model = MainNotesModel(observeNotes: { AsyncThrowingStream { $0.finish() } })
        var pinnedCalls: [(Note.ID, Bool)] = []
        var pinDesktopCalls: [Note.ID] = []
        var unpinDesktopCalls: [Note.ID] = []
        var deletedCalls: [Note.ID] = []
        model.setNotePinned = { pinnedCalls.append(($0, $1)) }
        model.pinNoteToDesktop = { pinDesktopCalls.append($0) }
        model.unpinNoteFromDesktop = { unpinDesktopCalls.append($0) }
        model.deleteNote = { deletedCalls.append($0) }

        let id = Note.ID(rawValue: 7)
        model.setNotePinned(id, true)
        model.setNotePinned(id, false)
        model.pinNoteToDesktop(id)
        model.unpinNoteFromDesktop(id)
        model.deleteNote(id)

        // 元组数组无 Equatable，按位拆开比较（等价 [(id, true), (id, false)]）。
        #expect(pinnedCalls.map(\.0) == [id, id])
        #expect(pinnedCalls.map(\.1) == [true, false])
        #expect(pinDesktopCalls == [id])
        #expect(unpinDesktopCalls == [id])
        #expect(deletedCalls == [id])
    }

    @Test("观察流收尾：一次性正常结束与读取失败异常都不崩、状态保留")
    func streamTerminationIsSafe() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        _ = try await environment.noteRepository.create(content: "留在原地")

        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })
        await model.runNotes(oneShot(try await firstFrame(environment)))
        #expect(model.notes.count == 1)

        // 非取消的正常结束（故障信号）：记日志但返回、状态保留
        await model.runNotes(oneShot(try await firstFrame(environment)))
        #expect(model.notes.count == 1)

        // 异常结束：吞掉错误、状态不清空
        await model.runNotes(failingStream())
        #expect(model.notes.count == 1)
    }

    @Test("start/stop：消费真实观察流收到创建更新；stop 停止消费")
    func startConsumesRealStream() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = MainNotesModel(observeNotes: { environment.noteRepository.observeActive() })

        model.start()
        defer { model.stop() }
        _ = try await environment.noteRepository.create(content: "启动即见")
        let appeared = await waitUntil { model.notes.count == 1 }
        #expect(appeared)
    }
}
