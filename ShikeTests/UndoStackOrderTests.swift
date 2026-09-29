// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike

/// 打磨轮 R3（2026-09-29 夜）：失败回栈的顺序不变量。
/// 弹出到回插之间若有新删除入栈，被撤销项必须插回它们之下（最近删的仍先出栈）；
/// 原实现的 append 会把更早删除的条目顶到栈顶。
@MainActor
struct UndoStackOrderTests {
    private func makeEnvironment() throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let environment = try AppEnvironment(
            database: AppDatabase.inMemory(),
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: URL(fileURLWithPath: "/tmp/shike-tests-panel", isDirectory: true)
        )
        return (environment, suiteName)
    }

    private func waitUntil(
        _ condition: @autoclosure () -> Bool,
        timeoutSeconds: Double = 2,
        _ label: String = ""
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(condition(), "等待超时：\(label)")
    }

    /// 经模型删除（入撤销栈）两条便签并等观察流到位。
    private func deleteTwoViaModel(_ environment: AppEnvironment) async throws -> (Note, Note) {
        let model = environment.panelModel
        model.start() // 列表断言依赖观察流推送
        let a = try await environment.noteRepository.create(content: "甲")
        let b = try await environment.noteRepository.create(content: "乙")
        try await waitUntil(model.notes.count == 2, "两条便签到位")
        await model.deleteNote(a.id)
        await model.deleteNote(b.id)
        return (a, b)
    }

    @Test("失败回栈按删除序号插回：弹出的条目回到栈顶原位")
    func reinsertKeepsOrder() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let (_, b) = try await deleteTwoViaModel(environment)
        #expect(model.deletedStack.map(\.summary) == ["甲", "乙"])
        // ⌘Z 弹出乙（恢复在飞）；等待出栈落定后模拟"恢复失败回栈"
        #expect(model.undoLastDeleteIfNeeded())
        try await waitUntil(model.deletedStack.map(\.summary) == ["甲"], "乙已出栈")
        let bItem = PanelModel.DeletedItem(kind: .note(b.id), summary: "乙", order: 2)
        model.reinsertForRetry(bItem)
        #expect(model.deletedStack.map(\.summary) == ["甲", "乙"])
    }

    @Test("更早弹出的失败项插回时，排在其后新入栈的删除之下（最近删的仍先出栈）")
    func newerDeletionStaysOnTop() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let (a, _) = try await deleteTwoViaModel(environment)
        // 栈 [甲(1), 乙(2)]；⌘Z 弹出甲前先弹出乙？LIFO 只能从栈顶弹——
        // 场景改为：乙先弹出恢复，甲随后弹出后失败；其间没有新删除时甲回栈顶。
        // 这里验证核心不变量：先弹出（更早删除）的甲，回栈时必须排在后删除的乙之下。
        #expect(model.undoLastDeleteIfNeeded()) // 弹出乙，恢复成功
        try await waitUntil(model.deletedStack.map(\.summary) == ["甲"], "乙已出栈")
        #expect(model.undoLastDeleteIfNeeded()) // 弹出甲，恢复成功
        try await waitUntil(model.deletedStack.isEmpty, "甲已出栈")
        // 其间又删了丙(order 3)
        let c = try await environment.noteRepository.create(content: "丙")
        try await waitUntil(model.notes.count == 3, "丙到位（甲乙已恢复回列表）")
        await model.deleteNote(c.id)
        #expect(model.deletedStack.map(\.summary) == ["丙"])
        // 甲(order 1)此时才回栈（模拟其恢复失败晚到）：必须插在丙之下
        let aItem = PanelModel.DeletedItem(kind: .note(a.id), summary: "甲", order: 1)
        model.reinsertForRetry(aItem)
        #expect(model.deletedStack.map(\.summary) == ["甲", "丙"])
        // 下一次 ⌘Z 弹出的应是丙（最近删除），而不是回插的甲
        #expect(model.undoLastDeleteIfNeeded())
        #expect(model.deletedStack.map(\.summary) == ["甲"])
    }

    @Test("端到端：恢复目标被永久删除后撤销——notFound 提示条，条目回栈保持可达")
    func undoAfterPermanentDeleteReportsNotFound() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = environment.panelModel
        let (a, _) = try await deleteTwoViaModel(environment)
        // 只留甲在栈里：把乙的删除撤销掉
        #expect(model.undoLastDeleteIfNeeded())
        try await waitUntil(model.deletedStack.count == 1, "乙已出栈")
        // 行被永久删除后撤销甲：restore 抛 notFound（仓储语义）
        try await environment.noteRepository.permanentlyDelete(a.id)
        #expect(model.undoLastDeleteIfNeeded())
        // 失败路径是异步收尾：等栈回填与提示条
        try await waitUntil(model.deletedStack.count == 1 && model.banner != nil, "失败回栈")
        #expect(model.deletedStack.count == 1, "失败回栈保持撤销入口可达")
        #expect(model.banner?.kind == .notFound)
    }
}
