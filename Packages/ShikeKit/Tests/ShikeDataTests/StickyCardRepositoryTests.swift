// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Testing

@testable import ShikeData

/// 桌面卡片仓储：钉出幂等、更新、取消钉住、随软删除隐藏、观察（Story 1.6）。
struct StickyCardRepositoryTests {
    private func makeWorld() throws -> (AppDatabase, NoteRepository, StickyCardRepository) {
        let database = try AppDatabase.inMemory(options: .init(clock: TestClock.ticking()))
        return (database, NoteRepository(database: database), StickyCardRepository(database: database))
    }

    private func sampleOptions(opacity: Double = 0.3) -> StickyCardOptions {
        StickyCardOptions(
            level: .desktop,
            color: .blue,
            fontSize: .large,
            autoHide: true,
            hideDelay: 1.5,
            hiddenOpacity: opacity,
            allSpaces: true,
            showOverFullScreen: false
        )
    }

    private func sampleFrame() -> CardFrame {
        CardFrame(x: 10, y: 20, width: 300, height: 200)
    }

    @Test("hiddenOpacity 在类型内钳制到 0.0～0.6")
    func hiddenOpacityClamped() {
        #expect(sampleOptions(opacity: 0.9).hiddenOpacity == 0.6)
        #expect(sampleOptions(opacity: -1).hiddenOpacity == 0.0)
        #expect(sampleOptions(opacity: 0.25).hiddenOpacity == 0.25)
    }

    @Test("Sendable 值类型由编译器核对")
    func domainTypesAreSendable() {
        func assertSendable<T: Sendable>(_: T.Type) {}
        assertSendable(StickyCard.self)
        assertSendable(CardFrame.self)
        assertSendable(StickyCardOptions.self)
        assertSendable(CardLevel.self)
        assertSendable(CardColor.self)
        assertSendable(CardFontSize.self)
        assertSendable(VisibleCard.self)
    }

