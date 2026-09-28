---
title: 'Story 2.4 快速输入框与提交'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/scope-boundaries.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 面板没有输入区，无法记录任何内容；2.3 交接的"输入框内 Tab"与 AC2（草稿互换、占位文案随模式变化）在此落地。

**Approach:** 移植 CaptureTextView（源：RmbHighlightedTextField + PlaceholderNSTextView + FocusDirection）：NSViewRepresentable 包 NSScrollView 中的 NSTextView，自绘占位；去掉自动补全与高亮（S2-01 再接入）；IME 安全（hasMarkedText 时不替换文字、回车交输入法）；⇧↩ 换行仅便签模式；Tab 上交为 onTab（切模式）；高度自适应（便签 6 行/待办 2 行，超出框内滚动）。PanelModel 增两份草稿（持久化 panel.draft.note/todo）、submit() 提交链路（成功清空草稿+焦点保留+新条目标识；失败保留输入并 report，重试绑定当次输入、成功后清除提示条——NFR19）、focusToken（呼出聚焦）。PanelView 顶栏下方插入输入区。

## Boundaries & Constraints

**Always:** IME 安全的决策逻辑提为可测纯函数；移植文件 GPL 来源头 + NOTICE + 04 §7；文案键集中；空内容（trim 后）提交无反应；提交成功清空对应模式草稿。

**Never:** 不接解析高亮（S2-01）；不做 TypingBuffer（2.5）；不做列表（2.6/2.7）；不改 PopoverController。

</frozen-after-approval>

## Implementation Notes

- CaptureTextView（移植）：newlineDecision 纯函数承载回车决策（组合态 > ⇧↩ > 裸回车 > 防御放行），组合态三重保护（updateNSView 跳过、doCommandBy 交还输入法、shouldChangeTextIn 拒绝 "\n"）；占位自绘加 hasMarkedText 守卫（优于 demo）；FocusDirection 收敛为二值。
- **外部变更令牌（盲审 H1/H2 的修复）**：demo 的"活动编辑器不回写"守卫只适用于其"提交即关窗"场景；拾刻的常驻输入框存在焦点态下的合法绑定变更（提交清空、模式切换）。PanelModel 新增 `draftResetToken`（mode didSet 与 finishSubmit 都触发），CaptureTextView 据此在焦点态无条件回写视图（保留光标相对位置），绕过该守卫。
- finishSubmit 语义：只在草稿仍是提交文本时清空（重试期间用户改动的新草稿绝不丢）；saveFailed 提示条重试成功后清除（NFR19）；recentlyCreatedItemID 1 秒清除任务连续创建时重置。
- 高度计算提为纯函数 captureHeight（盲审 M2）；提示条保持"顶栏下方"（顶栏 → banner → 输入区，恢复阶段 0 排序，盲审 M1）；onTab 简化为同向切换（盲审 L1）。
- 测试：CaptureInputTests 6 个（newlineDecision 7 例、captureHeight 边界、草稿持久化/互换/重启恢复/提交清空、提交入库与空内容防御、失败保留+重试绑定当次输入）；等待统一为截止时间轮询 waitUntil（盲审 L2，防 CI 抖动）。App 56 全绿、包 76 全绿、checks 通过。
- createNote/createTodo 为内部闭包接缝（默认走仓储，与 1.10 的 runNotes/runTodos 同类），供 L2 注入失败。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（2 high / 2 medium / 3 low），全部处置：

- [high→已修] H1 提交后输入框不清空：demo 的"活动编辑器不回写"守卫在常驻输入框场景失效，提交清空被跳过，继续输入会污染下一条内容。已加 draftResetToken 外部变更通道（模式 didSet + finishSubmit 触发，updateNSView 焦点态无条件回写）。
- [high→已修] H2 焦点态切模式草稿脱节：可见文字、提交内容、草稿三方不一致。同一通道修复（mode didSet 发令牌）。
- [medium→已修] M1 提示条位置偏离 03 §3/§14"顶栏下方"（实现放在了输入区之下）。已恢复 顶栏 → banner → 输入区 的阶段 0 排序，头注释同步。
- [medium→已修] M2 高度计算未提纯无测试（规格 Always 明示）。已提为 captureHeight 纯函数并补边界测试。
- [low→已修] L1 onTab 三元双分支相同 + 注释与实现矛盾。已简化为同向切换并修注释。
- [low→已修] L2 测试固定 sleep 在 CI 有抖动风险。已改为截止时间轮询 waitUntil（2 秒上限、20ms 步进）。
- [low→已修] L3 测试注释含糊（问号式）。已改陈述句。
- [确认] IME 三重保护（其中 doCommandBy 组合态检查为移植版新增，优于 demo）；"草稿==提交文本才清空"与 NFR19/不丢数据一致并已固化测试；banner 只清 saveFailed；1 秒高亮任务与 deinit 取消；范围合规（无 TypingBuffer/高亮/列表，PopoverController 零改动）。
- 遗留 L3 人工项：真实输入法组合回车、⇧↩ 手感、高度动画、提交后可见文字为空且连续输入（对应修复验证）。
