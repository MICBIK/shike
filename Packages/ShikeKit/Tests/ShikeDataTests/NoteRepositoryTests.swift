// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import GRDB
import Testing

@testable import ShikeData

/// 仓储测试共用设施：conventions.md「测试」规定的基准时间 T0（2026-09-23 12:00，
/// Asia/Shanghai）与注入时钟的内存库。
enum TestClock {
    static let t0: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 23
        components.hour = 12
        return calendar.date(from: components)!
    }()

    /// 每次调用前进一分钟的时钟：用于区分两次独立写入。
    static func ticking() -> (@Sendable () -> Date) {
        let clock = TickingClock(base: t0)
        return { clock.now() }
    }

    private final class TickingClock: @unchecked Sendable {
        private let lock = NSLock()
        private var base: Date

        init(base: Date) {
            self.base = base
        }

        func now() -> Date {
            lock.lock()
            defer { lock.unlock() }
            base = base.addingTimeInterval(60)
            return base
        }
    }
}

/// 在时限内轮询等待条件成立（条件读的是 ReceiveBox 的同步快照）；超时返回 false。
func waitFor(
    _ condition: @autoclosure () -> Bool,
    timeout: Duration = .seconds(2)
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// 便签仓储：写语义、ADR-017 的 updatedAt 规则、观察流（Story 1.4）。
struct NoteRepositoryTests {
    @Test("create 返回新 uuid 与 T0 时间戳；uuid 与时间都以文本存储")
    func createStoresLowercaseTextUUIDAndTextDates() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let repository = NoteRepository(database: database)

        let note = try await repository.create(content: "第一条")
        let note2 = try await repository.create(content: "第二条")

        #expect(note.uuid != note2.uuid)
        #expect(note.createdAt == TestClock.t0)
        #expect(note.updatedAt == TestClock.t0)
        #expect(note.deletedAt == nil)

        let checks = try await database.writer.read { database in
            try String.fetchAll(database, sql: "SELECT typeof(uuid) || '|' || uuid || '|' || typeof(createdAt) FROM note")
        }
        #expect(checks.count == 2)
        for line in checks {
            let parts = line.split(separator: "|")
            #expect(parts.count == 3)
            #expect(parts[0] == "text")
            #expect(parts[1].wholeMatch(of: /^[0-9a-f-]{36}$/) != nil)
            #expect(parts[2] == "text")
        }
    }

    @Test("Sendable 值类型由编译器核对")
    func domainTypesAreSendable() {
        func assertSendable<T: Sendable>(_: T.Type) {}
        assertSendable(Note.self)
        assertSendable(Note.ID.self)
        assertSendable(NoteListItem.self)
        assertSendable(NoteRepository.self)
    }

    @Test("只有 updateContent 更新 updatedAt；setPinned 幂等；软删除保留原 deletedAt")
    func writeSemanticsFollowADR017() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let repository = NoteRepository(database: database)

        let note = try await repository.create(content: "原文")
        let updatedAtAtCreation = note.updatedAt

        // updateContent 更新 updatedAt
        try await repository.updateContent(note.id, to: "新文")
        var fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.content == "新文")
        #expect(fresh!.updatedAt > updatedAtAtCreation)
        let updatedAtAfterContentChange = fresh!.updatedAt

        // setPinned(true)：pinnedAt = 当前时间，updatedAt 不变
        try await repository.setPinned(note.id, true)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.pinnedAt != nil)
        #expect(fresh!.updatedAt == updatedAtAfterContentChange)
        let pinnedAtValue = fresh!.pinnedAt

        // setPinned(true) 幂等：不改动
        try await repository.setPinned(note.id, true)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.pinnedAt == pinnedAtValue)
        #expect(fresh!.updatedAt == updatedAtAfterContentChange)

        // setPinned(false)：pinnedAt = nil，updatedAt 不变；再取消一次也是无改动
        try await repository.setPinned(note.id, false)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.pinnedAt == nil)
        #expect(fresh!.updatedAt == updatedAtAfterContentChange)
        try await repository.setPinned(note.id, false)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.pinnedAt == nil)

        // softDelete：deletedAt = 当前时间，updatedAt 不变；再删一次保留原 deletedAt
        try await repository.softDelete(note.id)
        fresh = try await fetchNote(from: database, id: note.id)
        let deletedAtValue = fresh!.deletedAt
        #expect(deletedAtValue != nil)
        #expect(fresh!.updatedAt == updatedAtAfterContentChange)
        try await repository.softDelete(note.id)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.deletedAt == deletedAtValue)

        // 已软删除的便签仍然可以 updateContent；内容变化照样推进 updatedAt
        try await repository.updateContent(note.id, to: "回收站里改")
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.content == "回收站里改")
        let updatedAtAfterTrashEdit = fresh!.updatedAt
        #expect(updatedAtAfterTrashEdit > updatedAtAfterContentChange)

        // restore：deletedAt = nil，updatedAt 不变；再恢复一次也无改动
        try await repository.restore(note.id)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.deletedAt == nil)
        #expect(fresh!.updatedAt == updatedAtAfterTrashEdit)
        try await repository.restore(note.id)
        fresh = try await fetchNote(from: database, id: note.id)
        #expect(fresh?.deletedAt == nil)
    }

    /// 直接查库取行（绕过仓储），用于断言写入效果；行不存在时返回 nil。
    private func fetchNote(from database: AppDatabase, id: Note.ID) async throws -> Note? {
        try await database.writer.read { database in
            try NoteRecord.fetchOne(database, key: id.rawValue)?.note
        }
    }

    @Test("契约边界：空内容可建；相同内容也推进 updatedAt；软删除后可永久删除")
    func contractEdgeCases() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        let repository = NoteRepository(database: database)

        // 内容可以为空（data-layer.md 仓储表）
        let empty = try await repository.create(content: "")
        #expect(empty.content == "")

        // 相同内容写回也推进 updatedAt（契约原文"更新"；自动保存语义已记录在 data-layer.md）
        let note = try await repository.create(content: "自动保存")
        let before = try await fetchNote(from: database, id: note.id)
        try await repository.updateContent(note.id, to: "自动保存")
        let after = try await fetchNote(from: database, id: note.id)
        #expect(after!.content == "自动保存")
        #expect(after!.updatedAt > before!.updatedAt)

        // 已软删除的便签可以被永久删除
        try await repository.softDelete(note.id)
        try await repository.permanentlyDelete(note.id)
        let gone = try await fetchNote(from: database, id: note.id)
        #expect(gone == nil)
    }

    @Test("permanentlyDelete 删除该行，卡片级联删除")
    func permanentDeleteRemovesRowAndCascadesCards() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let repository = NoteRepository(database: database)
        let note = try await repository.create(content: "待永久删除")
        try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO stickyCard (noteId, x, y, width, height, level, color, fontSize,
                    autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen, createdAt, updatedAt)
                VALUES (?, 0, 0, 100, 100, 'normal', 'yellow', 'medium', 0, 0, 0, 0, 0,
                    '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """, arguments: [note.id.rawValue])
        }

        try await repository.permanentlyDelete(note.id)

        let counts = try await database.writer.read { database in
            (
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note") ?? -1,
                try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM stickyCard") ?? -1
            )
        }
        #expect(counts.0 == 0)
        #expect(counts.1 == 0)
    }

    @Test("不存在的便签 ID：每个修改方法都抛 notFound")
    func mutatingMissingNoteThrowsNotFound() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let repository = NoteRepository(database: database)
        let ghost = Note.ID(rawValue: 9999)

        await #expect(throws: ShikeDataError.notFound) { try await repository.updateContent(ghost, to: "x") }
        await #expect(throws: ShikeDataError.notFound) { try await repository.setPinned(ghost, true) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.setPinned(ghost, false) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.softDelete(ghost) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.restore(ghost) }
        await #expect(throws: ShikeDataError.notFound) { try await repository.permanentlyDelete(ghost) }
    }

    @Test("只读连接上的写方法抛 writeFailed(.readOnly)")
    func readOnlyWriteFailsWithReadOnlyReason() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shike-readonly-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // 先建立有数据的库
        let writable = try AppDatabase.open(directory: directory)
        let setup = NoteRepository(database: writable)
        _ = try await setup.create(content: "只读测试")

        // 以只读方式打开同一个库文件
        var configuration = Configuration()
        configuration.readonly = true
        let readOnlyQueue = try DatabaseQueue(
            path: directory.appendingPathComponent(AppDatabase.fileName).path,
            configuration: configuration
        )
        let readOnlyDatabase = AppDatabase(writer: readOnlyQueue, options: .init())
        let repository = NoteRepository(database: readOnlyDatabase)

        await #expect(throws: ShikeDataError.writeFailed(.readOnly)) {
            try await repository.create(content: "写不进去")
        }
    }

    @Test("simulateWriteFailure：所有写方法抛 writeFailed(.simulated)，观察照常工作")
    func simulatedFailureKeepsDataAndObservationAlive() async throws {
        let database = try AppDatabase.inMemory(options: .init(
            clock: { TestClock.t0 },
            simulateWriteFailure: true
        ))
        let repository = NoteRepository(database: database)
        let ghost = Note.ID(rawValue: 1)

        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.create(content: "x") }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.updateContent(ghost, to: "x") }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.setPinned(ghost, true) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.softDelete(ghost) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.restore(ghost) }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) { try await repository.permanentlyDelete(ghost) }

        let count = try await database.writer.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note")
        }
        #expect(count == 0)

        // 观察不受影响：订阅后先收到当前值
        let stream = repository.observeActive()
        var received: [[NoteListItem]] = []
        for try await items in stream {
            received.append(items)
            break
        }
        #expect(received.count == 1)
        #expect(received[0].isEmpty)
    }
}

