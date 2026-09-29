---
title: 'Story 3.6 待办分组'
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

**Problem:** 待办只有"待办/已完成"两栏，逾期的事项混在里面看不见，过午夜也不会自己浮上来。

**Approach:** `TodoGrouping` 纯函数（注入 now/timeZone）：逾期（< 今天 0 点，红）/ 今天 / 以后 / 无日期 / 已完成（折叠保持阶段 1 交互）；组内逾期/今天/以后按 due 升序、无日期按创建降序（id 决胜，对齐阶段 1 流序）、已完成按完成时间降序（id 决胜）。PanelModel 用 timeContextTick 建立视图依赖，跨天/唤醒观察者递增；TodoListView 五个 Section + 行尾时间文案（复用 TimeDisplay，逾期红）。

## Boundaries & Constraints

**Always:** 纯函数注入 now/timeZone（NFR22，DST 用日历日推进）；snoozedUntil 不影响分组显示；文案键 xcstrings；阶段 1 勾选三态/原位编辑/删除撤销/新建在顶部不回归。

**Never:** 不做"设置时间…"（3.7）；不做计数（3.8）；不做全组排序的偏好化（S5-04）。

</frozen-after-approval>

## Implementation Notes

- TodoGrouping：分区先行再各组排序；`tomorrowStart` 用 calendar.date(byAdding: .day)（DST 安全，盲审 F1）；isOverdue/timeText 行级助手。
- PanelModel：timeContextTick（无 @ObservationIgnored——视图依赖需要跟踪）+ handleTimeContextChanged；start() 订阅跨天/唤醒（stop+start 防重复），stop()/deinit 移除（盲审 F4）。
- TodoListView：body 开头一次求值 groups 局部化（7 处引用，盲审 F2）；TodoRow 的 timeText/showsOverdueTime 读 tick 建立跨天依赖（盲审 F3）。
- 空状态引导更新（03 §14）；孤儿键 list.group.todos 移除。
- 测试：TodoGroupingTests 6 个（边界、归属与三组排序、跨天重排、逾期判定与行尾文案、snooze/已完成归属、tick）；TodoListTests 改用 todoGroups（断言等价）。App 116 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（3 medium / 3 low / 4 info），全部处置：

- [medium→已修] F1 "明天"边界用 +86400 秒——DST 时区春令时当天 00:00–01:00 错分进今天。改日历日推进 + 注释。
- [medium→已修] F2 todoGroups 每次 body 求值 7 次重算、各自取 Date()（跨午夜单帧不一致）。body 开头局部化一次求值。
- [medium→已修] F3 TodoRow 跨天文案刷新依赖父视图隐式重渲染。timeText/showsOverdueTime 显式读 tick。
- [low→已修] F4 deinit 不清理跨天/唤醒观察者。deinit 补 removeObserver。
- [low→已修] F5 组内排序丢 id 决胜（sort 非稳定，并列时与阶段 1 流序分叉）。补 id.rawValue 决胜。
- [low→已修] F6 测试缺口：snoozedUntil 不影响分组、已完成+有 due 归属。补两条。
- [info→已修] 孤儿键 list.group.todos 移除；空状态引导引号对齐站内「‘’」风格。
- [info→保留] 已折叠 @State 跨模式复位（阶段 1 同构）；pendingCompletionIDs 落库后一帧闪回（阶段 1 同款）；snoozed 待办红字躺在逾期组符合规格明文（验收对照）；行尾"9月30日/2027年3月5日"格式用例随 3.7 补。
