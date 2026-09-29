// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// S3-01：钉出与收回（03 §10.2；NFR19 失败上报）。
/// 走 AppEnvironment 组装的真实闭包（几何 + 仓储），观察流断言用"写后新建流"的首帧（确定性）。
@MainActor
struct PinCardFlowTests {
    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        return (environment, suiteName)
    }

    /// 写操作落库后新建观察流，取首帧（观察流首帧即当前全量）。
    private func snapshot(_ environment: AppEnvironment) async throws -> [VisibleCard] {
        var iterator = environment.stickyCardRepository.observeVisible().makeAsyncIterator()
        return try await iterator.next() ?? []
    }

    @Test("钉出：卡片按默认选项入账；面板行标记已钉（观察流附带便签）")
    func pinCreatesCardWithDefaults() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "钉我")
        let model = environment.panelModel
        await model.pinNoteToDesktop(note.id)
        let visible = try await snapshot(environment)
        #expect(visible.count == 1)
        #expect(visible.first?.note.id == note.id)
        #expect(visible.first?.card.options == environment.preferences.cardDefaultOptions)
        // 默认选项即 03 §9 的卡片分页默认（黄/中/浮在最上层/所有空间/不压全屏）
        #expect(visible.first?.card.options.color == .yellow)
        #expect(visible.first?.card.options.level == .floating)
        #expect(visible.first?.card.options.allSpaces == true)
        #expect(visible.first?.card.options.showOverFullScreen == false)
    }

    @Test("重复钉出走幂等：仍是一张卡，位置不变")
    func repinIsIdempotent() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "只钉一次")
        let model = environment.panelModel
        await model.pinNoteToDesktop(note.id)
        let first = try await snapshot(environment)
        await model.pinNoteToDesktop(note.id)
        let second = try await snapshot(environment)
        #expect(second.count == 1)
        #expect(second.first?.card.frame == first.first?.card.frame)
    }

    @Test("取消钉住：卡片记录删除，便签保留")
    func unpinKeepsNote() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "钉了再收")
        let model = environment.panelModel
        await model.pinNoteToDesktop(note.id)
        #expect(try await snapshot(environment).count == 1)
        await model.unpinNoteFromDesktop(note.id)
        #expect(try await snapshot(environment).isEmpty)
        // 便签本体还在（active 流）
        var noteIterator = environment.noteRepository.observeActive().makeAsyncIterator()
        let notes = try await noteIterator.next() ?? []
        #expect(notes.count == 1)
    }

    @Test("删除已钉便签：卡片从可见流消失；撤销删除后卡片回来（软删除期间记录保留）")
    func deleteAndUndoRestoresCard() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "联动验证")
        let model = environment.panelModel
        await model.pinNoteToDesktop(note.id)
        #expect(try await snapshot(environment).count == 1)
        try await environment.noteRepository.softDelete(note.id)
        #expect(try await snapshot(environment).isEmpty)
        try await environment.noteRepository.restore(note.id)
        let visible = try await snapshot(environment)
        #expect(visible.count == 1)
        #expect(visible.first?.card.noteID == note.id)
    }

    @Test("钉出不存在的便签：notFound 提示条（诚实文案 + 知道了可清）")
    func pinMissingNoteReportsBanner() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        await model.pinNoteToDesktop(Note.ID(rawValue: 999))
        // 打磨 R2：notFound 不再显示"未知错误（0）"
        #expect(model.banner?.kind == .notFound)
        model.dismissBanner()
        #expect(model.banner == nil)
    }

    @Test("移动与改选项互不覆盖：先移后改、先改后移 frame 都保持（回归 2026-09-29 弹回初始位置）")
    func optionsAndFrameWritesAreIndependent() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let note = try await environment.noteRepository.create(content: "拖动回归")
        let model = environment.panelModel
        await model.pinNoteToDesktop(note.id)
        // 先移动再改选项：位置不被选项写路径覆盖
        let dragged = CardFrame(x: 620, y: 300, width: 260, height: 200)
        try await environment.stickyCardRepository.updateFrame(note.id, frame: dragged)
        var options = environment.preferences.cardDefaultOptions
        options.color = .blue
        try await environment.stickyCardRepository.updateOptions(note.id, options: options)
        var visible = try await snapshot(environment)
        #expect(visible.first?.card.frame == dragged)
        #expect(visible.first?.card.options.color == .blue)
        // 反向顺序：再改一次选项后再移动，两者同样各自生效
        options.fontSize = .large
        try await environment.stickyCardRepository.updateOptions(note.id, options: options)
        let moved = CardFrame(x: 100, y: 80, width: 240, height: 180)
        try await environment.stickyCardRepository.updateFrame(note.id, frame: moved)
        visible = try await snapshot(environment)
        #expect(visible.first?.card.frame == moved)
        #expect(visible.first?.card.options.fontSize == .large)
    }
}
