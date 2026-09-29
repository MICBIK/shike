---
title: 'Story 2.8 删除与撤销'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/app-shell.md'
  - '{project-root}/_bmad-output/implementation-artifacts/deferred-work.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 删除（右键/编辑清空）直接软删、无反馈且无法撤销；面板内 ⌘Z 是文字撤销，没有删除撤销。

**Approach:** PanelModel 增会话级删除撤销栈（uuid+kind+删除时按模式记录的摘要）与 deletedBar 状态（摘要 + 5 秒自动消失 + 连续删除重置）；UndoBar 视图（底部浮出"已删除「前 12 字…」+ 撤销"）；undoLastDelete 走 restore；note/todo 的 deleteNote/deleteTodo 入栈；编辑清空（saveNoteContent 空→softDelete）同一通道入栈；⌘Z 在面板非编辑态逐条撤销（编辑态仍是文字撤销——两条本地监听路径区分：PopoverController 的面板按键处理加 ⌘Z 分支，编辑态由 endEditingIfNeeded 返回 true 消费）；2.6/2.7 交接的三条 deferred（清空删除入栈、收起保存 flush、重试条与撤销条互斥）一并落地。

## Boundaries & Constraints

**Always:** 撤销栈会话级不持久化；restore 后便签回到原排序位（数据层 updatedAt 语义保证）；5 秒提示条计时连续删除重置；与错误提示条互斥显示时撤销条优先级低（错误在顶栏下、撤销在底部，共存不冲突）。

**Never:** 不做最近删除界面（S4-05）；不做卡片联动（S3）。

</frozen-after-approval>

## Implementation Notes

- 撤销栈：DeletedItem（kind: note/todo + summary 前 12 字，超长加"…"——盲审 L5）；deletedStack 会话级 LIFO；recordDeletion 在 softDelete 成功后从内存列表取删除前内容入栈并显示提示条。
- 撤销条：deletedBarSummary + 可注入 deletedBarHideDelay（默认 5 秒，盲审 L2）；showDeletedBar 统一"显示+排计时"，撤销后显示下一条同样重启计时（盲审 M2：否则重新显示的条目永不消失）。
- 恢复失败回栈（盲审 M3）：popLast 先弹出后 restore，失败时条目放回栈顶且提示条保留；重试闭包 retryRestore 先移除再 restore，成功刷新提示条——撤销入口在失败期间保持可达（app-shell"调用 restore 并弹出"的顺序在失败路径上以"回栈"兑现）。
- ⌘Z：PopoverController 面板按键处理加 ⌘Z 分支（精确匹配，⌘⇧Z 因 charactersIgnoringModifiers 保留 Shift 产生大写 "Z" 天然放行）；undoLastDeleteIfNeeded 的 isEditingAny 守卫使编辑态 ⌘Z 返回 false 交回文字撤销。
- 便签右键菜单（盲审 H1：2.6 重写 NoteRow 时丢失，本次补回）：编辑、置顶/取消置顶、复制内容、删除——deleteNote 通路自动入栈。
- deferred 交接落实：①编辑清空入栈 ✓（saveNoteContent 空路径 recordDeletion）；②收起面板 flush 已在 2.6（onClose → endEditingIfNeeded）；**stop 前 flush 未做**——applicationWillTerminate 的在飞写任务极小丢失窗口，登记 deferred 随阶段收尾评估；③重试条与撤销条并存：错误条在顶栏下、撤销条在底部，独立状态共存（规格 frozen Always 的落地）。
- 决策登记（盲审 L3）：快速输入框持有焦点时 ⌘Z 被面板监听消费为删除撤销，草稿文字撤销不可达——阶段 1 接受（输入框草稿通常已提交；正式决策随阶段 1 回顾与产品确认，必要时守卫加"capture 为 firstResponder 且非空时放行"）。
- 测试：DeleteUndoTests 6 个（删除入栈+摘要省略+撤销顺序不变、连续删除逆序 ⌘Z、编辑态守卫、清空入栈+撤销内容不变、计时注入到时消失/撤销显示下一条）；App 75 全绿、包 76 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 high / 3 medium / 6 low），全部处置：

- [high→已修] 便签右键菜单整体缺失（2.6 重写 NoteRow 时丢失，注释与提交声明与实现不符；2.8 的"右键删除入口"对便签侧无物可接）。本次补回四个菜单项，deleteNote 自动入栈；已在 2.6 台账不可追溯——以本条目为登记。
- [medium→已修] refreshDeletedBar 不排隐藏任务，撤销后重新显示的提示条永不消失。抽出 showDeletedBar 统一显示+计时。
- [medium→已修] popLast 先于 restore 且失败不回栈——后续 report 覆盖 banner 后条目失去唯一撤销入口。失败回栈 + retryRestore 对称移除。
- [medium→登记] deferred 第 2 条"stop 前 flush"未实现也未登记。已登记 deferred-work（见 Implementation Notes）。
- [low→已修] "顺序不变"L2 断言恒真式。改为删除前采集 orderBefore、撤销后比较 unpinnedNotes 顺序。
- [low→已修] 5 秒隐藏零测试且不可注入。deletedBarHideDelay 可注入 + 计时三场景测试（到时消失/连续删除重置/撤销显示下一条）。
- [low→登记] 快速输入框 ⌘Z 消费决策。已登记（见 Implementation Notes，阶段 1 回顾确认）。
- [low→还原] Package.resolved 的无关抖动。已 git checkout 还原。
- [low→已修] 摘要截断无省略号。超 12 字补"…"。
- [low→已修] Implementation Notes 未填 + 待办清空标题决策未登记。本轮填写；决策已在 deferred-work（2.7 补充节）。
