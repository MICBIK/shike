---
title: 'Story 3.1 时间识别与高亮'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-2-reminders/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-2-reminders/stage-2-components.md'
  - '{project-root}/_bmad-output/specs/spec-stage-2-reminders/scope-boundaries.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 待办输入框把"周五下午三点"当纯文字存着——时间要靠人眼从句子里挑出来，阶段 0 就绪的解析引擎没有任何界面入口。

**Approach:** PanelModel 增加识别状态机：待办模式的草稿每次非组合态变化时调 `ChineseDateParser.parse`（注入 now/timeZone），产出 `recognition`（date/hasTime/matchedRanges）与 `recognitionDismissed`（✕ 后置位，草稿清空复位，模式往返保留）；便签模式识别关闭。CaptureTextView 增加 `highlightRanges`——非组合态时把区间以强调色背景应用到 textStorage（组合态绝不触碰属性），带变更守卫避免重复重排。PanelModel 提供 `recognitionHintState`（recognized(主文案/时长后缀/是否已过) / dismissed / nil），PanelView 在输入框下方渲染提示条（🕒 文案 ✕）；文案格式化提为纯函数 `RecognitionHint`/`TimeDisplay`（注入 now/timeZone）。待办占位文案改为「要做什么？比如：周五下午三点交报告」（03 §4）。提交路径不动（3.2 接清理）。

## Boundaries & Constraints

**Always:** 解析与格式化都注入 now/timeZone（NFR22）；组合态不解析、不刷新属性（IME 安全，可观察行为=组合中无高亮）；文案键集中 xcstrings（extractionState: manual）；识别为同步纯计算（NFR21）；草稿恢复（init/呼出/切模式回）后重新解析。

**Never:** 不改提交/清空逻辑与 TitleCleaner（3.2）；不改解析规则与 docs/05；不做通知、分组、搜索；不给 ShikeKit 加任何界面依赖。

</frozen-after-approval>

## Implementation Notes

- PanelModel 识别状态机：`recognition`（DateParseResult）/`recognitionDismissed`/`parseNow` 接缝；重算入口 `refreshRecognition()` 挂在 draftTodo didSet、mode didSet、timeZone didSet、init 末尾与 applyOpenMode 末尾（呼出无条件重算——openMode 与当前模式相同时 didSet 短路，隔夜呼出的相对日必须重算，盲审 H1）。`recognizedDue` 为 3.2 的提交接缝。
- 提示状态 `recognitionHintState`（recognized(Content)/dismissed/nil）：视图每次渲染重算，格式化经纯函数 `RecognitionHint.content`（相对时长判定用正则命中原文，含"之/以"后置写法）；`TimeDisplay` 提供今天/明天/昨天/周X（未来 2～6 天）/M月d日/yyyy年M月d日 HH:mm 文案（03 §6），3.6 的行尾时间复用。
- CaptureTextView：`highlightRanges` 参数；`applyHighlight` 静态函数（守卫键=全文+区间，一致跳过；先整段清 `.backgroundColor` 再按区间补回；越界区间忽略；组合态不应用）。textDidChange 加组合态守卫——组合期间不写回绑定（组合结束 AppKit 以最终文本再回调，不丢字；盲审 M1）。
- 文案：capture.recognition.*（remind/allDay/past/dismissed/dismiss/minutesLater/hoursLater/daysLater）、time.day.*（today/tomorrow/yesterday/weekday/monthDay/fullDate），全部 extractionState: manual；待办占位文案改「要做什么？比如：周五下午三点交报告」。
- 测试：CaptureRecognitionTests 8 个（识别与区间 L05、歧义界面表现、取消/复位、便签模式、init 注入识别+具体日期断言、提示四态文案、相对时长判定、applyHighlight 行为）；App 91 全绿（警告即错误）、包 76 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 high / 3 medium / 3 low），全部处置：

- [high→已修] H1 呼出面板不重解析（applyOpenMode 的 mode didSet 在同模式时短路，隔夜呼出提示显示陈旧日期）。applyOpenMode 末尾无条件 refreshRecognition()。
- [medium→已修] M1 组合态解析未被拦截（textDidChange 组合期间照常写绑定触发 parse）。加 hasMarkedText 守卫；组合结束时 AppKit 以最终文本再回调，不丢字。
- [medium→已剔除] M2 staged 的 Packages/ShikeKit/Package.resolved 与本故事无关（swift test 剪掉 App 依赖 pin 的已知抖动，阶段 1 台账已记录）。已还原到 HEAD；真正的锁在 project.yml 的 exactVersion。
- [medium→已修] M3 "周X" 硬编码绕过 xcstrings。新增 time.day.weekday（"周%@"）键。
- [medium→已修] M3b 恢复草稿测试的 parseNow 注入是死代码。timeZone/parseNow 提为 PanelModel.init 参数，测试直接构造模型并断言具体日期（明天 = T0+24h）。
- [low→已修] L1 相对时长后缀："之/以"后置写法并入正则；23.5 小时以上归并"1 天后"（避免 86399 秒显示"24 小时后"）。
- [low→已修] L2 dayText 注释与实现不符（±6 天 → 仅未来 2～6 天）。
- [low→已修] L3 ✕ 按钮无 accessibilityLabel。补 capture.recognition.dismiss 键。
- [确认] didSet 链无重入；守卫链完备（mode→draft→dismissed）；全天恒不红；applyHighlight 只动 backgroundColor、守卫键含全文防重复；测试不污染真实偏好；阶段 1 提交/草稿/Esc 语义零改动。
