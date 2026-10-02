// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import Observation

/// 主窗口统一反馈条（W3）：主窗口底部 safeAreaInset 的唯一文案来源——
/// 导出成功/失败、回收站写失败、三模型读失败、面板写失败旁路都写它。
/// 3 秒自清 + 日志留痕（与 TrashModel.showStatus / PanelModel.deletedBar
/// 同一自清通道）；面板收着时，这里是主窗口失败可见的唯一出口。
@MainActor
@Observable
final class MainFeedbackModel {
    /// 条尾动作（打磨二轮卡B）：删除反馈带「撤销」（调面板同一撤销栈）、
    /// 写失败反馈带「重试」（同一横幅重试闭包）；nil = 纯文案。
    /// 二者不共存——一次 show 只携带一个动作。
    enum Action {
        /// 撤销最近一次删除（显示窗口放宽到 5 秒，与面板撤销条同语义）。
        case undo(handler: () -> Void)
        /// 重试失败的写（显示窗口维持 3 秒自清不变）。
        case retry(handler: () -> Void)

        /// 条尾按钮文案（复用面板撤销条/横幅的既有键）。
        var label: String {
            switch self {
            case .undo: String(localized: .undoBarUndo)
            case .retry: String(localized: .bannerRetry)
            }
        }
    }

    /// 当前反馈文案；nil = 不显示。
    private(set) var message: String?

    /// 当前条尾动作；nil = 纯文案（隐藏时一并清除，防陈旧按钮残留）。
    private(set) var action: Action?

    /// 清除延迟（L2 测试注入缩短；默认 3 秒）。
    @ObservationIgnored var hideDelay: Duration = .seconds(3)
    /// 撤销类反馈的显示窗口（L2 测试注入缩短；5 秒与面板撤销条 deletedBarHideDelay 一致）。
    @ObservationIgnored var undoHideDelay: Duration = .seconds(5)
    /// nonisolated(unsafe) 供 deinit 取消（Task 是 Sendable，取消本身 Sendable 安全）。
    @ObservationIgnored nonisolated(unsafe) private var hideTask: Task<Void, Never>?
    /// 反馈文案的代次（show 递增）——语义同 TrashModel.statusToken，保留给
    /// "默认成功文案不覆盖失败文案"的未来扩展；当前仅 show 单通道。
    @ObservationIgnored private var token = 0

    deinit {
        hideTask?.cancel()
    }

    /// 显示反馈并排清除任务（连续调用重启计时，TrashModel.showStatus 同款）。
    /// 携带 .undo 时窗口用 undoHideDelay（5 秒），其余 3 秒。
    func show(_ message: String, action: Action? = nil) {
        token += 1
        self.message = message
        self.action = action
        hideTask?.cancel()
        let delay: Duration
        if case .undo? = action {
            delay = undoHideDelay
        } else {
            delay = hideDelay
        }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.message = nil
            self?.action = nil
        }
    }

    /// 条尾按钮动作（撤销/重试共用）：先收起反馈条再执行——撤销结果由面板
    /// 撤销条/列表回弹呈现，重试结果由下一次 report（成功清横幅/失败再报）呈现；
    /// 立即收起防同面重复点击（跨面双击与面板自身双击同属既有风险面，不在此扩权）。
    func performAction() {
        guard let action else { return }
        hideTask?.cancel()
        message = nil
        self.action = nil
        switch action {
        case .undo(let handler): handler()
        case .retry(let handler): handler()
        }
    }
}
