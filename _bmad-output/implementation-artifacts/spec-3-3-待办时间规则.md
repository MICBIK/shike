---
title: 'Story 3.3 待办时间规则'
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

**Problem:** 待办有了时间字段但没有任何规则决定"什么时候提醒"——全天待办的提醒时刻、过期任务的处理都未定义。

**Approach:** ShikeData 新增 `ReminderPlan.plan` 纯函数（04 §6.7 逐字落地）：候选=未删除/未完成/有 due；fireDate=snoozedUntil 优先，其次带时刻用 dueAt、全天用当天 00:00+allDayMinutes；只留晚于 now、升序前 50。偏好键 reminder.allDayMinutes（默认 540）/ reminder.snoozeMinutes（默认 10）/ menuBar.counter（默认 overdueAndToday）注册进 Preferences；设置-提醒分页真实化（全天时刻 DatePicker hourAndMinute + 稍后时长 5/10/15/30/60 档位 Picker）；MenuBarCounter 口径枚举就位（计数求值 3.8 接线）。本故事不接通知框架。

## Boundaries & Constraints

**Always:** 计划为纯函数、注入 now/timeZone（NFR22）；ShikeData 零界面依赖；键名与默认值同 04 §5.5；文案走 xcstrings；非法偏好值有回落。

**Never:** 不做通知调度（3.5）、不做计数 UI（3.8）、不做全天"过点顺延明天"（04 §6.7 未定义此行为）。

</frozen-after-approval>

## Implementation Notes

- ReminderPlan（ShikeData/Domain）：compactMap 过滤→fireDate 三级来源→`fireDate > now` 严格过滤→升序 prefix(limit)。契约注明 limit>0 与 allDayMinutes 0...1440（钳制在调用方）。
- Preferences 三键 + 默认值注册；Int 键读取用 `(object as? Int) ?? 默认`（防外部写坏成非数字时 integer(forKey:) 返回 0 的静默错误，盲审 F2）。
- SettingsModel 访问器：allDayMinutes 钳 0...1439（0:00–23:59，盲审 F4）、snooze 非法档位回落 10、menuBarCounter 非法回落 overdueAndToday；snoozeOptions = [5,10,15,30,60]。
- ReminderSettingsView：DatePicker(.hourAndMinute) 绑定分钟换算（静态纯函数 minutes(from:)/date(fromMinutes:)）；注释声明 @State 初值语义与 3.5 的去抖要求（盲审 F7）。
- 测试：L1 ReminderPlanTests 8 个（候选过滤、fireDate 规则、snooze 优先/过期、过界过滤、limit 50/51、时区注入、全天跨天与今天已过不顺延、负 limit 防御）；L2 ReminderSettingsTests 3 个（偏好往返、访问器钳制回落、分钟换算）。App 99 全绿、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（3 medium / 3 low / 2 info），全部处置：

- [medium→已修] F1 prefix(负数) 运行时崩溃（公共 API 无契约）。入口 guard limit > 0 返回空 + L1 用例 + 契约注明。
- [medium→已修] F2 allDayMinutes 被外部写坏成非数字时 integer(forKey:) 返回 0（=00:00）静默错。读取改 `(object as? Int) ?? 540`；snoozeMinutes 同口径防写坏。
- [medium→已修] F3 缺 components §3 点名的"全天跨天"L1。补 allDayMinutes=1440 次日 00:00 与"今天全天已过不排也不顺延明天"两条。
- [low→已修] F4 钳制上界 1440 越过规格 0:00–23:59。统一钳 1439，测试同步。
- [low→已修] F5 +30h 断言对 DST 敏感。删除（与固定时区测试口径冲突的墙钟断言）。
- [low→已修] F6 MainMenuTests 测试名与断言矛盾。改名对齐。
- [info→已修] F7 设置页 @State 初值语义与 onChange 逐 tick 写偏好的去抖要求——注释落盘，S2-05 实现时遵守。
- [info→已修] F8 plan 的 allDayMinutes/limit 契约——doc 注明。
- [确认] snoozedUntil 无条件优先、过滤口径、全天日界用 due 当天、Picker 绑定不卡死、DatePicker 本地时区口径、键名默认值逐字对上 04 §5.5、xcstrings manual 齐全。