/// 观察流：初始值、更新推送、软删除消失、无关表不推送、取消、读取失败（Story 1.4）。
struct NoteObservationTests {
    @Test("初始值排序与 isPinnedToDesktop；写入推送；软删除消失；无关表不推送；取消即停")
    func observationLifecycle() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        let repository = NoteRepository(database: database)

        let first = try await repository.create(content: "第一张")
        let second = try await repository.create(content: "第二张")
        // 给第一张便签插一张卡片（isPinnedToDesktop = true）
        try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO stickyCard (noteId, x, y, width, height, level, color, fontSize,
                    autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen, createdAt, updatedAt)
                VALUES (?, 0, 0, 100, 100, 'normal', 'yellow', 'medium', 0, 0, 0, 0, 0,
                    '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """, arguments: [first.id.rawValue])
        }

        let stream = repository.observeActive()
        let received = ReceiveBox<NoteListItem>()
        let task = Task {
            for try await items in stream {
                received.append(items)
            }
        }

        // 初始值：updatedAt 相同则按 id 降序 → 第二张在前；第一张带卡片
        let sawInitial = await waitFor(received.count >= 1)
        #expect(sawInitial)
        let initial = received.snapshot[0]
        #expect(initial.map(\.note.id.rawValue) == [second.id.rawValue, first.id.rawValue])
        #expect(initial.map(\.isPinnedToDesktop) == [false, true])

