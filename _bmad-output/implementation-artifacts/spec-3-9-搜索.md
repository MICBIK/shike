---
title: 'Story 3.9 搜索'
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

**Problem:** 记多了找不回——没有检索入口，翻列表是唯一手段。

**Approach:** ⌘F 或顶栏放大镜进入搜索（搜索框替换输入框位置，焦点自动就位）；范围=未删除便签内容与待办标题（含已完成），不区分大小写 contains，0.2 秒防抖（时长可注入）；结果分「便签」「待办」两组（updatedAt 降序）、匹配子串高亮（AttributedString）；无结果"没有找到「××」"+清除按钮；点击结果退出搜索、切模式、滚动定位、1.5 秒高亮（已完成待办先展开已完成组）；Esc 顺序插入"退出搜索"层；搜索态 TypingBuffer 让位、⌘1/⌘2 消费不切模式。

## Boundaries & Constraints

**Always:** 检索与高亮用 trim 后同口径关键词；防抖时长可注入（NFR21）；已删除不出现在结果（观察流过滤）；文案键 xcstrings。

**Never:** 不做全文检索/正则；不做跨模式结果记忆。

</frozen-after-approval>

## Implementation Notes

- PanelModel：isSearching/searchQuery（didSet 防抖，时长 searchDebounceDelay 可注入）/两组结果/beginSearch（清时间弹层）/exitSearch/locateSearchResult；locateNoteID + 分槽定位清除任务（便签/待办互不吞）；isCompletedSectionExpanded 提升到模型（定位已完成待办先展开）。
- SearchView：SearchRow.matchRanges 纯函数（String.Index 全部命中）+ AttributedString 着色；lineLimit(3)、已完成划线置灰；trim 后 query 同口径高亮（盲审 F4）。
- Esc 顺序更新为结束编辑 → 退出搜索 → 收起面板（AppDelegate escapeHandler）；TypingBuffer 搜索态让位（盲审 F2）；endCaptureWindow 退出搜索（跨呼出残留会静默丢键，盲审 F2）；beginSearch 清时间弹层（盲审 F3）；⌘1/⌘2 搜索态消费不切模式（F7）。
- 测试：SearchTests 7 个（matchRanges、过滤/排序/含已完成、Esc 语义、双模式定位、清空与退出、防抖自动检索、已完成定位展开）。App 133 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（2 high / 3 medium / 4 low / 1 info），全部处置：

- [high→已修] F1 点击已完成待办结果：折叠组无行可滚、定位完全失效。isCompletedSectionExpanded 提升到模型，locateTodo 对已完成目标先展开。
- [high→已修] F2 搜索态跨呼出残留——残留态下"呼出即打字"静默丢键（S1-04 核心承诺回归）。endCaptureWindow 里 exitSearch。
- [medium→已修] F3 ⌘F 穿透"设置时间"弹层，退出搜索后弹层复活。beginSearch 清 editingTimeTarget。
- [medium→已修] F4 高亮用未 trim 的 query——带空格时高亮整体消失。trim 后同口径。
- [medium→已修] F5 防抖不可测未测。时长提为可注入属性 + L2 自动检索用例。
- [low→已修] F6 首键 200ms 防抖窗闪现"没有找到"。（防抖注入后由 runSearch/空态判定覆盖；空态仅在检索后出现。）
- [low→已修] F7 搜索态 ⌘1/⌘2 仍切模式。消费不切模式。
- [low→已修] F8 结果行无 lineLimit/完成态标识 + 死参数。lineLimit(3)+划线置灰+去 title。
- [low→已修] F9 locateClearTask 单槽复用——便签定位后通知点本体，便签高亮常驻。分槽。
- [info→已修] F10：matchRanges 注释改 String.Index；search.empty 引号对齐「」；放大镜补 accessibilityLabel；PopoverController 头注释三级 Esc 更新（部分随代码注释落盘）。
- [info→保留] 设置窗口为 key window 时 ⌘F 被截获（既有 ⌘1/⌘2/⌘Z 同模式，既有债）；搜索期间数据变化结果不重算（快照语义，下次按键自愈）。
