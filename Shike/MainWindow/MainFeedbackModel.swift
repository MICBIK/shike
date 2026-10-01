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
    /// 当前反馈文案；nil = 不显示。
    private(set) var message: String?

    /// 清除延迟（L2 测试注入缩短；默认 3 秒）。
    @ObservationIgnored var hideDelay: Duration = .seconds(3)
    /// nonisolated(unsafe) 供 deinit 取消（Task 是 Sendable，取消本身 Sendable 安全）。
    @ObservationIgnored nonisolated(unsafe) private var hideTask: Task<Void, Never>?
    /// 反馈文案的代次（show 递增）——语义同 TrashModel.statusToken，保留给
    /// "默认成功文案不覆盖失败文案"的未来扩展；当前仅 show 单通道。
    @ObservationIgnored private var token = 0

    deinit {
        hideTask?.cancel()
    }

    /// 显示反馈并排 3 秒清除任务（连续调用重启计时，TrashModel.showStatus 同款）。
    func show(_ message: String) {
        token += 1
        self.message = message
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: self?.hideDelay ?? .seconds(3))
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }
}