        // 写入提交后收到新值
        _ = try await repository.create(content: "第三张")
        let sawThird = await waitFor(received.snapshot.last?.count == 3)
        #expect(sawThird)
        #expect(received.snapshot.last?.first?.note.content == "第三张")

        // 软删除的便签从结果中消失；恢复后重新出现
        try await repository.softDelete(second.id)
        let sawDeletion = await waitFor(received.snapshot.last?.count == 2)
        #expect(sawDeletion)
        #expect(received.snapshot.last?.contains { $0.note.id == second.id } == false)
        try await repository.restore(second.id)
        let sawRestore = await waitFor(received.snapshot.last?.count == 3)
        #expect(sawRestore)
        #expect(received.snapshot.last?.contains { $0.note.id == second.id } == true)

        // 观察存续期间的置顶不改变内容排序，但卡片插入会翻转 isPinnedToDesktop
        try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO stickyCard (noteId, x, y, width, height, level, color, fontSize,
                    autoHide, hideDelay, hiddenOpacity, allSpaces, showOverFullScreen, createdAt, updatedAt)
                VALUES (?, 0, 0, 100, 100, 'normal', 'yellow', 'medium', 0, 0, 0, 0, 0,
                    '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """, arguments: [second.id.rawValue])
        }
        let sawCardFlip = await waitFor(
            received.snapshot.last?.first { $0.note.id == second.id }?.isPinnedToDesktop == true
        )
        #expect(sawCardFlip)

