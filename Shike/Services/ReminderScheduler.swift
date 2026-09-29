// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import AppKit
import Foundation
import os
import ShikeData

/// 通知调度（S2-05，04 §6.7）：以数据库（经待办观察流的快照）为准核对系统中
/// 已排的通知——按"全部撤销 + 按计划重排"实现，天然幂等（NFR20）：相同数据
/// 重复 reconcile 不产生重复通知。
/// 对账时机：启动、待办数据变化（0.5 秒合并，NFR21）、跨天、唤醒、提醒设置变化。
@MainActor
final class ReminderScheduler {
    private let scheduling: NotificationScheduling
    private let todosProvider: () -> [Todo]
    private let preferences: Preferences
    private let timeZoneProvider: () -> TimeZone
    private let nowProvider: () -> Date

    /// 数据变化的对账合并窗口（NFR21）。
    static let debounceInterval: TimeInterval = 0.5

    private var debounceTask: Task<Void, Never>?
    /// nonisolated(unsafe)：deinit 里移除观察者（释放后不再有订阅，与 PanelModel 同款约定）。
    nonisolated(unsafe) private var systemEventObservers: [any NSObjectProtocol] = []
    private(set) var reconcileCount = 0
    /// 重入合并：对账在途时再来的请求置脏标记，完成后补跑一次（盲审 F2——两次
    /// 对账在 XPC 挂起点交错会残留已删除待办的幽灵通知）。
    private var isReconciling = false
    private var reconcileAgain = false
    /// 上次对账的计划（标识 → 触发时刻）：差量检测"已变化"，未变的跳过（盲审 F5）。
    private var lastPlanned: [String: Date] = [:]

    init(
        scheduling: NotificationScheduling,
        todosProvider: @escaping () -> [Todo],
        preferences: Preferences,
        timeZoneProvider: @escaping () -> TimeZone,
        nowProvider: @escaping () -> Date = { Date() }
    ) {
        self.scheduling = scheduling
        self.todosProvider = todosProvider
        self.preferences = preferences
        self.timeZoneProvider = timeZoneProvider
        self.nowProvider = nowProvider
    }

    deinit {
        systemEventObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// 对账入口（重入安全）：在途时再来的请求置脏标记，完成后补跑一次（盲审 F2）。
    func reconcile() async {
        if isReconciling {
            reconcileAgain = true
            return
        }
        isReconciling = true
        await performReconcile()
        isReconciling = false
        if reconcileAgain {
            reconcileAgain = false
            await reconcile()
        }
    }

    /// 对账一次：差量对账——只撤销计划外的与时刻已变化的，只新增/重写
    /// 新增或变化的条目（减少 XPC 次数与"撤销-重排"间的崩溃窗口，盲审 F5）。
    /// 只管理 uuid 形态的标识（盲审 F4）。
    private func performReconcile() async {
        let now = nowProvider()
        let plan = ReminderPlan.plan(
            todos: todosProvider(),
            now: now,
            timeZone: timeZoneProvider(),
            allDayMinutes: clampedAllDayMinutes
        )
        let planned = Dictionary(uniqueKeysWithValues: plan.map { ($0.todoUUID.uuidString, $0.fireDate) })

        let systemPending = await scheduling.pendingIdentifiers()
        // 撤销：系统在排但不在计划里的 uuid 形态标识；以及时刻已变化的（随后重排）
        var toRemove = systemPending.filter { identifier in
            guard UUID(uuidString: identifier) != nil else { return false }
            return planned[identifier] == nil || lastPlanned[identifier] != planned[identifier]
        }
        // 补排：新增（系统没有）或时刻相对上次计划已变化的
        let toAdd = plan.filter { reminder in
            let identifier = reminder.todoUUID.uuidString
            return !systemPending.contains(identifier) || lastPlanned[identifier] != reminder.fireDate
        }
        toRemove.append(contentsOf: toAdd.map { $0.todoUUID.uuidString })
        if !toRemove.isEmpty {
            await scheduling.removePending(identifiers: toRemove)
        }
        for reminder in toAdd {
            await scheduling.add(
                identifier: reminder.todoUUID.uuidString,
                title: reminder.title,
                body: NotificationCoordinator.body(
                    due: TodoDue(date: reminder.fireDate, hasTime: reminder.hasTime),
                    now: now,
                    timeZone: timeZoneProvider()
                ),
                userInfo: ["uuid": reminder.todoUUID.uuidString],
                fireDate: reminder.fireDate
            )
        }
        lastPlanned = planned
        reconcileCount += 1
        Log.app.info("通知对账完成：计划 \(plan.count, privacy: .public) 条，撤销 \(toRemove.count, privacy: .public) 条")
    }

    /// 数据变化入口：0.5 秒内的多次变化合并为一次对账（NFR21）。
    func scheduleReconcile() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(Self.debounceInterval * 1000)))
            guard !Task.isCancelled else { return }
            await self?.reconcile()
        }
    }

    /// 订阅跨天与唤醒（App 启动时一次；L2 直接调 handleDayChanged/handleWake 验证路由）。
    func startObservingSystemEvents() {
        let dayChanged = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleDayChanged() }
        }
        let wake = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.handleWake() }
        }
        systemEventObservers = [dayChanged, wake]
    }

    /// 跨天：重新对账（"今天"全部重算）。
    func handleDayChanged() {
        scheduleReconcile()
    }

    /// 唤醒：重新对账（睡眠期间错过的对账补上）。
    func handleWake() {
        scheduleReconcile()
    }

    /// 全天提醒分钟数（钳制是调用方的责任，ReminderPlan 契约）。
    private var clampedAllDayMinutes: Int {
        min(1439, max(0, preferences.reminderAllDayMinutes))
    }
}
