// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Observation
import os
import ShikeData

/// 面板状态（app-shell.md「组件契约」）：模式、两个列表的数据与提示条。
@MainActor
@Observable
final class PanelModel {
    /// 顶栏分段控件的模式（03 §3）；默认便签，重启回到便签，不写入偏好设置。
    enum Mode: String, CaseIterable, Sendable {
        case note
        case todo
    }

    /// 顶栏下方的提示条（03 §3）；重试动作单独保存（闭包不参与相等性）。
    struct BannerState: Equatable {
        enum Kind: Equatable {
            case saveFailed(DataFailureReason)
            case loadFailed(DataFailureReason)
        }

        let kind: Kind

        var message: String {
            switch kind {
            case .saveFailed(let reason):
                String(localized: .bannerSaveFailed(ErrorText.reason(reason)))
            case .loadFailed(let reason):
                String(localized: .bannerLoadFailed(ErrorText.reason(reason)))
            }
        }
    }

    var mode: Mode = .note

    private(set) var notes: [NoteListItem] = []
    private(set) var todos: [Todo] = []
    private(set) var banner: BannerState?

    private let noteRepository: NoteRepository
    private let todoRepository: TodoRepository
    @ObservationIgnored private var bannerRetry: (() -> Void)?
    /// 只有 start()（重新订阅）之后收到的首批数据才允许清除读取失败提示条；
    /// 否则另一条仍在运行的流的任意更新会把提示条误清掉。
    @ObservationIgnored private var pendingLoadBannerClear = false
    /// @ObservationIgnored + nonisolated(unsafe)（Task 是 Sendable，取消本身 Sendable 安全）
    /// 只为让 deinit 能停止任务；deinit 与 start/stop 不会并发发生（模型释放后不再有订阅）。
    @ObservationIgnored nonisolated(unsafe) private var noteTask: Task<Void, Never>?
    @ObservationIgnored nonisolated(unsafe) private var todoTask: Task<Void, Never>?

    init(noteRepository: NoteRepository, todoRepository: TodoRepository) {
        self.noteRepository = noteRepository
        self.todoRepository = todoRepository
    }

    deinit {
        // Task.cancel 是 nonisolated 的，可在 deinit 调用；释放时停止观察。
        noteTask?.cancel()
        todoTask?.cancel()
    }

    /// 订阅两类观察流（app-shell.md：start() 订阅便签与待办两个观察）。
    /// 读取失败提示条的"重试"会重新调用本方法，即重新订阅。
    func start() {
        noteTask?.cancel()
        todoTask?.cancel()
        pendingLoadBannerClear = true
        noteTask = Task { [weak self] in await self?.consumeNotes() }
        todoTask = Task { [weak self] in await self?.consumeTodos() }
    }

    /// 停止消费（applicationWillTerminate 调用）。
    func stop() {
        noteTask?.cancel()
        todoTask?.cancel()
        noteTask = nil
        todoTask = nil
        pendingLoadBannerClear = false
    }

    private func consumeNotes() async {
        await runNotes(noteRepository.observeActive())
    }

    private func consumeTodos() async {
        await runTodos(todoRepository.observeActive())
    }

    /// 消费一个便签观察流。internal 供 L2 直接驱动真实的失败处理链路。
    func runNotes(_ stream: AsyncThrowingStream<[NoteListItem], any Error>) async {
        do {
            for try await items in stream {
                notes = items
                clearLoadBannerIfNeeded()
            }
            // data-layer.md「观察」：非取消的正常结束是故障信号（仓储层已把它转成
            // readFailed 抛出；这里兜底，防止数据层语义变化后静默失效）。
            reportIfNotCancelled(.readFailed(.ioError))
        } catch {
            handleStreamFailure(error)
        }
    }

    /// 消费一个待办观察流。internal 供 L2 直接驱动真实的失败处理链路。
    func runTodos(_ stream: AsyncThrowingStream<[Todo], any Error>) async {
        do {
            for try await items in stream {
                todos = items
                clearLoadBannerIfNeeded()
            }
            reportIfNotCancelled(.readFailed(.ioError))
        } catch {
            handleStreamFailure(error)
        }
    }

    private func reportIfNotCancelled(_ error: ShikeDataError) {
        guard !Task.isCancelled else { return }
        report(error, retry: {})
    }

    /// 观察流以异常结束：取消不算失败；其他错误统一按读取失败上报。
    private func handleStreamFailure(_ error: Error) {
        guard !(error is CancellationError) else { return }
        let dataError = (error as? ShikeDataError) ?? ShikeDataError.readFailed(.ioError)
        report(dataError, retry: {})
    }

    /// 重新订阅成功（收到首批数据）后清除读取失败提示条；保存失败提示条不受数据更新影响。
    private func clearLoadBannerIfNeeded() {
        guard pendingLoadBannerClear, case .loadFailed = banner?.kind else { return }
        pendingLoadBannerClear = false
        banner = nil
    }

    /// 生成提示条（app-shell.md：读取失败时"重试"会重新订阅）。
    func report(_ error: ShikeDataError, retry: @escaping () -> Void) {
        Log.data.info("面板提示条：\(error.classification, privacy: .public)")
        switch error {
        case .readFailed(let reason):
            banner = BannerState(kind: .loadFailed(reason))
            bannerRetry = { [weak self] in self?.start() }
            pendingLoadBannerClear = false
        case .writeFailed(let reason):
            banner = BannerState(kind: .saveFailed(reason))
            bannerRetry = retry
        case .openFailed(let reason), .backupFailed(let reason):
            // 阶段 0 的面板不会收到这两类；按保存失败展示，避免静默。
            banner = BannerState(kind: .saveFailed(reason))
            bannerRetry = retry
        case .notFound:
            banner = BannerState(kind: .saveFailed(.unknown(code: 0)))
            bannerRetry = retry
        }
    }

    /// 提示条上的"重试"按钮。
    func retryBanner() {
        bannerRetry?()
    }
}