        // 无关表（todo）的写入不推送重复的值
        let countBefore = received.count
        try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO todo (uuid, title, dueHasTime, dueAt, createdAt, updatedAt)
                VALUES ('0b8df3a0-4a1e-4d3e-9f60-00000000000a', '无关', 0, NULL, '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
        }
        let stayedQuietAfterUnrelatedWrite = await waitFor(received.count > countBefore, timeout: .milliseconds(800)) == false
        #expect(stayedQuietAfterUnrelatedWrite)
        #expect(received.count == countBefore)

        // 取消消费的 Task 即停止观察
        task.cancel()
        _ = await task.result
        let countAtCancel = received.count
        let fourth = try await repository.create(content: "取消后写入")
        let stayedQuietAfterCancel = await waitFor(received.count > countAtCancel, timeout: .milliseconds(800)) == false
        #expect(stayedQuietAfterCancel)
        #expect(received.count == countAtCancel)
        _ = fourth
    }

    @Test("读取失败：流以 readFailed(原因) 结束")
    func fetchFailureEndsStreamWithReadFailed() async throws {
        let database = try AppDatabase.inMemory(options: .init(clock: { TestClock.t0 }))
        _ = try await NoteRepository(database: database).create(content: "一行")

        // 直接构造观察流：第二次取值起抛错，模拟读取失败。
        // （史诗验收写的机制是"第二个连接 DROP TABLE note"，实测 GRDB 7.11 的
        // 观察在表被删后既不重取也不报错，只会静默挂起，该机制无法触发
        // readFailed；改为注入取值失败，同一契约、确定性触发。偏差记录在
        // spec-1-4 与晨报，1.17 写回时建议修订该验收的机制描述。）
        struct FetchBroken: Error {}
        let breaker = BreakBox()
        let stream = observationStream(reader: database.writer) { database in
            if breaker.isBroken {
                throw FetchBroken()
            }
            return try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM note") ?? -1
        }

        let thrown = ErrorBox()
        let task = Task {
            do {
                for try await _ in stream {}
            } catch {
                thrown.set(error)
            }
        }

        // 订阅后先收到当前值；随后打破读取，再经一次提交触发重取
        _ = try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO note (uuid, content, createdAt, updatedAt)
                VALUES ('0b8df3a0-4a1e-4d3e-9f60-00000000000c', '触发重取', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
        }
        breaker.breakIt()
        _ = try await database.writer.write { database in
            try database.execute(sql: """
                INSERT INTO note (uuid, content, createdAt, updatedAt)
                VALUES ('0b8df3a0-4a1e-4d3e-9f60-00000000000d', '再来一次', '2026-01-01 00:00:00.000', '2026-01-01 00:00:00.000')
                """)
        }

        let sawReadFailure = await waitFor(thrown.get != nil)
        #expect(sawReadFailure)
        task.cancel()
        guard let error = thrown.get as? ShikeDataError, case .readFailed(.ioError) = error else {
            Issue.record("流应以 readFailed(.ioError) 结束，实际：\(String(describing: thrown.get))")
            return
        }
    }
}

/// 线程安全的开关：让取值闭包从某次调用起抛错。
private final class BreakBox: @unchecked Sendable {
    private let lock = NSLock()
    private var broken = false

    var isBroken: Bool {
        lock.lock()
        defer { lock.unlock() }
        return broken
    }

    func breakIt() {
        lock.lock()
        defer { lock.unlock() }
        broken = true
    }
}

/// 线程安全的错误收集器。
private final class ErrorBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: (any Error)?

    var get: (any Error)? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set(_ error: any Error) {
        lock.lock()
        defer { lock.unlock() }
        value = error
    }
}

/// 线程安全的结果收集器：观察流的回调在任意执行器上。（便签与待办测试共用）
final class ReceiveBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [[Value]] = []

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return items.count
    }

    var snapshot: [[Value]] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }

    func append(_ value: [Value]) {
        lock.lock()
        defer { lock.unlock() }
        items.append(value)
    }
}
