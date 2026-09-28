---
title: 'Story 3.8 菜单栏计数'
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

**Problem:** 菜单栏只有一个图标，还有多少事没做完全不可见；待办积压时不打开面板就没有感知。

**Approach:** `MenuBarCounter.count` 纯函数（none / overdueAndToday=逾期+今天未完成 / allIncomplete=全部未完成，注入 now/timeZone）；StatusItemController.updateCounter 在图标右侧显示数字（nil/0 不显示）；待办分段按钮显示同口径角标；设置-通用新增三口径 Picker。刷新时机：数据变化、跨天/唤醒（timeContextChanged 钩子）、口径变化。

## Boundaries & Constraints

**Always:** 计数纯函数注入 now/timeZone（NFR22）；口径非法值回落 overdueAndToday；文案键 xcstrings。

**Never:** 不把 pendingCompletionIDs（1 秒窗口）计入计数（与数据双真相）；不做"不显示"以外的图标隐藏。

</frozen-after-approval>

## Implementation Notes

- SettingsModel 的 menuBarCounter/reminderAllDayMinutes/reminderSnoozeMinutes 改为**存储属性 + didSet**（写偏好 + 触发钩子）——原经 UserDefaults 的计算属性不可被 @Observable 观测，视图 onChange 检测不到变化、钩子是死代码（盲审 F2，同根因波及 3.5 的提醒设置页）；init 读偏好作初值（init 内赋值不触发 didSet）。
- StatusItemController.updateCounter：button.title 数字、0/nil 置空（variableLength 自适应宽度，盲审 F6）。
- PanelView 待办分段标签带计数（count > 0 才显示，盲审 F1）；todoBadgeCount 读 timeContextTick（跨天重算，盲审 F3）。
- 测试：MenuBarCounterTests 5 个（三口径、零、resolve 回落、完成减一+钩子）；ReminderSettingsTests 改为存储属性语义。App 126 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（2 high / 1 medium / 2 low / 3 info），全部处置：

- [high→已修] F1 计数为 0 时分段显示"待办 0"（guard 只挡 nil）。补 count > 0。
- [high→已修] F2 口径变化钩子是死代码——SettingsModel 经 UserDefaults 的计算属性不可被 @Observable 观测，onChange 永不触发（同根因波及 3.5 的提醒设置页）。三个设置项改存储属性 + didSet（持久化 + 钩子）；ReminderSettingsTests 对齐新语义。
- [medium→已修] F3 分段角标跨天不刷新（不读 tick）。todoBadgeCount 补 tick 依赖。
- [low→确认] F4 "完成立即减少"与 1 秒延迟落库：计数按数据口径（落库后减），阶段 1 两段式交互不变，验收按"落库后立即"口径。
- [low→已修] F5 测试断言链同义反复 + 空数组逃生门。uuid 捕获 + 去逃生门。
- [info→已修] F6 冗余 variableLength 赋值删除；F7 Package.resolved 夹带还原。
- [info→确认] F8 接线无环、三钩子先于 start()、MainActor 安全、xcstrings 齐全。
