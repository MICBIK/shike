// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// 数据库的打开与生命周期（data-layer.md「AppDatabase」）。
/// 公开 API 不出现 GRDB 类型：连接作为内部存储，由仓储与观察使用。
public final class AppDatabase: Sendable {
    /// 打开与运行参数。
    public struct Options: Sendable {
        /// 用于全天规范化与备份命名。
        public var timeZone: TimeZone
        /// 所有时间戳的来源；经 GRDB 的 transactionClock 注入，同一事务内取值相同。
        public var clock: @Sendable () -> Date
        /// 对应调试启动参数 -ShikeSimulateWriteFailure。
        public var simulateWriteFailure: Bool

        public init(
            timeZone: TimeZone = .current,
            clock: @escaping @Sendable () -> Date = { Date() },
            simulateWriteFailure: Bool = false
        ) {
            self.timeZone = timeZone
            self.clock = clock
            self.simulateWriteFailure = simulateWriteFailure
        }
    }

    public static let fileName = "shike.sqlite"

    /// 仓储与观察使用；公开签名中不出现 GRDB 类型。
    let writer: any DatabaseWriter
    /// timeZone/simulateWriteFailure 由 Story 1.4 起的仓储写路径与备份使用。
    private let options: Options

    private init(writer: any DatabaseWriter, options: Options) {
        self.writer = writer
        self.options = options
    }

    private static func configuration(_ options: Options) -> Configuration {
        var configuration = Configuration()
        // 时间戳全部取自注入时钟：同一事务内相同，测试可确定（data-layer.md）。
        configuration.transactionClock = .custom { _ in options.clock() }
        return configuration
    }

    /// 打开数据目录中的库；目录不存在时创建。同步执行，启动时立即知道成败。
    /// 任何一步失败都抛 `openFailed(原因)`，不创建替代库（ADR-013）。
    public static func open(directory: URL, options: Options = .init()) throws -> AppDatabase {
        try open(directory: directory, options: options, migrator: makeMigrator())
    }

    /// 迁移器可注入的内部入口：测试用它在 v1 之后追加测试迁移；生产代码只注册 v1。
    static func open(directory: URL, options: Options, migrator: DatabaseMigrator) throws -> AppDatabase {
        do {
            // 1. 数据目录必须是绝对路径的文件 URL
            guard directory.isFileURL, directory.path.hasPrefix("/") else {
                throw ShikeDataError.openFailed(.invalidLocation)
            }
            // 2. 创建目录
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // 3. DatabasePool（WAL）
            let pool = try DatabasePool(
                path: directory.appendingPathComponent(Self.fileName).path,
                configuration: configuration(options))
            // 4. 库来自更新的版本时失败，不写入
            if try pool.read({ database in try migrator.hasBeenSuperseded(database) }) {
                throw ShikeDataError.openFailed(.newerSchema)
            }
            // （迁移前备份的步骤由 Story 1.14 接入）
            // 5. 在事务中执行迁移
            try migrator.migrate(pool)
            return AppDatabase(writer: pool, options: options)
        } catch let error as ShikeDataError {
            throw error
        } catch {
            throw ShikeDataError.openFailed(mapFailure(error))
        }
    }

    /// 内存库，供测试与 SwiftUI 预览使用；执行与文件库相同的迁移。
    public static func inMemory(options: Options = .init()) throws -> AppDatabase {
        do {
            let queue = try DatabaseQueue(configuration: configuration(options))
            try makeMigrator().migrate(queue)
            return AppDatabase(writer: queue, options: options)
        } catch let error as ShikeDataError {
            throw error
        } catch {
            throw ShikeDataError.openFailed(mapFailure(error))
        }
    }

    /// 迁移器由内部工厂创建：测试可以注入 v1 之后的测试迁移，生产代码只注册正式迁移
    /// （data-layer.md「迁移前备份·可测试性」）。
    static func makeMigrator(
        additionalMigrations: [(identifier: String, migrate: @Sendable (Database) throws -> Void)] = []
    ) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1", migrate: migrateV1)
        for additional in additionalMigrations {
            migrator.registerMigration(additional.identifier, migrate: additional.migrate)
        }
        return migrator
    }

    /// v1 表结构（04 §5；data-layer.md「结构细节」）。已发布的迁移永不修改（ADR-006）。
    private static func migrateV1(_ database: Database) throws {
        try database.create(table: "note") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("uuid", .text).notNull().unique()
            table.column("content", .text).notNull()
            table.column("pinnedAt", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
        }
        try database.create(index: "note_on_deletedAt", on: "note", columns: ["deletedAt"])

        try database.create(table: "todo") { table in
            table.autoIncrementedPrimaryKey("id")
            table.column("uuid", .text).notNull().unique()
            table.column("title", .text).notNull()
            table.column("dueAt", .datetime)
            table.column("dueHasTime", .boolean).notNull().defaults(to: false)
            table.column("snoozedUntil", .datetime)
            table.column("completedAt", .datetime)
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("deletedAt", .datetime)
            // 04 §5 规定的唯一 CHECK；枚举与取值范围由 Swift 类型保证
            table.check(sql: "dueHasTime = 0 OR dueAt IS NOT NULL")
        }
        try database.create(index: "todo_on_deletedAt", on: "todo", columns: ["deletedAt"])
        try database.create(index: "todo_on_completedAt_dueAt", on: "todo", columns: ["completedAt", "dueAt"])

        try database.create(table: "stickyCard") { table in
            table.autoIncrementedPrimaryKey("id")
            // 一张便签最多一张卡片；便签被永久删除时级联删除
            table.column("noteId", .integer).notNull().unique().references("note", onDelete: .cascade)
            table.column("x", .real).notNull()
            table.column("y", .real).notNull()
            table.column("width", .real).notNull()
            table.column("height", .real).notNull()
            table.column("level", .text).notNull()
            table.column("color", .text).notNull()
            table.column("fontSize", .text).notNull()
            table.column("autoHide", .boolean).notNull()
            table.column("hideDelay", .real).notNull()
            table.column("hiddenOpacity", .real).notNull()
            table.column("allSpaces", .boolean).notNull()
            table.column("showOverFullScreen", .boolean).notNull()
            table.column("createdAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
        }
    }
}
