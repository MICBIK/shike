---
title: 'Story 3.2 提交与标题清理'
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

**Problem:** 提交时"周五下午三点"会原样进标题，时间没有入账；05 §7 的清理在结尾带标点时漏删"提醒我"（Issue #2，阶段 0 遗留的决定点）。

**Approach:** PanelModel 提交改为载荷制：`todoSubmission(from:)` 在提交时点定格 (title, due)——识别中走 `TitleCleaner.clean(text, removing: matchedRanges)` + due；识别被 ✕ 取消走 `stripWhitespaceAndPunctuation`（05 §7 第 2、4 步豁免）+ nil due；无识别走 `clean(text, removing: [])`（第 3 步提醒词照常）。重试重放同一载荷，不随等待期间识别状态漂移。TitleCleaner 第 3、4 步迭代到不动点（Issue #2 修订）；docs/05 §7 规则 + §9.13 用例 M09～M11 同一提交更新，守护测试计数 125→128。

## Boundaries & Constraints

**Always:** docs/05 与测试同提交同步（守护测试强制）；提交失败输入与识别状态保留；重试期间用户改动的新草稿绝不丢；ShikeKit 零界面依赖。

**Never:** 不改解析规则（只动清理）；不做通知/分组/搜索。

</frozen-after-approval>

## Implementation Notes

- TitleCleaner：第 3、4 步 repeat-until-stable；clean 对 ranges 加越界防御（公共 API，盲审 F3）；新增 stripWhitespaceAndPunctuation（仅空白与标点，全标点输入回退原文）。
- PanelModel：`Submission` 载荷（note(content) / todo(originalText,title,due)）；finishSubmit 按 originalText 比对清空草稿（重试期间新草稿绝不丢）。
- 无识别提交照常清理提醒词（"记得还信用卡"→"还信用卡"，盲审 F2：05 §7 字面语义，豁免仅限 ✕）。
- 测试：TodoSubmissionTests 5 个（清理+due、✕ 豁免、无识别提醒词、重试不漂移、重试成功清空/新草稿保留）；L1 M09～M11 + strip 用例；App 96 全绿（警告即错误）、包 77 全绿（守护 128 同步）、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 high / 1 medium / 3 low / 2 info），全部处置：

- [high→已修] F1 新增 3 个 L2 测试前两个是同步断言，跑在 submit 的非结构化 Task 之前必失败；且本地工程未重新 xcodegen，91 个测试不含新文件（CI 必红）。改 async + waitUntil 截止轮询，重跑 xcodegen 后 96 全绿。
- [medium→已修] F2 无识别提交（"记得还信用卡"）不走第 3 步，与修订后 05 §7 字面冲突。改为 `clean(text, removing: [])`；✕ 豁免保持独立；补 L2 用例。
- [low→已修] F3 clean 公共 API 无越界防御（NSMutableString 抛异常）。where 子句补 NSMaxRange 上界。
- [low→已修] F4 引用漂移：守护测试显示名 125→128、TitleCleaner 注释第 5→6 步、docs/04 "125 行"→"128 行"、规划工件"第 5 步/五步清理/stripWhitespaceAndPunctuationOnly"对齐。
- [low→已修] F5 重试路径缺"成功清空草稿/新草稿保留"断言。补 retryClearsDraftOnlyIfUnchanged（调用计数做确定性等待，消除 banner 竞态）。
- [info→已修] F7 recognizedDue 注释过时（"3.2 接线"）。改为"识别提示与测试用；提交载荷在 todoSubmission 定格"。
- [确认] F6/F8：迭代循环必然终止（每次变更严格缩短字符串）；suffix 顺序保证"提醒我"不被拆分；✕ 窗口行为正确；strip 全标点回退符合第 6 步；载荷定格消除重试漂移。
