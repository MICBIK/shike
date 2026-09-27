---
title: 'Story 1.16 排除误识别、高亮与标题清理'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/parser.md'
  - '{project-root}/docs/05-中文日期解析规格.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 解析器会把"两点意见""点心"这类非时刻的"X点"识别成时间（05 §6），没有标题清理（05 §7），§9.10～§9.13 的用例与守护测试缺失。

**Approach:** 实现 05 §6 规则 A1～A4（"第"前、有/这/那/共/另 前、"点"后组成词、后跟内容词 → 不识别；例外：前面紧挨时段词或后面带分钟/半/整/钟时一定识别，只影响时刻部分、日期照常）；实现 `TitleCleaner.clean(_:removing:)` 严格按 05 §7 五步；补齐 §9.10（J01～J13）、§9.11（K01）、§9.12（L01～L05）、§9.13（M01～M08）共 27 个用例；守护测试从 docs/05 提取 §9 全部（编号, 输入）与测试数据做对称差，125 个用例必须一一对应，任何一侧不同步 CI 即失败。

## Boundaries & Constraints

**Always:** 清理严格按 §7 原文五步；Issue #2 跟踪步骤顺序修订，本故事不改。

**Never:** 不打包第三方许可证；不修改 05。

</frozen-after-approval>

## Implementation Notes

- A 规则实现于 X点 分类的候选级检查（classifyTime 内，越界/歧义返回 nil 即丢弃候选）；遮蔽文本中的前导"_"不影响前后文判断（"_"不在任何排除集合）。
- ParserSectionTests 的九个小节用例数组提升为 static 并暴露 allRegistry（id→input），守护测试据此与 §9.10～9.13 的 27 例合并比对。
- 验收结果：J01～J13 全部返回 nil；K01 识别为 09-24 全天仅高亮"明天"；L01～L05 区间逐一相等；M01～M08 标题逐一相等；守护测试 125=125 且对称差为空。解析器目标 16 测试、全包 75 测试全绿；checks.sh 通过。
- 本故事的独立盲审并入"全量代码评审（1-1..1-17）"任务统一执行（同为解析器资产，守护测试已机械保证用例同步）。

## Review Triage Log

并入全量代码评审任务（1-1..1-17）。
