// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData

/// 导出服务（S3.5-06）：把便签与待办序列化成 Markdown / JSON 文档。
/// 纯静态函数、无 IO——文件写入由主线程集成时接 NSSavePanel，本类型只产出字符串/字节。
enum ExportService {
    // - MARK: Markdown

    /// Markdown 文档（S3.5-06）：标题 + 置顶/全部两节便签 + 五分组待办；
    /// 空节不输出，节内跟随数据原序；空数据只输出标题。
    /// `generatedAt` 既是标题日期，也是待办分组的"现在"（导出反映生成时刻的状态）。
    ///
    /// 与界面的两处有意差异：
    /// - 「置顶」节已单列，故「全部」节只含未置顶便签（界面的「全部」组含置顶）——
    ///   每条便签在文档中恰好出现一次，不冗余；
    /// - 待办节内跟随数据原序（界面按 due 排序），见 todoSections 注释。
    ///
    /// - Note: 导出是数据制品而非界面文案，节标题为固定中文（"置顶""全部""待办""逾期"
    ///   "今天""以后""无日期""已完成"），写死在代码里——导出文件不随应用语言切换，
    ///   也不进 UI 本地化系统，属预期行为。
    static func markdown(notes: [Note], todos: [Todo], generatedAt: Date) -> String {
        markdown(notes: notes, todos: todos, generatedAt: generatedAt, timeZone: .current)
    }

    /// 时区注入版本（L2 测试固定时区；入口默认本地时区，NFR17 同款纯函数口径）。
    static func markdown(notes: [Note], todos: [Todo], generatedAt: Date, timeZone: TimeZone) -> String {
        var lines: [String] = ["# 拾刻导出（\(headerDate(generatedAt, timeZone: timeZone))）"]

        // 便签分两节：置顶（pinnedAt 非空）与其余的"全部"，节内跟随数据原序。
        let pinned = notes.filter { $0.pinnedAt != nil }
        let unpinned = notes.filter { $0.pinnedAt == nil }
        if !pinned.isEmpty {
            lines.append("## 置顶")
            lines.append(contentsOf: noteItemLines(pinned))
        }
        if !unpinned.isEmpty {
            lines.append("## 全部")
            lines.append(contentsOf: noteItemLines(unpinned))
        }

        // 待办五分组（同 TodoGrouping 的判定语义），空节不输出。
        let groups = todoSections(todos: todos, now: generatedAt, timeZone: timeZone)
        let sections: [(title: String, todos: [Todo])] = [
            ("待办 · 逾期", groups.overdue),
            ("待办 · 今天", groups.today),
            ("待办 · 以后", groups.later),
            ("待办 · 无日期", groups.noDate),
            ("待办 · 已完成", groups.completed),
        ]
        for section in sections where !section.todos.isEmpty {
            lines.append("## \(section.title)")
            lines.append(contentsOf: section.todos.map { todoItemLine($0, timeZone: timeZone) })
        }

        return lines.joined(separator: "\n") + "\n"
    }

    /// 便签条目行：`- 内容`，多行内容的续行缩进两空格（保持在同一列表项内）。
    private static func noteItemLines(_ notes: [Note]) -> [String] {
        notes.flatMap { note in
            note.content
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .map { index, line in
                    index == 0 ? "- \(line)" : "  \(line)"
                }
        }
    }

    /// 待办条目行（S3.5-06 的字面格式）：未完成 `- [ ] 标题（yyyy-MM-dd HH:mm）`
    /// （无 due 则无时间括号；全天待办与界面同口径只显日期 `（yyyy-MM-dd）`）；
    /// 已完成 `- [x] 标题`（不带时间括号）。
    private static func todoItemLine(_ todo: Todo, timeZone: TimeZone) -> String {
        if todo.completedAt != nil {
            return "- [x] \(todo.title)"
        }
        guard let due = todo.due else {
            return "- [ ] \(todo.title)"
        }
        if due.hasTime {
            return "- [ ] \(todo.title)（\(dateTimeText(due.date, timeZone: timeZone))）"
        }
        return "- [ ] \(todo.title)（\(dateOnlyText(due.date, timeZone: timeZone))）"
    }

    /// 待办五分组的导出实现（S3.5-06）：与 Shike/Panel/TodoGrouping.swift 的
    /// TodoGrouping.group 同语义——逾期/今天/以后/无日期/已完成，日界为时区的
    /// 当天 [00:00, 24:00)（日历日推进，DST 安全）。不直接复用其函数：分组器按 due
    /// 对组内排序（界面"最近到期在前"），而导出要求节内跟随数据原序，故只复刻
    /// 分组判定、不做组内排序。
    private static func todoSections(
        todos: [Todo],
        now: Date,
        timeZone: TimeZone
    ) -> (overdue: [Todo], today: [Todo], later: [Todo], noDate: [Todo], completed: [Todo]) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayStart = calendar.startOfDay(for: now)
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!

