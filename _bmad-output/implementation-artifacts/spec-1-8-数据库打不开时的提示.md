---
title: 'Story 1.8 数据库打不开时的提示'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/failure-modes.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/architecture-diagrams.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 启动时数据库打不开（路径无效、目录不可用、损坏、迁移失败、库来自更新版本）时，App 还没有任何反馈路径，也绝不能拿空库顶替或覆盖用户数据。

**Approach:** AppDelegate 按 architecture-diagrams.md §3 串起启动流程：LaunchOptions（三个调试参数）→ 解析数据目录（默认 `~/Library/Application Support/Shike/`；`-ShikeDataDirectory` 展开 `~`，展开后非绝对路径按 `openFailed(.invalidLocation)` 走失败提示，绝不退回默认）→ `AppDatabase.open`（`simulateWriteFailure` 传入 Options）→ 失败时 `DatabaseOpenFailureAlert` 循环（重试=重新走完整打开；打开数据目录=访达后再次提示；退出=terminate）。`-ShikeSimulateDatabaseOpenFailure` 只让首次尝试抛 `openFailed(.simulated)`。`ErrorText` 把 11 种 `DataFailureReason` 映射为 app-shell.md 文案表文案；`AppEnvironment` 增加 `dataDirectory` 注入。文案全部来自 Localizable.xcstrings；日志按 conventions.md（data/ui 分类，只记分类与代码）。

## Boundaries & Constraints

**Always:** 提示期间不组装 AppEnvironment、不建菜单栏图标；`NSApp.activate()` 先于提示；文案与文案表逐字一致。

**Never:** 不改用内存库、不新建空库、不改动原文件；不实现主菜单/菜单栏图标/备份（1.9～1.13）；`SHIKE_TEST_HOST=1` 时全部跳过。

</frozen-after-approval>

## Implementation Notes

- LaunchOptions 从 `ProcessInfo.arguments` 解析（`init(arguments:)` 可注入测试）；值 YES 大小写不敏感；`DataDirectory` 三态 default/custom/invalid，invalid 保存展开后的路径并交给 `AppDatabase.open` 的绝对路径校验拒绝，从而走与真实打不开完全相同的提示路径。
- `Support/Log.swift` 按 conventions.md 定义四个 category 的 Logger；打开失败写 `data`（分类/代码 .public），提示展示写 `ui`。
- AppEnvironment 增加 `dataDirectory: URL`（app-shell.md 契约的 init 签名）；BackupService 与 PanelModel 仍留待 1.13/1.9-1.10。
- 文案表全部键一次性写入 Localizable.xcstrings（后续故事直接用键）。
- 盲审后加固：`-ShikeDataDirectory` 同时接受 `-Flag=值` 写法；裸旗标（缺值）判为 invalid 而非退回默认，堵死"静默碰真实数据目录"的通道。
- 验收结果：ShikeTests 新增 LaunchOptionsTests（6 例）、ErrorTextTests（11 种原因逐字对照文案表），xcodebuild test 通过；checks.sh 通过。

## Review Triage Log

盲审（Blind Hunter）结论 pass、无 high；4 条 low 全部处理：
- [low→已修] ErrorText.swift 归位到 Shike/Support/（app-shell.md「文件布局」表的规定位置）。
- [low→已修] 裸旗标 `-ShikeDataDirectory` 缺值按 invalid 处理，并新增 `-Flag=值` 语法；不再退回默认目录。
- [low→已修] 日志分类改由 ShikeDataError.classification 统一给出（`类别/原因`），不再硬编码 openFailed 前缀；openInFinder 注释说明忽略 NSWorkspace.open 返回值。
- [false×5] 状态机与 §4 一致、模拟参数只失败一次、48 键文案与文案表逐字一致、~ 展开与相对路径判定、方案参数预置——复核均不成立。