    @Test("钉出：新卡片时间戳一致；重复钉出返回现有卡片不做改动")
    func pinIsIdempotent() async throws {
        let (database, notes, cards) = try makeWorld()
        let note = try await notes.create(content: "被钉的便签")

        let first = try await cards.pin(note.id, frame: sampleFrame(), options: sampleOptions())
        #expect(first.noteID == note.id)
        #expect(first.createdAt == first.updatedAt)
        #expect(first.options.hiddenOpacity == 0.3)

        // 改动参数再钉一次：仍返回现有卡片，不做任何改动
        let again = try await cards.pin(
            note.id,
            frame: CardFrame(x: 99, y: 99, width: 1, height: 1),
            options: sampleOptions(opacity: 0.5)
        )
        #expect(again == first)

        let count = try await database.writer.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM stickyCard")
        }
        #expect(count == 1)
    }

    @Test("便签不存在或已软删除时 pin 抛 notFound")
    func pinMissingOrDeletedNoteThrowsNotFound() async throws {
        let (database, notes, cards) = try makeWorld()

        await #expect(throws: ShikeDataError.notFound) {
            try await cards.pin(Note.ID(rawValue: 9999), frame: sampleFrame(), options: sampleOptions())
        }

        let note = try await notes.create(content: "会被删掉")
        try await notes.softDelete(note.id)
        await #expect(throws: ShikeDataError.notFound) {
            try await cards.pin(note.id, frame: sampleFrame(), options: sampleOptions())
        }
        _ = database
    }

    @Test("updateFrame / updateOptions 更新对应列与 updatedAt；unpin 删除卡片便签不变；缺失即 notFound")
    func updateAndUnpinSemantics() async throws {
        let (database, notes, cards) = try makeWorld()
        let note = try await notes.create(content: "有卡片")

        let initial = try await cards.pin(note.id, frame: sampleFrame(), options: sampleOptions())

        try await cards.updateFrame(note.id, frame: CardFrame(x: 1, y: 2, width: 30, height: 40))
        var card = try await currentCard(database, noteID: note.id)
        #expect(card?.frame == CardFrame(x: 1, y: 2, width: 30, height: 40))
        #expect(card!.updatedAt > initial.updatedAt)
        let afterFrame = card!.updatedAt

        let newOptions = sampleOptions(opacity: 0.55)
        try await cards.updateOptions(note.id, options: newOptions)
        card = try await currentCard(database, noteID: note.id)
        #expect(card?.options.color == .blue)
        #expect(card?.options.hiddenOpacity == 0.55)
        #expect(card!.updatedAt > afterFrame)

        // 不存在的卡片 ID：三个方法都抛 notFound
        let ghost = Note.ID(rawValue: 9999)
        await #expect(throws: ShikeDataError.notFound) { try await cards.updateFrame(ghost, frame: sampleFrame()) }
        await #expect(throws: ShikeDataError.notFound) { try await cards.updateOptions(ghost, options: sampleOptions()) }
        await #expect(throws: ShikeDataError.notFound) { try await cards.unpin(ghost) }

        // unpin：卡片删除，便签不变
        try await cards.unpin(note.id)
        let cardGone = try await currentCard(database, noteID: note.id)
        #expect(cardGone == nil)
        let noteCount = try await database.writer.read { database in
            try Int.fetchOne(
                database,
                sql: "SELECT COUNT(*) FROM note WHERE id = ? AND deletedAt IS NULL",
                arguments: [note.id.rawValue]
            )
        }
        #expect(noteCount == 1)
    }

    private func currentCard(_ database: AppDatabase, noteID: Note.ID) async throws -> StickyCard? {
        try await database.writer.read { database in
            try StickyCardRecord.fetchOne(
                database,
                sql: "SELECT * FROM stickyCard WHERE noteId = ?",
                arguments: [noteID.rawValue]
            )?.card
        }
    }

    @Test("软删除后卡片从 observeVisible 消失，恢复后重现；便签永久删除时级联删除")
    func visibleFollowsNoteLifecycle() async throws {
        let (database, notes, cards) = try makeWorld()
        let note = try await notes.create(content: "生命周期")
        _ = try await cards.pin(note.id, frame: sampleFrame(), options: sampleOptions())

        let received = ReceiveBox<VisibleCard>()
        let stream = cards.observeVisible()
        let task = Task {
            for try await items in stream {
                received.append(items)
            }
        }
        defer { task.cancel() }

        #expect(await waitFor(received.count >= 1))
        #expect(received.snapshot[0].count == 1)

        // 软删除便签：卡片从可见结果中消失
        try await notes.softDelete(note.id)
        #expect(await waitFor(received.snapshot.last?.isEmpty == true))

        // 恢复便签：卡片重新出现
        try await notes.restore(note.id)
        #expect(await waitFor(received.snapshot.last?.count == 1))

        // 永久删除便签：卡片级联删除
        try await notes.permanentlyDelete(note.id)
        #expect(await waitFor(received.snapshot.last?.isEmpty == true))
        let count = try await database.writer.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM stickyCard")
        }
        #expect(count == 0)
    }

    @Test("simulateWriteFailure：所有写方法抛 writeFailed(.simulated)")
    func simulatedFailure() async throws {
        let database = try AppDatabase.inMemory(options: .init(
            clock: { TestClock.t0 },
            simulateWriteFailure: true
        ))
        let repository = StickyCardRepository(database: database)
        let ghost = Note.ID(rawValue: 1)

        await #expect(throws: ShikeDataError.writeFailed(.simulated)) {
            try await repository.pin(ghost, frame: sampleFrame(), options: sampleOptions())
        }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) {
            try await repository.updateFrame(ghost, frame: sampleFrame())
        }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) {
            try await repository.updateOptions(ghost, options: sampleOptions())
        }
        await #expect(throws: ShikeDataError.writeFailed(.simulated)) {
            try await repository.unpin(ghost)
        }
    }
}
