// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
internal import GRDB

/// 仓储共用设施：挂在 AppDatabase 上，供三个仓储的写路径与观察复用。
extension AppDatabase {
    /// 仓储写路径的唯一入口：
    /// - `simulateWriteFailure` 开启时不访问数据库，直接抛 `writeFailed(.simulated)`；
    /// - 时间戳经 `db.transactionDate` 取自注入时钟，同一事务内相同；
    /// - 失败一律映射为 `ShikeDataError.writeFailed(原因)`，不用 `try?` 吞错。
    func performWrite<T: Sendable>(
        _ operation: @escaping @Sendable (Database) throws -> T
    ) async throws -> T {
        if options.simulateWriteFailure {
            throw ShikeDataError.writeFailed(.simulated)
        }
        do {
            return try await writer.write { database in
                try operation(database)
            }
        } catch let error as ShikeDataError {
            throw error
        } catch {
            throw ShikeDataError.writeFailed(mapFailure(error))
        }
    }

    /// 行存在性检查：写方法的"目标状态已达成"路径用它与 notFound 区分。
    static func exists(
        _ table: String,
        id: Int64,
        in database: Database
    ) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: "SELECT 1 FROM \(table) WHERE id = ?",
            arguments: [id]
        ) ?? false
    }
}

/// 观察流：把 GRDB 的 ValueObservation 桥接为 AsyncThrowingStream。
/// - 流在构造时即开始观察（急切启动）；去重、先推当前值；取消消费的 Task
///   即停止观察（不消费时的清理依赖流的 deinit 触发 onTermination）；
/// - 读取失败经异常路径以 `readFailed(原因)` 结束；
/// - 实测（GRDB 7.11.1）：被观察的表被删除后，观察静默挂起——不重取、不
///   报错、不结束，流将无限等待；此类结构变化由外部流程（备份/迁移）避免，
///   1.17 写回时需在契约中写明这一边界。
func observationStream<Value: Sendable & Equatable>(
    reader: any DatabaseReader,
    tracking makeValue: @escaping @Sendable (Database) throws -> Value
) -> AsyncThrowingStream<Value, any Error> {
    // 注意：不用 trackingConstantRegion——实测它对"表被删除"这类结构变化
    // 既不重取也不报错，观察会静默挂起；tracking 在任何提交后重取，
    // 读失败会正常进入 onError/异常路径（阶段 0 的数据量下代价可接受）。
    let observation = ValueObservation
        .tracking(makeValue)
        .removeDuplicates()

    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                for try await value in observation.values(in: reader) {
                    continuation.yield(value)
                }
                // 活观察不会自然结束；万一走到这里，按读取通道断开处理
                // （消费方已离开时，对已终止的流再 finish 是无害空操作）。
                continuation.finish(throwing: ShikeDataError.readFailed(.ioError))
            } catch let error as ShikeDataError {
                continuation.finish(throwing: error)
            } catch {
                continuation.finish(throwing: ShikeDataError.readFailed(mapFailure(error)))
            }
        }
        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
