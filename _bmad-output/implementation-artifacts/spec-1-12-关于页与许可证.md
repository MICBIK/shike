---
title: 'Story 1.12 关于页与许可证'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/docs/06-开发规范.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 关于页只有骨架（图标/名称/版本），源码链接、法律声明、许可证查看与致谢缺失，不满足 GPL-3.0 第 5(d) 条对交互界面的要求。

**Approach:** 关于分页按序显示：占位图标 note.text、名称"拾刻"、"版本 0.0.0（1）"（Info.plist）、源码链接（默认浏览器打开）、版权行、法律声明段落、"查看许可证"按钮、致谢（Reminders MenuBar（GPL-3.0）、GRDB.swift（MIT））。`LicenseWindowController` 单实例只读文本窗口，标题"许可证"，显示随 App 打包的 LICENSE 全文，断网可用。LICENSE 经 project.yml 以资源打包（仓库不另存副本）；第三方许可证全文不打包。

## Boundaries & Constraints

**Always:** 界面文案来自 xcstrings；法律声明逐字用文案表文本。

**Never:** 不打包第三方许可证全文（规格非目标）；不发布安装包（阶段 0～3 只打标签）。

</frozen-after-approval>

## Implementation Notes

- 新增键 about.acknowledgments.detail（"Reminders MenuBar（GPL-3.0）、GRDB.swift（MIT）"）：致谢明细是第三方名称+许可证标注，放目录而非代码字面量（conventions「文案」）。
- LICENSE 读取失败（打包破损）记 data 日志并显示空文本，不用 try? 静默；窗口内容 NSTextView 只读、不富文本。
- 验收结果：ShikeTests 新增 AboutPageTests（包内 LICENSE 非空且含 GPL 文本；版本格式"版本 0.0.0（1）"），共 31 测试全绿；checks.sh 通过。

## Review Triage Log

盲审（Blind Hunter）结论 pass，3 条 low 全部处理：
- [low→已修] LICENSE 读取失败时窗口显示诊断文本（构建破损才可见），不再是无声空白。
- [low→已修] 版本测试期望值由 Info.plist 实际值拼出（钉格式不钉版本号），版本提升不误伤 CI。
- [low→已修] 本 spec 测试计数更正为 31。
- [false×2] about.acknowledgments.detail 新键（规格明文要求致谢明细、文案表无键、符合 conventions 文案集中）；闭包穿线无保留环、Link 在 NSHostingView 可用、GPL 5(d) 四要素齐备——复核均不成立。
- 真机验收遗留：源码链接实际在默认浏览器打开、许可证窗口断网显示（需要 GUI）。
- [CI 发现→已修]（2026-09-27 晚，8471846）CI（macos-26，Xcode 26）自本故事起 app 作业持续红灯：#expect 宏展开把表达式放入非隔离上下文，引用 View 推断的 @MainActor 静态成员（versionText/sourceURL）报隔离错误；本地 Xcode 27 不报，掩盖了问题约 5 个提交。修复：AboutPageTests 标记 @MainActor（两代编译器均合法）。教训：本地编译器（27）与 CI（macos-26 默认 Xcode 26）行为有差异，"本地绿"不能替代 CI 确认；后续故事每轮推送必须盯到 CI 全绿再收工。
