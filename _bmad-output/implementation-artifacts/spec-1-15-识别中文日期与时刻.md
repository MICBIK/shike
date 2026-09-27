---
title: 'Story 1.15 识别中文日期与时刻'
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

**Problem:** ShikeDateParser 只有契约类型（1.1），没有解析器实现；阶段 2 的时间识别（S2-01）无可用依赖。

**Approach:** 按 parser.md「从 TZMemo 迁入」：第一步把 `../TZMemo/Packages/TZMemoDateParser/Sources/TZMemoDateParser/` 原样复制入 ShikeDateParser（改名+文件头，单独提交）；第二步按差异表改为新 API（struct/Sendable/init(timeZone:)/parse(_:now:) 必传/结果映射 hasTime），并以 05 §9.1～§9.9 的 98 个用例驱动修复全部行为差异（含：全天 00:00、时段词即有时刻、§4.4 换算表、无前缀周X 才顺延且全天当天不顺延、周一为一周之首、移除"当天"、新增 今早/下周/周末/冒号时间/相对时长/三点钟、非法日期不识别、区间按位置排序、正则 static let）。不迁入 parser-check。

## Boundaries & Constraints

**Always:** 内部固定公历、周一为首；时区只取 init 参数；不出现 Calendar.current/Locale.current/autoupdatingCurrent。

**Never:** 不迁入 parser-check；旧断言与 05 冲突时以 05 为准。

</frozen-after-approval>

## Implementation Notes

- 两个提交：原样迁入（除两处必要的模块适配：旧 DateParseResult 删除、parse 返回映射到契约类型）与 05 对齐实现+98 用例。
- 差异表 17 项逐条落实；关键实现点：periodHint 分支保留（今晚/明早等时段词算有时刻）；weekend/下周 并入 DayKind；冒号与 X点正则的 \s* 前导空格在候选裁剪中扣除以保高亮精确；相对时长小时前缀剥"个"。
- 盲审后修复：非法日期（2月30号）回读年月日校验失败时候选整体不识别（原回退"今天"）；分类链传入 now 取代墙钟 Date()；午后独立时段（默认 14:00、1～11 加 12）；init 补 `.current` 默认值；下个周末归入下周末；测试区间长度改用 UTF-16 距离。
- 验收结果：ShikeDateParserTests 新增 ParserSectionTests（9 个小节测试覆盖 98 用例，含 hasTime 与高亮区间断言），两个测试目标合计 70（11+59）全绿；checks.sh（含解析器区域与禁用项检查）通过。
- 范围说明：差异表中的 A1～A4 歧义规则、TitleCleaner 与守护测试随 Story 1.16 落实（其验收标准显式覆盖 05 §6/§9.10～§9.13）；本故事完成 §9.1～§9.9 可驱动的其余全部差异项。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes，处理如下：
- [high→已修] 05 对齐层与测试未提交——本提交补齐（迁入提交 a84f6a6 之后的全部修改）。
- [high→已修] 非法日期被宽松进位后回退"今天"——改为分类期回读校验（年月日一致），失败时候选丢弃、整体返回 nil。
- [high→已修] 午后并入中午——独立 earlyAfternoon 时段（默认 14:00、1～11 加 12；H03 不再依赖巧合）。
- [high→分范围] A1～A4 歧义规则缺失——按故事拆分归 1.16（其验收标准显式覆盖），本故事范围内无 §9.1～9.9 用例可驱动。
- [medium→已修] init 缺 .current 默认值；分类链用墙钟 Date() 取年份——已传入 now。
- [medium→1.16] 守护测试（05 §9 对称差）——1.16 验收标准显式要求，随 1.16 实现。
- [low→已修] 「下个周末」正则与分类矛盾；测试区间长度改 UTF-16 距离；spec 计数表述改为"两目标合计 70（11+59）"。
- [low→不修] bestMatch 首匹配不回退（越界首个匹配丢弃后不再找后文）——符合 05"宁可不识别"原则，记录备查。
- 98 用例、API 形状、static let 正则、周一为首、迁入提交最小适配均经盲审实测确认无误。
