---
title: 'Story 2.6 便签列表与编辑'
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

**Problem:** 便签模式非空时只显示条数占位，看不到内容也不能编辑；Esc 的"结束编辑"第一级（2.1 框架）还是空实现。

**Approach:** 新增 RelativeTimeFormatter（纯函数：刚刚/N 分钟前/今天 HH:mm/昨天/M月d日，注入 now+时区）与 NoteListView（「置顶」（pinnedAt 降序）+「便签」（updatedAt 降序）分组；行 = 内容前 3 行 + 相对时间；单击原位编辑，0.5 秒防抖/失焦/收起面板自动保存走 updateContent；右键菜单：编辑、置顶/取消置顶、复制内容、删除——删除先直连 softDelete，2.8 接撤销条）；PanelModel 的 endEditingIfNeeded 接真实编辑状态；空状态补引导句（S1-10 便签侧）。编辑状态经 PanelModel 供 Esc 与"收起面板时保存"消费。

## Boundaries & Constraints

**Always:** RelativeTimeFormatter 纯函数注入 now/timeZone；新文案键集中；Esc 顺序（结束编辑 → 收起）；自动保存走 updateContent（updatedAt 语义 ADR-017 由数据层保证）。

**Never:** 不做待办列表（2.7）；不做撤销提示条（2.8）；不做图钉标记（S3-01）与右键菜单里的钉到桌面/转为待办项（S3-01/S5-03）。

</frozen-after-approval>

## Implementation Notes

- RelativeTimeFormatter：纯函数注入 now/timeZone；五格式 + 边界（59 秒→刚刚、59/60 分钟→今天 HH:mm）。
- NoteRow 编辑通道（盲审 Critical 的修复）：**编辑文字直接绑定 `model.editingNoteText`**（不再有本地 @State 断链）——Esc（endEditingIfNeeded）、失焦（@FocusState onChange）、收起面板（onClose → endEditingIfNeeded）三个时机保存读到的都是真实内容。进入编辑即聚焦（H2）；点击别处=失焦=结束编辑（H1）。单击另一行时先 endEditingIfNeeded flush 旧行。
- 置顶组按 pinnedAt 降序在视图层排序（H3；未改数据层——observeActive 保持 updatedAt 降序，置顶时间排序只作用于组内展示）。
- 相对时间渲染时取 `Date()`（H4：模型不再持有 now——避免"启动 2 小时后永远刚刚"）；列表不每分钟自刷新，时间随任意观察推送更新（阶段 1 接受）。
- 空内容语义（M2）：saveNoteContent 对 trim 后为空的编辑走 softDelete（03 §5/§7"清空视为删除"）；**撤销提示条与 ⌘Z 由 2.8 接入**（已在 deferred-work 登记）。
- IME 候选窗 Esc（M4）：PopoverController 的裸 Esc 处理在 keyWindow 首响应者为有 marked text 的 NSTextView 时放行（交还输入法取消候选）。
- 行 id 统一 uuidString + 新条目高亮背景（M1）；空组不渲染（L1）；编辑框 minHeight 44 不随内容增高（L3 体验记录，不违反 AC）。
- 测试：NoteListTests 5 个（格式边界、分组随置顶、endEditing 保存/未变不写库、清空删除、置顶删除动作）+ PanelBehaviorTests 更新为真实编辑态；App 66 全绿、包 76 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 Critical / 4 High / 4 Medium / 5 Low），全部处置：

- [critical→已修] NoteRow 本地 @State 与模型断链：Esc/收起面板把便签抹成空串（数据丢失；测试手工赋值掩盖了断链）。编辑文字改为直接绑定模型字段。
- [high→已修] 失焦保存/点击别处结束编辑缺失。@FocusState + onChange 失焦 flush；tap 另一行先 endEditingIfNeeded。
- [high→已修] 进入编辑无焦点。onChange(editingNoteID) 置 @FocusState。
- [high→已修] 置顶组未按 pinnedAt 降序且偏差未落档（评审指出"规格已声明可接受"不实）。已实现 pinnedAt 降序排序，与 AC1/03 §5/frozen 段一致。
- [high→已修] model.now 永不推进（运行两小时后全部"刚刚"）。删除模型 now，渲染时取 Date()；时区注入留待阶段 2（注释改为如实描述）。
- [medium→已修] 新条目滚动定位 UUID/String 类型不匹配 + 无高亮样式。统一 uuidString + 高亮背景。
- [medium→已修] 空内容语义未做未交接。saveNoteContent 空转 softDelete；2.8 交接登记到 deferred-work。
- [medium→已修] L1 边界缺 59 秒/60 分钟。已补。
- [medium→已修] IME 候选窗 Esc 未处理也未登记。PopoverController 组合态直通。
- [low→已修] 空便签组头渲染。加 isEmpty 条件。
- [low→记录] 收起面板保存为 fire-and-forget Task（App 存活则可靠；收起后立即退出 App 有极小丢失窗口，随 2.8 撤销栈设计一并考虑）。
- [low→记录] 编辑框不随内容增高（体验项，不违反 AC）。
- [low→已修] Implementation Notes 未填。本轮填写；status 置 done。
- [info·确认] 待办侧引导句提前启用（2.7 的组件先到位）；time.date 用 %lld 等价于文案表 %-m 记法；范围合规。
