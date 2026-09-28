---
title: 'Story 2.7 待办列表与完成'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/app-shell.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 待办模式非空时只显示条数占位；勾选完成、已完成分组、标题编辑都缺失；Esc 的编辑结束只覆盖便签。

**Approach:** 新增 TodoListView（「待办」completedAt==nil + 「已完成（N）」默认折叠、空组不显示；行 = 圆圈按钮 + 标题；点击圆圈立即划线变灰，1 秒后 setCompleted(true) 移入已完成组，期间再点取消；已完成组点击勾回 setCompleted(false)；单击标题原位单行编辑走 updateTitle；右键菜单：编辑、删除）；PanelModel 增 activeTodos/completedTodos、pendingCompletionIDs（1 秒延迟，时长可注入供 L2）、editingTodoID/editingTodoText；endEditingIfNeeded 覆盖两类编辑；空状态引导句已就位（2.6）。

## Boundaries & Constraints

**Always:** 1 秒延迟可注入（测试缩短）；待办分组"阶段 1 分组"（逾期/今天/以后/无日期属阶段 2）；不做设置时间（S2-07）、时间显示（S2）、键盘导航（S5-02）。

**Never:** 不做删除撤销条（2.8）；不改 ShikeData；空标题编辑不保存（回退）。

</frozen-after-approval>

## Implementation Notes

- TodoListView：「待办」+「已完成（N）」（header 折叠，默认折叠、空组不显示）；行 = 圆圈 + 标题；编辑为原位单行 TextField（onSubmit/失焦/Esc 立即保存 + 0.5 秒防抖——盲审 M1 按契约补齐）；新条目高亮与滚动对齐便签侧（盲审 L2）。
- 三态勾选：toggleTodoCompletion（未完成→pendingCompletionIDs+定时器；pending 再点→取消；已完成→勾回）；completionDelay 可注入（L2 用 120ms）；定时器回调先落库再移除待移入标记（盲审 L1：消除闪烁帧）；deinit 取消全部计时器（盲审 L4）。
- endEditingIfNeeded 扩展双编辑（便签优先，各自立即保存）；saveTodoTitle 空标题不保存（回退，frozen 段明示）——"待办清空=删除入口"登记 deferred-work 由 2.8 决定。
- PanelView 移除 countPlaceholder 死代码（条数占位完成使命；panel.placeholder.count 键保留在文案表）。
- 测试：TodoListTests 4 个（分组与排序、三态含取消与勾回、标题编辑空回退、双编辑顺序）；App 70 全绿、包 76 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 medium / 4 low / 4 info），全部处置：

- [medium→已修] AC5 的防抖自动保存缺失（提交式替代未落档）。已按契约补 0.5 秒防抖（与便签同模式）。
- [low→已修] 完成瞬间视觉回退闪烁（先移除 pending 再落库）。已改为落库后移除。
- [low→已修] 待办侧缺新条目高亮/滚动。已补（id 统一 uuidString + 背景 + ScrollViewReader）。
- [low→记录] 编辑中的待办到期移组随折叠消失（1 秒内点圆圈再点标题的边角）。可接受，内容不丢。
- [low→已修] completionTimers 未在 deinit 取消。已补 nonisolated(unsafe) + 取消。
- [info→已修] countPlaceholder 死代码。已移除（文案键保留）。
- [info→登记] 待办标题清空=回退与 03 §7 清空删除的语义缺口。已登记 deferred-work 由 2.8 决定。
- [info·确认] 编辑态跨模式残留与便签侧一致；空标题语义与 frozen 段一致；三态竞态推演（取消先于清字典、四连点收敛、写飞行期再点击的幂等补写）全部成立。
- 遗留 L3 人工项：勾选→划线→1 秒移组→展开已完成组的真实手感；折叠展开状态在面板收起后重置（@State，按设计）。
