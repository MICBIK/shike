// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import os
import ShikeData

/// 退出冲刷（W1 数据安全）：⌘Q 时进程随即退出，三面既有保存路径都是
/// fire-and-forget Task（面板行、主窗口行、卡片正文），最后一次编辑可能丢失。
/// perform 用 Task.detached 包住异步写并以信号量同步等待——**必须 detached**：
/// `Task { }` 继承 @MainActor 隔离，主线程被信号量阻塞时任务永不启动（死锁）；
/// 仓储是 Sendable struct，脱离 actor 调用安全。超时放弃只记日志（退出场景无 UI）。
enum SyncFlush {
    /// 同步执行一段异步写：在超时内完成则本函数返回时写入已落库；超时则放弃
    /// 等待（写入仍在后台继续，但进程可能先死——日志是唯一痕迹）。
    static func perform(
        timeout: Duration = .seconds(3),
        _ work: @escaping @Sendable () async -> Void
    ) {
        let semaphore = DispatchSemaphore(value: 0)
        // userInitiated：调用方（退出/接手播种）在同步等这个写，别让它排在后台队列尾。
        Task.detached(priority: .userInitiated) {
            await work()
            semaphore.signal()
        }
        let nanoseconds = Int(timeout.components.seconds) * 1_000_000_000
            + Int(timeout.components.attoseconds / 1_000_000_000)
        if semaphore.wait(timeout: .now() + .nanoseconds(nanoseconds)) == .timedOut {
            Log.app.error("退出冲刷超时放弃（写入可能未落库）")
        }
    }

    /// 便签内容的冲刷（同 PanelModel.saveNoteContent 数据语义）：trim 后为空→软删除
    /// （幂等，已删除返回 false 静默）、内容未变跳过；行不在调用方快照时兜底直写
    /// （打磨轮 2026-10-03，C4 对齐：面板观察流失败而行健在时，在线保存已兜底直写、
    /// 冲刷再静默跳过=最后一次编辑无声丢失；无快照可比，跳过"未变跳过"）。
    /// 失败记日志（不含内容，Log 纪律）。snapshotContent 取调用方自己的快照——
    /// 面板与主窗口各看各的，卡片路径同既有写路径取面板快照。
    static func noteContent(
        _ id: Note.ID,
        text: String,
        snapshotContent: String?,
        repository: NoteRepository
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            perform {
                do {
                    _ = try await repository.softDelete(id)
                } catch {
                    Log.data.error("退出冲刷便签软删除失败：\((error as? ShikeDataError)?.classification ?? "unknown", privacy: .public)")
                }
            }
        } else if snapshotContent != text {
            perform {
                do {
                    try await repository.updateContent(id, to: text)
                } catch {
                    Log.data.error("退出冲刷便签内容失败：\((error as? ShikeDataError)?.classification ?? "unknown", privacy: .public)")
                }
            }
        }
    }

    /// 待办标题的冲刷（同 PanelModel.saveTodoTitle 数据语义）：空标题不保存
    /// （回退原标题）、内容未变跳过；行不在调用方快照时兜底直写（C4 对齐，
    /// 同 noteContent）。失败记日志。
    static func todoTitle(
        _ id: Todo.ID,
        text: String,
        snapshotTitle: String?,
        repository: TodoRepository
    ) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              snapshotTitle != text
        else { return }
        perform {
            do {
                try await repository.updateTitle(id, to: text)
            } catch {
                Log.data.error("退出冲刷待办标题失败：\((error as? ShikeDataError)?.classification ?? "unknown", privacy: .public)")
            }
        }
    }
}
