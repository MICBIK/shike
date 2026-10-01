// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Note/Todo 的 memberwise init 是 internal（包内约定）

/// S3.5-06：导出服务（纯逻辑，无 IO）。
/// Markdown 节结构/条目格式与 JSON 结构/字段值；日期全部注入固定值 + 固定时区，
/// 断言不随测试机时区漂移。
struct ExportServiceTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    /// 基准：2026-09-29（周二）10:00 Asia/Shanghai——导出时刻兼作待办分组的"现在"。
    private static let generatedAt: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 29
        components.hour = 10
        return calendar.date(from: components)!
    }()

    /// 相对基准日的某天（默认当天 12:00）。
    private func date(_ daysFromNow: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: Self.generatedAt))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func note(id: Int64, content: String, pinned: Bool = false) -> Note {
        Note(
            id: Note.ID(rawValue: id),
            uuid: UUID(),
            content: content,
            pinnedAt: pinned ? Self.generatedAt : nil,
            createdAt: Self.generatedAt,
            updatedAt: Self.generatedAt,
            deletedAt: nil
        )
    }

    private func todo(
        id: Int64,
        title: String,
        due: TodoDue? = nil,
        snoozedUntil: Date? = nil,
        completedAt: Date? = nil
    ) -> Todo {
        Todo(
            id: Todo.ID(rawValue: id),
            uuid: UUID(),
            title: title,
            due: due,
            snoozedUntil: snoozedUntil,
            completedAt: completedAt,
            createdAt: Self.generatedAt,
            updatedAt: Self.generatedAt,
            deletedAt: nil
        )
    }

    /// 注入固定日期与时区的 markdown 快捷入口。
    private func markdown(notes: [Note] = [], todos: [Todo] = []) -> String {
        ExportService.markdown(notes: notes, todos: todos, generatedAt: Self.generatedAt, timeZone: Self.timeZone)
    }

    /// 某节标题到下一个 "## " 标题之间的条目行（不含节头；节不存在返回空）。
    private func sectionLines(_ output: String, header: String) -> [String] {
        let lines = output.split(separator: "\n").map(String.init)
        guard let start = lines.firstIndex(of: header) else { return [] }
        let rest = lines[(lines.index(after: start))...]
        let end = rest.firstIndex(where: { $0.hasPrefix("## ") }) ?? rest.endIndex
        return Array(rest[..<end])
    }

    // - MARK: Markdown

    @Test("markdown：标题、置顶/全部两节、待办五节与勾选框/时间格式逐条出现且有序")
    func markdownSectionsAndItems() {
        let output = markdown(
            notes: [
                note(id: 1, content: "置顶便签", pinned: true),
                note(id: 2, content: "普通便签"),
            ],
            todos: [
                todo(id: 3, title: "逾期待办", due: TodoDue(date: date(-1), hasTime: true)),
                todo(id: 4, title: "今天待办", due: TodoDue(date: date(0), hasTime: true)),
                todo(id: 5, title: "以后待办", due: TodoDue(date: date(1), hasTime: true)),
                todo(id: 6, title: "无日期待办"),
                todo(id: 7, title: "已完成待办", due: TodoDue(date: date(-2), hasTime: true), completedAt: date(0, hour: 9)),
            ]
        )
        let lines = output.split(separator: "\n").map(String.init)

        #expect(lines.first == "# 拾刻导出（2026年9月29日）")
        // 七个节齐全且按约定顺序出现（置顶 → 全部 → 待办五分组）
        let expectedOrder = [
            "## 置顶",
            "## 全部",
            "## 待办 · 逾期",
            "## 待办 · 今天",
            "## 待办 · 以后",
            "## 待办 · 无日期",
            "## 待办 · 已完成",
        ]
        var searchStart = lines.startIndex
        for header in expectedOrder {
            guard let index = lines[searchStart...].firstIndex(of: header) else {
                Issue.record("缺少节标题或顺序不对：\(header)")
                return
            }
            searchStart = lines.index(after: index)
        }

        // 便签逐条出现；置顶便签全文档恰出现一次（「全部」节只含未置顶，与界面组语义的差异见 ExportService 注释）
        #expect(sectionLines(output, header: "## 置顶") == ["- 置顶便签"])
        #expect(sectionLines(output, header: "## 全部") == ["- 普通便签"])
        #expect(output.components(separatedBy: "- 置顶便签").count - 1 == 1)

        // 待办条目按节归属（分组正确性：时间条目须落在正确的节内）
        #expect(sectionLines(output, header: "## 待办 · 逾期") == ["- [ ] 逾期待办（2026-09-28 12:00）"])
        #expect(sectionLines(output, header: "## 待办 · 今天") == ["- [ ] 今天待办（2026-09-29 12:00）"])
        #expect(sectionLines(output, header: "## 待办 · 以后") == ["- [ ] 以后待办（2026-09-30 12:00）"])
        #expect(sectionLines(output, header: "## 待办 · 无日期") == ["- [ ] 无日期待办"])
        #expect(sectionLines(output, header: "## 待办 · 已完成") == ["- [x] 已完成待办"])
    }

    @Test("markdown：多行便签的续行缩进两空格")
    func markdownMultilineIndent() {
        let output = markdown(notes: [note(id: 1, content: "第一行\n第二行\n第三行")])
        #expect(output.contains("- 第一行\n  第二行\n  第三行"))
    }

    @Test("markdown：空数据只输出标题")
    func markdownEmptyOnlyTitle() {
        #expect(markdown() == "# 拾刻导出（2026年9月29日）\n")
    }

    @Test("markdown：空节不输出（无置顶便签、无待办）")
    func markdownSkipsEmptySections() {
        let output = markdown(notes: [note(id: 1, content: "普通便签")], todos: [])
        #expect(!output.contains("## 置顶"))
        #expect(output.contains("## 全部"))
        #expect(!output.contains("## 待办"))

        // 仅置顶输入：「全部」节不输出（每条便签在文档中恰好出现一次）
        let pinnedOnly = markdown(notes: [note(id: 1, content: "只有置顶", pinned: true)], todos: [])
        #expect(pinnedOnly.contains("## 置顶"))
        #expect(!pinnedOnly.contains("## 全部"))
        #expect(pinnedOnly.components(separatedBy: "- 只有置顶").count - 1 == 1)
    }

    @Test("markdown：待办五分组日界边界（昨天 23:59 逾期、今天 00:00/23:59 今天、明天 00:00 以后）")
    func markdownGroupBoundaries() {
        let output = markdown(notes: [], todos: [
            todo(id: 1, title: "昨晚", due: TodoDue(date: date(-1, hour: 23, minute: 59), hasTime: true)),
            todo(id: 2, title: "今零点", due: TodoDue(date: date(0, hour: 0, minute: 0), hasTime: true)),
            todo(id: 3, title: "今晚", due: TodoDue(date: date(0, hour: 23, minute: 59), hasTime: true)),
            todo(id: 4, title: "明零点", due: TodoDue(date: date(1, hour: 0, minute: 0), hasTime: true)),
        ])
        #expect(sectionLines(output, header: "## 待办 · 逾期") == ["- [ ] 昨晚（2026-09-28 23:59）"])
        #expect(Set(sectionLines(output, header: "## 待办 · 今天")) == Set([
            "- [ ] 今零点（2026-09-29 00:00）",
            "- [ ] 今晚（2026-09-29 23:59）",
        ]))
        #expect(sectionLines(output, header: "## 待办 · 以后") == ["- [ ] 明零点（2026-09-30 00:00）"])
    }

    @Test("markdown：节内跟随数据原序（不做面板分组器的 due 排序）")
    func markdownPreservesDataOrderWithinSection() {
        let output = markdown(notes: [], todos: [
            todo(id: 1, title: "晚提交的", due: TodoDue(date: date(0, hour: 18), hasTime: true)),
            todo(id: 2, title: "早提交的", due: TodoDue(date: date(0, hour: 8), hasTime: true)),
        ])
        #expect(sectionLines(output, header: "## 待办 · 今天") == [
            "- [ ] 晚提交的（2026-09-29 18:00）",
            "- [ ] 早提交的（2026-09-29 08:00）",
        ])
    }

    @Test("markdown：全天待办只显日期（与界面全天口径一致，无 00:00 时间括号）")
    func markdownAllDayTodoExportsDateOnly() {
        let output = markdown(notes: [], todos: [
            todo(id: 1, title: "全天", due: TodoDue(date: date(0), hasTime: false)),
        ])
        #expect(sectionLines(output, header: "## 待办 · 今天") == ["- [ ] 全天（2026-09-29）"])
    }

    // - MARK: JSON

    @Test("json：顶层结构（version/generatedAt/notes/todos）与字段值")
    func jsonStructureAndFields() throws {
        let data = try ExportService.json(
            notes: [note(id: 1, content: "便签甲", pinned: true)],
            todos: [todo(id: 2, title: "待办乙", due: TodoDue(date: date(0), hasTime: true))],
            generatedAt: Self.generatedAt
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        // 顶层键与版本
        #expect(Set(object.keys) == ["version", "generatedAt", "notes", "todos"])
        #expect(object["version"] as? Int == 1)

        // generatedAt：ISO8601（UTC），整秒注入 → 往返相等
        let generatedAtText = try #require(object["generatedAt"] as? String)
        let parsedGeneratedAt = try #require(ISO8601DateFormatter().date(from: generatedAtText))
        #expect(parsedGeneratedAt == Self.generatedAt)

        // notes 字段值
        let notes = try #require(object["notes"] as? [[String: Any]])
        #expect(notes.count == 1)
        let exportedNote = try #require(notes.first)
        #expect(exportedNote["content"] as? String == "便签甲")
        #expect(exportedNote["uuid"] is String)
        #expect(exportedNote["pinnedAt"] is String) // 置顶时间非空（ISO8601 字符串）
        #expect(exportedNote["createdAt"] is String)
        #expect(exportedNote["deletedAt"] is NSNull)

        // todos 字段值（due 展开为 date + hasTime；未完成 completedAt 为空）
        let todos = try #require(object["todos"] as? [[String: Any]])
        #expect(todos.count == 1)
        let exportedTodo = try #require(todos.first)
        #expect(exportedTodo["title"] as? String == "待办乙")
        #expect(exportedTodo["completedAt"] is NSNull)
        let due = try #require(exportedTodo["due"] as? [String: Any])
        #expect(due["hasTime"] as? Bool == true)
        #expect(due["date"] is String)
    }

    @Test("json：completedAt 非空时导出为 ISO8601 字符串且可往返")
    func jsonCompletedTodoRoundTrip() throws {
        let completedAt = date(0, hour: 9)
        let data = try ExportService.json(
            notes: [],
            todos: [todo(id: 1, title: "已完成", completedAt: completedAt)],
            generatedAt: Self.generatedAt
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let todos = try #require(object["todos"] as? [[String: Any]])
        let exportedTodo = try #require(todos.first)
        let completedAtText = try #require(exportedTodo["completedAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: completedAtText) == completedAt)
        #expect(exportedTodo["due"] is NSNull) // 无 due 时为空
    }

    @Test("json：可选字段全空时显式 null（键恒在，稳定 schema）；全天待办 due.hasTime=false 原样导出")
    func jsonEncodesAllOptionalKeysAsExplicitNull() throws {
        let data = try ExportService.json(
            notes: [note(id: 1, content: "无置顶")],
            todos: [todo(id: 2, title: "最小待办", due: TodoDue(date: date(0), hasTime: false))],
            generatedAt: Self.generatedAt
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let exportedNote = try #require((object["notes"] as? [[String: Any]])?.first)
        #expect(exportedNote["pinnedAt"] is NSNull)
        #expect(exportedNote["deletedAt"] is NSNull)

        let exportedTodo = try #require((object["todos"] as? [[String: Any]])?.first)
        #expect(exportedTodo["snoozedUntil"] is NSNull)
        #expect(exportedTodo["completedAt"] is NSNull)
        #expect(exportedTodo["deletedAt"] is NSNull)
        let due = try #require(exportedTodo["due"] as? [String: Any])
        #expect(due["hasTime"] as? Bool == false) // 全天原样，不丢 hasTime
        #expect(due["date"] is String)
    }

    @Test("json：snoozedUntil 有值导出为 ISO8601 字符串且整秒往返相等")
    func jsonSnoozedUntilValueExportsISO8601() throws {
        let snoozedUntil = date(0, hour: 16, minute: 30)
        let data = try ExportService.json(
            notes: [],
            todos: [todo(id: 1, title: "稍后提醒", snoozedUntil: snoozedUntil)],
            generatedAt: Self.generatedAt
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedTodo = try #require((object["todos"] as? [[String: Any]])?.first)
        let text = try #require(exportedTodo["snoozedUntil"] as? String)
        #expect(ISO8601DateFormatter().date(from: text) == snoozedUntil)
    }

    @Test("json：解码往返——显式 null 还原为 nil、非空字段精确还原（同 schema 镜像结构验证）")
    func jsonDecodesBackWithNilsRestored() throws {
        let pinned = note(id: 1, content: "置顶便签", pinned: true)
        let plain = note(id: 2, content: "普通便签")
        let timed = todo(id: 3, title: "带时间", due: TodoDue(date: date(0, hour: 15), hasTime: true), snoozedUntil: date(0, hour: 16))
        let done = todo(id: 4, title: "已完成", completedAt: date(0, hour: 9))
        let data = try ExportService.json(notes: [pinned, plain], todos: [timed, done], generatedAt: Self.generatedAt)

        // 导出投影类型是 ExportService 私有：测试内定义同 schema 镜像结构验证解码方向
        // （导出时间的秒级精度约定见 ExportService.json 注释；此处基准均取整秒）。
        struct MirrorDue: Codable { let date: Date; let hasTime: Bool }
        struct MirrorNote: Codable {
            let uuid: UUID
            let content: String
            let pinnedAt: Date?
            let createdAt: Date
            let updatedAt: Date
            let deletedAt: Date?
        }
        struct MirrorTodo: Codable {
            let uuid: UUID
            let title: String
            let due: MirrorDue?
            let snoozedUntil: Date?
            let completedAt: Date?
            let createdAt: Date
            let updatedAt: Date
            let deletedAt: Date?
        }
        struct MirrorDocument: Codable {
            let version: Int
            let generatedAt: Date
            let notes: [MirrorNote]
            let todos: [MirrorTodo]
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(MirrorDocument.self, from: data)

        #expect(document.version == 1)
        #expect(document.generatedAt == Self.generatedAt)
        #expect(document.notes[0].pinnedAt == Self.generatedAt)
        #expect(document.notes[1].pinnedAt == nil) // 显式 null → nil
        #expect(document.notes[1].deletedAt == nil)
        #expect(document.todos[0].due?.date == date(0, hour: 15))
        #expect(document.todos[0].due?.hasTime == true)
        #expect(document.todos[0].snoozedUntil == date(0, hour: 16))
        #expect(document.todos[0].deletedAt == nil)
        #expect(document.todos[1].completedAt == date(0, hour: 9))
        #expect(document.todos[1].due == nil)
    }
}
