---
title: 'Story 3.5 通知调度'
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

**Problem:** 通知会发了，但系统和数据库各管各的——改时间、完成、删除后，过时的提醒照样响。

**Approach:** `ReminderScheduler`：以观察流快照 + ReminderPlan 做差量对账（只撤销计划外/已变化的，只新增/重写新增或变化的，未变跳过）；自持上次计划（标识→时刻）做变化检测；只管理 uuid 形态标识。对账时机：观察流首帧与数据变化（0.5 秒合并）、跨天、唤醒（NSCalendarDayChanged/didWakeNotification 订阅）、提醒设置变化（重注册类别 + 对账）。启动对账由首帧驱动——首帧前不拿空快照清空系统提醒（盲审 F1）。重入安全：在途时置脏标记完成后补跑（盲审 F2）。

## Boundaries & Constraints

**Always:** 幂等（NFR20：相同数据重复对账不产生重复通知）；合并去抖（NFR21）；读取失败不触发对账（不知道数据库状态就不重写系统状态）；L2 全替身。

**Never:** 不做权限提示条（3.10）；不管理非提醒类通知（uuid 形态之外的一律不动）。

</frozen-after-approval>

## Implementation Notes

- 差量算法：`lastPlanned`（标识→时刻）与系统 pending 求并集判断——撤销=系统在排但计划外/时刻变化的；补排=系统没有或时刻相对上次计划变化的。
- 对账入口 reconcile 重入合并：isReconciling + reconcileAgain 脏标记；scheduleReconcile 的 Task.sleep 取消由 isCancelled guard 拦截。
- 通知正文复用 NotificationCoordinator.body（提醒时刻口径，snoozed 显示 snooze 后的时间）。
- 接线：panelModel.todosChanged（runTodos 每帧发射，含首帧）→ scheduleReconcile；settingsModel.onReminderSettingsChanged → 重注册类别 + scheduleReconcile；跨天/唤醒订阅在 startObservingSystemEvents。
- 测试：ReminderSchedulerTests 6 个（幂等、完成撤销+改时间重写、50 条上限、合并去抖+无重复、跨天/唤醒路由、正文口径）；App 110 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（2 medium / 4 low / 3 info），全部处置：

- [medium→已修] F1 启动对账拿空快照清空系统已排提醒，读流失败时整个会话静默丢失。删除启动直调，启动对账由观察流首帧驱动（读取失败不发射 → 不动系统状态）。
- [medium→已修] F2 reconcile 无重入保护——两个对账在 XPC 挂起点交错残留"已删除待办"的幽灵通知。isReconciling + reconcileAgain 补跑。
- [low→已修] F3 对账日志插值被转义失效（`\\(`）。修正为单反斜杠并追加撤销条数。
- [low→已修] F4 全 App 清空会吞未来非提醒类通知。只管理 uuid 形态标识。
- [low→已修] F5 "全撤全排"偏离 04 §6.7 差量措辞。改为差量（lastPlanned 自持变化检测）。
- [low→已修] F6 防抖测试 700ms 真实 sleep 在 CI 有抖动风险。改截止轮询 + 窗口后仍为 1 的合并断言。
- [info→保留] F7 DatePicker 逐 tick 触发 setNotificationCategories（幂等 fire-and-forget，量级无害）；F8 snooze 回落三处重复（语义不同：读档位 vs 写校验）；F9 Package.resolved 夹带（已还原）。
- [确认] 首帧自愈链路闭合、debounce 取消路径、设置接线时机、deinit 观察者移除、NFR20/21 被测试钉住。
