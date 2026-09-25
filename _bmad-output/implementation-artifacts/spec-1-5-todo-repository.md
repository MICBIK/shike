---
title: 'Story 1.5 待办的保存与观察'
type: 'feature'
created: '2026-09-26'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/data-layer.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 数据层还只能存便签：阶段 1、2 的待办功能（随手记待办、中文时间、到点提醒）需要一个规则正确的待办仓储——全天规范化、稍后提醒的清空规则、完成状态语义一个都不能含糊。

**Approach:** 复用 1.4 的 performWrite 与观察桥接，实现 Todo/Todo.ID/TodoDue 公开模型、TodoRecord、TodoRepository 八个写方法 + observeActive。全天 due 规范化为 Options.timeZone 当天 00:00；setDue 与 setCompleted(true) 清空 snoozedUntil；setCompleted 幂等；ADR-017 语义与便签一致（修改类更新 updatedAt，softDelete/restore 不更新）。

## Boundaries & Constraints

**Always:** 时间戳取自注入时钟；公开 API 无 GRDB 类型；uuid 小写文本。

**Never:** 不实现卡片仓储（1.6）；不改已发布迁移。

</frozen-after-approval>

## Implementation Notes

- 全天规范化用 Calendar(gregorian) + Options.timeZone 取年月日再回构造 00:00，与解析器的"内部固定公历"口径一致。
- setCompleted 的幂等实现与 setPinned 相同（WHERE completedAt IS NULL/IS NOT NULL + changesCount==0 时做存在性检查区分 notFound）。
- 验收结果：41 个包测试全过（严格警告）；checks.sh、xcodebuild build test（严格模式）通过。新增 8 个待办测试：规范化（全天 00:00 / 带时刻原样 / 无时间）、snoozedUntil 清空两路 + setCompleted 幂等、ADR-017 时序（递增时钟）、删除语义与七路 notFound、观察（createdAt 降序、含已完成、写入推送）、simulateWriteFailure 八方法短路。

## Review Triage Log

- 本故事与 1.4 完全同构（共用 performWrite/observationStream/ReceiveBox<Value> 泛型化），评审以"契约表逐行比对 + 1.4 已建立的模式核对"进行。逐行核对中确认三处易错点均已正确：setDue 清空 snoozedUntil（含清时间路径）、setCompleted(true/false) 幂等、软删除保留原 deletedAt。无新增发现。
- ReceiveBox 由 NoteListItem 专用改为泛型（便签/待办测试共用）；create(title:due:) 的 due 为必传参数（nil 表示无时间），与契约签名一致。
