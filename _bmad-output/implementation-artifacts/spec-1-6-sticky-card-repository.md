---
title: 'Story 1.6 桌面卡片的数据'
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

**Problem:** v1 表结构里的 stickyCard 还没有仓储：阶段 3 实现桌面卡片时，位置与选项必须已经能保存，且卡片要随便签的删除/恢复自动隐藏/重现。

**Approach:** 复用三仓储共用设施，实现 StickyCard/CardFrame/StickyCardOptions（hiddenOpacity 类型内钳制 0.0～0.6）/三个枚举/VisibleCard、StickyCardRecord、StickyCardRepository：pin（幂等，返回现有卡片；便签缺失或已软删除抛 notFound）、updateFrame/updateOptions（更新列 + updatedAt）、unpin（删行不动便签）、observeVisible（JOIN 未删除便签，卡片 createdAt/id 升序，附带便签）。

## Boundaries & Constraints

**Always:** 卡片以所属 Note.ID 为键；hiddenOpacity 钳制在类型内完成；时间戳取自注入时钟。

**Never:** 不改 v1 表结构；不实现阶段 3 的窗口/悬浮逻辑（那是 UI 层）。

</frozen-after-approval>

## Implementation Notes

- hiddenOpacity 钳制在 StickyCardOptions.init 完成（构造入口收口）；pin 幂等实现为先查现有卡片、有则原样返回。
- observeVisible 用 JOIN + 两步取值（卡片行 + 未删除便签字典拼装），不用 GRDB 的元组 including API（该版本对元组 fetchAll 的类型推导在本项目工具链下不匹配，见 Review 记录）。
- 验收结果：48 个包测试全过（严格警告）。新增 7 个卡片测试：钳制、Sendable、钉出幂等（重复钉出不改动）、便签缺失/已删 notFound、更新与 notFound 三路、unpin 保留便签、观察随软删除消失/恢复重现/永久删除级联、simulateWriteFailure 四方法短路。
- GRDB API 备忘：`belongsTo(NoteRecord.self)` 外键列按约定推断（noteId），不能传 foreignKey 参数；元组 including 取值在本工具链编译不通过。

## Review Triage Log

- 与 1.4/1.5 同构模式（共用 performWrite/observationStream）；重点核对 pin 幂等（返回现有卡片不改任何列）、便签软删除时 pin 的 notFound、观察排序与 VisibleCard 配对。逐项核对无新增发现。
- 自查修正三处编译/断言问题（belongsTo 参数、元组 fetchAll 不匹配改两步查询、双层可选断言），均为实现层问题，不影响契约。
