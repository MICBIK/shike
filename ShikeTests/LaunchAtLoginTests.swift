// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ServiceManagement
import Testing

@testable import Shike

/// Story 2.9：开机自启服务（app-shell.md「组件契约」、03 §9/§14）。
/// SMAppService 的真实注册/注销路径由人工验收（L3，注销重登录）；这里用替身验证映射与开关。
@MainActor
struct LaunchAtLoginTests {
    private func makeService(
        systemStatus: SMAppService.Status,
        register: @escaping () throws -> Void = {},
        unregister: @escaping () throws -> Void = {}
    ) -> LaunchAtLoginService {
        LaunchAtLoginService(
            statusProvider: { systemStatus },
            register: register,
            unregister: unregister,
            openSettings: {}
        )
    }

    @Test("状态映射：enabled/requiresApproval/notFound→notRegistered")
    func statusMapping() {
        let enabled = makeService(systemStatus: .enabled)
        enabled.refresh()
        #expect(enabled.status == .enabled)
        #expect(enabled.isEnabled)

        let approval = makeService(systemStatus: .requiresApproval)
        approval.refresh()
        #expect(approval.status == .requiresApproval)
        #expect(approval.isEnabled) // 需要批准也算启用（注册意向已表达）

        let notRegistered = makeService(systemStatus: .notFound)
        notRegistered.refresh()
        #expect(notRegistered.status == .notRegistered)
        #expect(!notRegistered.isEnabled)
    }

    @Test("setEnabled(true)：调用 register 并刷新为 enabled；setEnabled(false)：unregister 后回到 notRegistered")
    func setEnabledToggles() throws {
        // 闭包按引用捕获 var：register/unregister 修改"系统状态"，refresh 读到最新值
        var systemSays: SMAppService.Status = .notRegistered
        var registerCalls = 0
        var unregisterCalls = 0
        let service = LaunchAtLoginService(
            statusProvider: { systemSays },
            register: {
                registerCalls += 1
                systemSays = .enabled
            },
            unregister: {
                unregisterCalls += 1
                systemSays = .notRegistered
            },
            openSettings: {}
        )
        service.refresh()
        #expect(service.status == .notRegistered)

        try service.setEnabled(true)
        #expect(registerCalls == 1)
        #expect(service.status == .enabled)
        #expect(service.isEnabled)

        try service.setEnabled(false)
        #expect(unregisterCalls == 1)
        #expect(service.status == .notRegistered)
        #expect(!service.isEnabled)
    }

    @Test("幂等：已是目标状态时不调用 register/unregister")
    func setEnabledIdempotent() throws {
        var registerCalls = 0
        let service = LaunchAtLoginService(
            statusProvider: { .enabled },
            register: { registerCalls += 1 },
            unregister: {},
            openSettings: {}
        )
        try service.setEnabled(true) // 已启用：不重复注册
        #expect(registerCalls == 0)
        #expect(service.status == .enabled)
    }

    @Test("注册失败：错误上浮，状态保持系统实际值")
    func registerFailureSurfaces() {
        struct Boom: Error {}
        let service = makeService(
            systemStatus: .notRegistered,
            register: { throw Boom() }
        )
        service.refresh()
        #expect(throws: Boom.self) {
            try service.setEnabled(true)
        }
        #expect(service.status == .notRegistered)
    }
}
