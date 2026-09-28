---
title: 'Story 3.7 编辑时间'
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

**Problem:** 时间只能靠重打整句修改——计划一变就得删了重录。

**Approach:** 待办右键"设置时间…"打开弹层（popover(item:)）：日历选日期、"包含时刻"开关、时刻选择、快捷按钮今天/明天/下周一/清除时间；变更即时落库（PanelModel.setDue，autosave 风格）。compose/shiftDays/nextMonday 为注入时区的纯函数。清除时间置 nil 并关弹层。

## Boundaries & Constraints

**Always:** 纯函数注入 timeZone（NFR22，DST 用 bySettingHour 不用 byAdding 时分）；快捷按钮以真实今天为绝对基准；编辑标题不重新识别时间；失败走保存失败提示条。

**Never:** 不做重复任务；不做弹层里的确认按钮（即时落库语义）。

</frozen-after-approval>

## Implementation Notes

- TodoTimeEditorView：@State 三元（day/hasTime/timeOfDay）；快按钮只改 day、落库由 onChange 独家触发（避免双写，盲审 F6）；无时刻待办开启"包含时刻"默认 09:00（盲审 F7）。
- compose 用 bySettingHour（DST 过渡日墙上时刻不被偏移，盲审 F3，配 New York 春令时 L1）；nextMonday 公式注释改 Calendar weekday 术语（F5）。
- 面板收起钩子 endCaptureWindow 清 editingTimeTarget（面板级 Esc/热键收起宿主不走 item 绑定回写，弹层会幽灵复活，盲审 F2）；popover 内容 .id(todo.id) 防状态复用。
- 测试：TodoTimeEditorTests 6 个（compose 两态、nextMonday 三基准、shiftDays、DST 边界、setDue 往返、标题编辑不动 due）；TodoGroupingTests 补"9月30日/2027年3月7日"行尾格式。App 122 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（2 high / 2 medium / 3 low / 2 info），全部处置：

- [high→已修] F1 "今天"快捷按钮是空操作（闭包原样返回选中日期）。以真实今天为基准。
- [high→已修] F2 面板收起不清 editingTimeTarget——弹层幽灵复活 + 已删待办弹"未知错误"。endCaptureWindow 复位 + .id(todo.id)。
- [medium→已修] F3 compose 用 byAdding(hour/minute) 跨 DST 偏移 1 小时（测试时区无 DST 掩盖）。改 bySettingHour + New York 春令时 L1。
- [medium→已修] F4 明天/下周一相对选中日期而非真实今天（文案语义相悖）。三按钮统一真实今天基准。
- [low→已修] F5 nextMonday 注释 ISO weekday 术语错误。改 Calendar weekday。
- [low→已修] F6 快捷按钮双写（手动 apply + onChange）。只改 day。
- [low→已修] F7 全天待办开启时刻默认 00:00。改默认 09:00。
- [info→backlog] F8 notFound 提示渲染为"未知错误（0）"（阶段既有映射，记录不改）。
- [info→确认] F9：@State 状态残留路径、写库竞态与调度器交互、$model 绑定合法性、标题编辑不识别的覆盖——全部核实无恙。
