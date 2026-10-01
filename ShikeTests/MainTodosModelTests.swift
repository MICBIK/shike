// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation
import ShikeData
import Testing

@testable import Shike
@testable import ShikeData // Todo 的 memberwise init 是 internal（包内约定）

/// S3.5-04：主窗口-待办视图的模型（03 §16.4）。
/// 走 AppEnvironment 组装的真实仓储（in-memory），分组断言直接复用面板分组器
/// TodoGrouping（分组逻辑本身由 TodoGroupingTests 覆盖，这里验证接线与转发）。
/// 时间确定性分工：due 用固定基准构造、模型注入固定 now；仓储时间戳
/// （createdAt/completedAt）用 AppDatabase.Options(clock:) 注入。
@MainActor
struct MainTodosModelTests {
    private static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    /// 基准：2026-09-29（周二）10:00 Asia/Shanghai。
    private static let now: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 29
        components.hour = 10
        return calendar.date(from: components)!
    }()

    private func makeEnvironment(clock: (@Sendable () -> Date)? = nil) throws -> (AppEnvironment, String) {
        let suiteName = "shike-tests-\(UUID().uuidString)"
        let database = try clock.map { try AppDatabase.inMemory(options: AppDatabase.Options(clock: $0)) }
            ?? AppDatabase.inMemory()
        let environment = AppEnvironment(
            database: database,
            preferences: Preferences(defaults: UserDefaults(suiteName: suiteName)!),
            dataDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("shike-tests-main-todos-\(UUID().uuidString)", isDirectory: true)
        )
        return (environment, suiteName)
    }

    /// 组装接好真实观察流的模型（now/时区注入固定值，分组判定不随机器时间漂移）。
    private func makeModel(_ environment: AppEnvironment) -> MainTodosModel {
        let model = MainTodosModel()
        model.timeZone = Self.timeZone
        model.now = { Self.now }
        model.observeTodos = { environment.todoRepository.observeActive() }
        return model
    }

    private func waitUntil(
        _ model: MainTodosModel,
        timeoutSeconds: Double = 2,
        _ label: String = "",
        _ condition: (MainTodosModel) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition(model) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        if condition(model) { return }
        Issue.record("等待超时：\(label)")
    }

    /// 固定基准（Self.now）± n 天的某时刻（默认正午，避开任何时区的日界）。
    private func date(_ daysFromNow: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.timeZone
        let day = calendar.date(byAdding: .day, value: daysFromNow, to: calendar.startOfDay(for: Self.now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    /// 一次性流：runTodos 消费完即返回，测试确定性收尾。
    private func oneShot(_ items: [Todo]) -> AsyncThrowingStream<[Todo], any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(items)
            continuation.finish()
        }
    }

    /// 立即以读取失败收尾的流（观察流异常结束形态）。
    private func failingStream() -> AsyncThrowingStream<[Todo], any Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: ShikeDataError.readFailed(.ioError))
        }
    }

    @Test("五分组：带时间（逾期/今天/以后）、无日期、已完成各归其组，组内排序与面板分组器一致")
    func groupingMembershipAndOrder() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        model.start()
        defer { model.stop() }
        _ = try await environment.todoRepository.create(title: "逾期", due: TodoDue(date: date(-1), hasTime: true))
        _ = try await environment.todoRepository.create(title: "今天晚", due: TodoDue(date: date(0, hour: 15), hasTime: true))
        _ = try await environment.todoRepository.create(title: "今天早", due: TodoDue(date: date(0, hour: 9), hasTime: true))
        _ = try await environment.todoRepository.create(title: "明天", due: TodoDue(date: date(1), hasTime: true))
        _ = try await environment.todoRepository.create(title: "后天", due: TodoDue(date: date(2), hasTime: true))
        _ = try await environment.todoRepository.create(title: "无日期", due: nil)
        let done = try await environment.todoRepository.create(title: "已完成", due: nil)
        try await environment.todoRepository.setCompleted(done.id, true)

        // 等到"已完成"真正落到已完成组（防创建帧与完成帧之间的竞态伪装成通过）
        try await waitUntil(model, "已完成组就位") { $0.groups.completed.map(\.title) == ["已完成"] }

        let groups = model.groups
        #expect(groups.overdue.map(\.title) == ["逾期"])
        #expect(groups.today.map(\.title) == ["今天早", "今天晚"]) // 组内 due 升序
        #expect(groups.later.map(\.title) == ["明天", "后天"])
        #expect(groups.noDate.map(\.title) == ["无日期"])
        #expect(groups.completed.map(\.title) == ["已完成"])
    }

    @Test("搜索：标题不区分大小写过滤（含已完成）；空白关键词视为不过滤；无命中全组为空")
    func searchFiltersByTitle() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        model.start()
        defer { model.stop() }
        _ = try await environment.todoRepository.create(title: "买牛奶", due: nil)
        _ = try await environment.todoRepository.create(title: "Buy Milk", due: nil)
        let done = try await environment.todoRepository.create(title: "交牛奶报告", due: nil)
        try await environment.todoRepository.setCompleted(done.id, true)

        // 等到已完成帧落地（只等 count==3 会在创建帧与完成帧之间竞态误判）
        try await waitUntil(model, "三条待办到位且已完成组就位") {
            $0.todos.count == 3 && $0.groups.completed.count == 1
        }

        // 不过滤：未完成两条在无日期组、已完成一条在已完成组
        model.searchText = ""
        #expect(model.groups.noDate.count == 2)
        #expect(model.groups.completed.count == 1)

        // 中文命中：未完成命中的留在原组，已完成的命中也进已完成组（与面板搜索同口径）
        model.searchText = "牛奶"
        #expect(model.groups.noDate.map(\.title) == ["买牛奶"])
        #expect(model.groups.completed.map(\.title) == ["交牛奶报告"])

        // 英文不区分大小写
        model.searchText = "MILK"
        #expect(model.groups.noDate.map(\.title) == ["Buy Milk"])

        // 纯空白视为不过滤（空格与换行制表符混合）
        model.searchText = "   "
        #expect(model.groups.noDate.count == 2)
        model.searchText = "\n\t "
        #expect(model.groups.noDate.count == 2)
        #expect(model.groups.completed.count == 1)

        // 无命中：五组全空（视图据此显示"没有找到 X"+清除，与便签分区同款），原始快照保留（过滤只作用派生）
        model.searchText = "不存在的关键词"
        let groups = model.groups
        #expect(groups.hasNoActive && groups.completed.isEmpty)
        #expect(model.todos.count == 3)
    }

    @Test("toggleComplete 转发：未完成→(id, true)、已完成→(id, false)；delete 转发 id")
    func actionForwarding() throws {
        let model = MainTodosModel()
        var toggleCalls: [(id: Todo.ID, completed: Bool)] = []
        model.toggleComplete = { id, completed in toggleCalls.append((id, completed)) }
        var deleted: [Todo.ID] = []
        model.delete = { deleted.append($0) }
        var edited: [Todo.ID] = []
        model.edit = { edited.append($0) }
        var timed: [Todo.ID] = []
        model.setTime = { timed.append($0) }

        let uncompleted = Todo(
            id: Todo.ID(rawValue: 1),
            uuid: UUID(),
            title: "未完成",
            due: nil,
            snoozedUntil: nil,
            completedAt: nil,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: nil
        )
        let completed = Todo(
            id: Todo.ID(rawValue: 2),
            uuid: UUID(),
            title: "已完成",
            due: nil,
            snoozedUntil: nil,
            completedAt: Self.now,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: nil
        )

        model.toggleCompletion(uncompleted)
        model.toggleCompletion(completed)
        #expect(toggleCalls.count == 2)
        #expect(toggleCalls[0].id == uncompleted.id && toggleCalls[0].completed == true)
        #expect(toggleCalls[1].id == completed.id && toggleCalls[1].completed == false)

        model.delete(uncompleted.id)
        #expect(deleted == [uncompleted.id])

        // 编辑/设置时间转发 id 原样；稍后提醒默认 nil 不产生任何调用
        model.edit(uncompleted.id)
        model.setTime(completed.id)
        #expect(edited == [uncompleted.id])
        #expect(timed == [completed.id])
        #expect(model.snooze == nil)
    }

    @Test("完成回环：勾选后从未完成组消失、进入已完成组；勾回复原（真实仓储 + 观察流）")
    func completeRoundTripThroughRepository() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        // 转发闭包接真实仓储（集成时接 PanelModel.setTodoCompleted 同语义）
        model.toggleComplete = { id, completed in
            Task { try? await environment.todoRepository.setCompleted(id, completed) }
        }
        model.start()
        defer { model.stop() }
        let todo = try await environment.todoRepository.create(title: "回环待办", due: nil)

        try await waitUntil(model, "待办进入无日期组") { $0.groups.noDate.map(\.id) == [todo.id] }
        #expect(model.groups.completed.isEmpty)

        // 勾选完成 → 闭包转发 → 仓储落库 → 观察流回推 → 分组迁移
        model.toggleCompletion(todo)
        try await waitUntil(model, "迁移到已完成组") { $0.groups.completed.map(\.id) == [todo.id] }
        #expect(model.groups.noDate.isEmpty)

        // 勾回：用观察流回推的最新快照（completedAt 已非空 → 目标状态 false）
        guard let completed = model.todos.first(where: { $0.id == todo.id }) else {
            Issue.record("观察流里找不到该待办")
            return
        }
        #expect(completed.completedAt != nil)
        model.toggleCompletion(completed)
        try await waitUntil(model, "勾回无日期组") { $0.groups.noDate.map(\.id) == [todo.id] }
        #expect(model.groups.completed.isEmpty)
    }

    @Test("clock 注入：昨天的完成时间戳不影响归组；已完成组按完成时间降序")
    func clockInjectedCompletedOrdering() async throws {
        // 库时钟固定为"昨天"（相对注入基准 T 减一天，不依赖真实时钟/时区）：
        // createdAt/completedAt 全是昨天
        let fixedYesterday = Self.now.addingTimeInterval(-86_400)
        let yesterdayClock: @Sendable () -> Date = { fixedYesterday }
        let (environment, suiteName) = try makeEnvironment(clock: yesterdayClock)
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        model.start()
        defer { model.stop() }
        let first = try await environment.todoRepository.create(title: "先完成", due: nil)
        let second = try await environment.todoRepository.create(title: "后完成", due: nil)
        try await waitUntil(model, "两条待办到位") { $0.todos.count == 2 }

        // 昨天创建的无日期待办不是逾期（归组只看 due 与完成态，不看 createdAt）
        #expect(model.groups.noDate.count == 2)
        #expect(model.groups.overdue.isEmpty)

        try await environment.todoRepository.setCompleted(first.id, true)
        try await environment.todoRepository.setCompleted(second.id, true)
        try await waitUntil(model, "两条都完成") { $0.groups.completed.count == 2 }
        // 已完成组按 completedAt 降序：后完成的在上（并列时 id 决胜，序同）
        #expect(model.groups.completed.map(\.title) == ["后完成", "先完成"])
        #expect(model.groups.noDate.isEmpty)
    }

    @Test("跨天重算：handleTimeContextChanged 递增时钟，分组随注入 now 推进而迁移（今天→逾期）")
    func timeContextTickBumpsAndDrivesRegroup() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        defer { model.stop() }
        model.start()
        let todo = try await environment.todoRepository.create(
            title: "今天的事",
            due: TodoDue(date: date(0, hour: 15), hasTime: true)
        )
        try await waitUntil(model, "待办进入今天组") { $0.groups.today.map(\.id) == [todo.id] }

        // 注入的 now 推进到次日 + 分组时钟递增（跨天/唤醒同款）：重算后迁入逾期组
        var currentNow = Self.now
        model.now = { currentNow }
        currentNow = try #require(Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: Self.now))
        let tickBefore = model.timeContextTick
        model.handleTimeContextChanged()
        #expect(model.timeContextTick == tickBefore + 1)
        try await waitUntil(model, "迁移到逾期组") { $0.groups.overdue.map(\.id) == [todo.id] }
        #expect(model.groups.today.isEmpty)
    }

    @Test("时区锚点：日界按注入时区计算（纽约 00:00 与 23:59 同属今天），不随机器时区漂移")
    func groupingUsesInjectedTimeZoneDayBoundaries() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        defer { model.stop() }
        // 第三时区（纽约）：若实现误用 .current，任何非纽约机器至少一条边界错组
        let newYork = TimeZone(identifier: "America/New_York")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 15
        components.hour = 12
        let nowNY = calendar.date(from: components)!
        model.timeZone = newYork
        model.now = { nowNY }
        model.start()
        defer { model.stop() }

        let dayStart = calendar.startOfDay(for: nowNY)
        let midnight = dayStart
        let almostMidnight = calendar.date(byAdding: .minute, value: 23 * 60 + 59, to: dayStart)!
        let early = try await environment.todoRepository.create(title: "纽约零点", due: TodoDue(date: midnight, hasTime: true))
        let late = try await environment.todoRepository.create(title: "纽约2359", due: TodoDue(date: almostMidnight, hasTime: true))
        try await waitUntil(model, "两条待办到位") { $0.todos.count == 2 }

        #expect(model.groups.today.map(\.id) == [early.id, late.id]) // 组内 due 升序
        #expect(model.groups.overdue.isEmpty)
        #expect(model.groups.later.isEmpty)
    }

    @Test("观察流收尾：正常结束保留快照、异常结束不崩且保留快照（与便签模型同口径）")
    func streamFinishAndFailureKeepState() async throws {
        let model = MainTodosModel()
        let todo = Todo(
            id: Todo.ID(rawValue: 1),
            uuid: UUID(),
            title: "快照",
            due: nil,
            snoozedUntil: nil,
            completedAt: nil,
            createdAt: Self.now,
            updatedAt: Self.now,
            deletedAt: nil
        )

        await model.runTodos(oneShot([todo]))
        #expect(model.todos.map(\.id) == [todo.id])

        // 读取失败异常收尾：吞错记日志（不可断言），状态保留不崩
        await model.runTodos(failingStream())
        #expect(model.todos.map(\.id) == [todo.id])
    }

    @Test("stop 停止消费：停流后仓储新增不再推送；重复 start 幂等不重复消费")
    func stopStopsAndStartIsIdempotent() async throws {
        let (environment, suiteName) = try makeEnvironment()
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let model = makeModel(environment)
        let todo = try await environment.todoRepository.create(title: "订阅前", due: nil)
        model.start()
        defer { model.stop() }
        try await waitUntil(model, "首帧到位") { $0.todos.map(\.id) == [todo.id] }

        // 重复 start：先取消旧订阅再订阅，帧不重复消费（仍是全量快照语义）
        model.start()
        _ = try await environment.todoRepository.create(title: "重启后新增", due: nil)
        try await waitUntil(model, "新流首帧含两条") { $0.todos.count == 2 }

        // stop 后不再消费：新增不进快照（stop 已取消任务，无可达路径，休眠兜底时序）
        model.stop()
        _ = try await environment.todoRepository.create(title: "停流后新增", due: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.todos.count == 2)
    }

    @Test("已完成组默认折叠（与面板一致）")
    func completedSectionDefaultsCollapsed() {
        let model = MainTodosModel()
        #expect(!model.isCompletedExpanded)
        model.isCompletedExpanded = true
        #expect(model.isCompletedExpanded)
    }
}