        var overdue: [Todo] = []
        var today: [Todo] = []
        var later: [Todo] = []
        var noDate: [Todo] = []
        var completed: [Todo] = []
        for todo in todos {
            if todo.completedAt != nil {
                completed.append(todo)
            } else if let due = todo.due {
                if due.date < todayStart {
                    overdue.append(todo)
                } else if due.date < tomorrowStart {
                    today.append(todo)
                } else {
                    later.append(todo)
                }
            } else {
                noDate.append(todo)
            }
        }
        return (overdue, today, later, noDate, completed)
    }

    // - MARK: 日期文案（私有；固定 en_US_POSIX，防用户区域设置改写数字与字段序）

    /// 导出标题日期：yyyy年M月d日（中文年月日字面量加引号，防被当作格式占位）。
    private static func headerDate(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy'年'M'月'd'日'"
        return formatter.string(from: date)
    }

    /// 待办时间：yyyy-MM-dd HH:mm（24 小时制）。
    private static func dateTimeText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    /// 全天待办的日期：yyyy-MM-dd（与界面 TimeDisplay 的全天口径一致，只显日期）。
    private static func dateOnlyText(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    // - MARK: JSON

    /// JSON 文档（S3.5-06）：`{"version":1,"generatedAt":ISO8601,"notes":[...],"todos":[...]}`。
    /// Note/Todo 是非 Codable 的域类型（ShikeData 的定义未遵循 Codable），用私有映射类型
    /// ExportedNote/ExportedTodo 过渡；uuid 作跨设备稳定标识，时间统一 ISO8601
    /// （秒级精度——数据库毫秒在导出中舍入；未来需要毫秒对账时随 version 2 演进）。
    /// 可选字段编码为显式 null（键恒在，消费方按稳定 schema 读取），见 encodeOptional。
    static func json(notes: [Note], todos: [Todo], generatedAt: Date) throws -> Data {
        let document = ExportedDocument(
            version: 1,
            generatedAt: generatedAt,
            notes: notes.map { note in
                ExportedNote(
                    uuid: note.uuid,
                    content: note.content,
                    pinnedAt: note.pinnedAt,
                    createdAt: note.createdAt,
                    updatedAt: note.updatedAt,
                    deletedAt: note.deletedAt
                )
            },
            todos: todos.map { todo in
                ExportedTodo(
                    uuid: todo.uuid,
                    title: todo.title,
                    due: todo.due.map { ExportedDue(date: $0.date, hasTime: $0.hasTime) },
                    snoozedUntil: todo.snoozedUntil,
                    completedAt: todo.completedAt,
                    createdAt: todo.createdAt,
                    updatedAt: todo.updatedAt,
                    deletedAt: todo.deletedAt
                )
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        // prettyPrinted：导出文件人也要读；sortedKeys：同版本输出字节稳定（利于比对）。
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }

    /// JSON 导出文档结构（version 1；未来字段演进以 version 区分）。
    private struct ExportedDocument: Codable {
        let version: Int
        let generatedAt: Date
        let notes: [ExportedNote]
        let todos: [ExportedTodo]
    }

    /// 可选字段的显式 null 编码：合成 Codable 会省略 nil 键，导出契约要求键恒在——
    /// 消费方按稳定 schema 读取，version 演进时字段形态不随取值漂移。
    /// 解码仍用合成 init(from:)（显式 null 与缺键都还原为 nil，两代文件通读）。
    private static func encodeOptional<E: Encodable, K: CodingKey>(
        _ value: E?,
        forKey key: K,
        into container: inout KeyedEncodingContainer<K>
    ) throws {
        if let value {
            try container.encode(value, forKey: key)
        } else {
            try container.encodeNil(forKey: key)
        }
    }

    /// 便签的导出投影（Note 非 Codable，字段平移）。
    private struct ExportedNote: Codable {
        let uuid: UUID
        let content: String
        let pinnedAt: Date?
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case uuid, content, pinnedAt, createdAt, updatedAt, deletedAt
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uuid, forKey: .uuid)
            try container.encode(content, forKey: .content)
            try ExportService.encodeOptional(pinnedAt, forKey: .pinnedAt, into: &container)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try ExportService.encodeOptional(deletedAt, forKey: .deletedAt, into: &container)
        }
    }

    /// 待办时间的导出投影（TodoDue 的 date + hasTime）。
    private struct ExportedDue: Codable {
        let date: Date
        let hasTime: Bool
    }

    /// 待办的导出投影（Todo 非 Codable，字段平移）。
    private struct ExportedTodo: Codable {
        let uuid: UUID
        let title: String
        let due: ExportedDue?
        let snoozedUntil: Date?
        let completedAt: Date?
        let createdAt: Date
        let updatedAt: Date
        let deletedAt: Date?

        private enum CodingKeys: String, CodingKey {
            case uuid, title, due, snoozedUntil, completedAt, createdAt, updatedAt, deletedAt
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(uuid, forKey: .uuid)
            try container.encode(title, forKey: .title)
            try ExportService.encodeOptional(due, forKey: .due, into: &container)
            try ExportService.encodeOptional(snoozedUntil, forKey: .snoozedUntil, into: &container)
            try ExportService.encodeOptional(completedAt, forKey: .completedAt, into: &container)
            try container.encode(createdAt, forKey: .createdAt)
            try container.encode(updatedAt, forKey: .updatedAt)
            try ExportService.encodeOptional(deletedAt, forKey: .deletedAt, into: &container)
        }
    }
}
