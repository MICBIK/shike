// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo Services/LaunchAtLoginService.swift 移植；去掉单例、旧辅助程序（
// SMLoginItemSetEnabled）迁移与 unavailable 分支的发布残留；系统访问经注入闭包，
// L2 用替身验证状态映射与开关，不真实调用 SMAppService（2026-09-28）。

import Foundation
import ServiceManagement

/// 开机自启（S1-08，ADR-011：不启用沙盒）：基于 SMAppService.mainApp。
/// 状态每次从系统实时读取；"需要批准"时由设置页引导打开登录项设置。
@MainActor
final class LaunchAtLoginService {
    enum Status: Equatable {
        case enabled
        case disabled
        case requiresApproval
        case notRegistered
    }

    private(set) var status: Status = .notRegistered

    private let statusProvider: () -> SMAppService.Status
    private let registerAction: () throws -> Void
    private let unregisterAction: () throws -> Void
    private let openSettingsAction: () -> Void

    init(
        statusProvider: @escaping () -> SMAppService.Status = { SMAppService.mainApp.status },
        register: @escaping () throws -> Void = { try SMAppService.mainApp.register() },
        unregister: @escaping () throws -> Void = { try SMAppService.mainApp.unregister() },
        openSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.statusProvider = statusProvider
        self.registerAction = register
        self.unregisterAction = unregister
        self.openSettingsAction = openSettings
        refresh() // 初值即从系统读取，避免首次 setEnabled 用陈旧状态做幂等判断
    }

    /// 开关语义上的"已启用"：需要批准也算启用（注册意向已表达）。
    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    /// 每次从系统读取状态（03 §9：状态以系统为准，不缓存决策）。
    func refresh() {
        switch statusProvider() {
        case .enabled: status = .enabled
        case .requiresApproval: status = .requiresApproval
        case .notFound, .notRegistered: status = .notRegistered
        @unknown default: status = .notRegistered
        }
    }

    /// 开关（右键菜单与设置-通用共用）。注册/注销失败经 error 上浮由调用方提示，
    /// 状态以 refresh 后的系统实际为准。
    func setEnabled(_ enabled: Bool) throws {
        let isRegistered = status == .enabled || status == .requiresApproval
        guard isRegistered != enabled else {
            refresh()
            return
        }
        if enabled {
            try registerAction()
        } else {
            try unregisterAction()
        }
        refresh()
    }

    /// 打开系统设置的登录项页面（需要批准时的引导）。
    func openSystemSettings() {
        openSettingsAction()
    }
}
