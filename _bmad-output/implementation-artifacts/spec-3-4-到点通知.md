---
title: 'Story 3.4 到点通知'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-2-reminders/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-2-reminders/stage-2-components.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 待办有了时间却没有提醒——到点没有任何东西响，退出拾刻后更没人管。

**Approach:** `NotificationScheduling` 协议封装 UNUserNotificationCenter（App 层唯一触碰点，NFR23；L2 内存替身零真实调用）；`NotificationCoordinator` 负责类别注册（"完成"+"稍后提醒（N 分钟）"，时长随偏好）、前台横幅、动作路由（完成/稍后提醒/点本体打开面板定位）。PanelModel 增加权限请求钩子（带时间提交时触发）与 completeTodo/snoozeTodo（按 uuid 直达仓储）；locateTodo 定位状态 + TodoListView 滚动定位与 1.5 秒高亮。AppEnvironment 注入 scheduling 并在属性就绪后配置动作回调；AppDelegate 接线类别、delegate 与 openPanelHandler。提前排期的本地通知在退出后照常送达（UNTimeInterval 触发器）。

## Boundaries & Constraints

**Always:** NFR23（UN 只在 App 层经接缝；L2 零真实权限/通知）；动作落库不依赖界面快照（冷启动安全，uuid 直达仓储）；过期 fireDate 拒绝排期；不吞错误（排期失败写日志、动作失败走提示条重试）。

**Never:** 不做调度对账（3.5）；不做权限被拒提示条（3.10）；不改 PopoverController 语义。

</frozen-after-approval>

## Implementation Notes

- NotificationScheduling 协议：authorizationStatus / requestAuthorization / pendingIdentifiers / add / removePending；SystemNotificationScheduling 用 async 变体；add 拒绝过期 fireDate（盲审 F4）并写日志。
- NotificationCoordinator：registerCategory(snoozeMinutes:)——按钮括号时长随偏好（盲审 F3）；handleAction 与 UN 类型解耦（default=点本体→openPanelHandler，complete/snooze→handlers）；delegate nonisolated + MainActor.run hop；Handlers 在 AppEnvironment 全部属性就绪后配置（init 顺序约束）。
- TodoRepository 新增 uuid 读写入口：todo(uuid:)（含已删除）/ setCompleted(uuid:) / snooze(uuid:)——snooze 带 completedAt IS NULL 守卫（盲审 F5）；uuid 比较小写（ADR-020 编码，实测大写 uuidString 查不到导致动作静默失效——L2 waitUntil 抓住）。
- PanelModel：completeTodo/snoozeTodo 走仓储 uuid 路径（快照无关，冷启动安全，盲审 F1）；未处理（已删除/已完成）写日志忽略；失败走保存失败提示条+重试。
- TodoListView：onChange(of: locateTodoID, initial: true)——挂载即定位（盲审 F2：模式切换/冷启动路径下目标先于列表挂载存在）。
- 测试：NotificationCoordinatorTests 6 个（动作路由+档位时长、正文两态、权限请求时机三态、动作落库+F5 脏写防御、定位清除）；App 104 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（3 high / 1 medium / 2 low / 1 info），全部处置：

- [high→已修] F1 动作落库依赖 PanelModel.todos 内存快照——冷启动首批快照未到时用户动作被静默丢弃（违反 components §3"先等数据库就绪"）。仓储新增 uuid 读写入口，动作直达仓储；实测中 L2 还抓到 uuid 大小写不匹配（ADR-020 小写存储）导致动作静默失效的真缺陷。
- [high→已修] F2 滚动定位在列表首次挂载路径不触发（onChange 不响应既有值；openMode=便签时点通知必现）。onChange 加 initial: true。
- [high→已修] F3 稍后提醒按钮文案硬编码 10 分钟，违反"括号时长随设置变化"（设置页已可改 60）。registerCategory(snoozeMinutes:) 读偏好注册；3.5 的"提醒设置变化"时机负责重注册。
- [medium→已修] F4 add() 的 max(1,…) 把过期 fireDate 变成"1 秒后立即响"。改为拒排+日志；崩溃防御退化为极小正值钳制 0.1s。
- [low→已修] F5 对已完成待办点旧通知"稍后提醒"写脏 snoozedUntil。仓储 snooze(uuid:) 加 completedAt IS NULL 守卫 + L2 用例。
- [low→已修] F6 requestAuthorization 的 false 混淆"拒绝"与"出错"。doc 注明权威口径是 authorizationStatus()。
- [info→部分] F7：handleActionAndWait 包装删除（直呼同步方法）；snoozeMinutes 回落逻辑与 SettingsModel 重复保留（两处语义不同：读档位 vs 写校验）；openPanelHandler 强捕获风格保留（生命周期一致）。
- [确认] delegate 回调 hop、冷启动 delegate 时序、NFR23 边界、xcstrings manual、阶段 1 无回归。
