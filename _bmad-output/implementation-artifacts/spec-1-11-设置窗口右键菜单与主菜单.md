---
title: 'Story 1.11 设置窗口、右键菜单与主菜单'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
  - '{project-root}/docs/03-交互设计.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 拾刻没有设置入口、右键菜单和主菜单：⌘,、⌘Q 与编辑快捷键不可用，基本操作入口不全。

**Approach:** 移植 `StatusMenu`（设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q）；去掉单例与更新相关菜单项；只在右键时临时挂到图标上，performClick 后卸下）。`SettingsWindowController` 单实例：打开先 `NSApp.activate()` 再 `makeKeyAndOrderFront`（不在最前的回退由真机验收）；已打开再选设置只带到最前并停在当前分页；"关于拾刻"打开并切到关于分页。`SettingsTab` 有序注册表：通用、快捷键、提醒、卡片、数据、关于，前五页占位"将在阶段 N 提供"（1、1、2、3、4），关于页本故事先显示图标、名称、版本（Info.plist）。启动时在组装之后、图标之前建立隐藏主菜单：应用菜单（设置… ⌘,、退出拾刻 ⌘Q）与编辑菜单（undo/redo/cut/copy/paste/selectAll，target nil）。登记 NOTICE.md 与 04 §7。

## Boundaries & Constraints

**Always:** 分页由有序注册表定义，后续阶段只替换占位视图；文案全部来自 xcstrings。

**Never:** 不移植 SettingsOpenerView、不用 SwiftUI Settings 场景；关于页的源码/法律声明/致谢由 1.12 补全。

</frozen-after-approval>

## Implementation Notes

- StatusMenu 保留 demo 的 NSObject+target 形态（NSMenuItem.target 弱引用，实例由 AppDelegate 持有保活）；动作经 Actions 闭包回调 AppDelegate。
- SettingsWindowController 持有 @Observable SettingsModel（分页选择），SwiftUI TabView 绑定；窗口标题复用 menu.settings 文案，不新增键。
- 主菜单设置项 target 为 nil，经响应链落到 AppDelegate 的 @objc 方法；退出用系统 terminate: 选择器。
- 验收结果：ShikeTests 新增 MainMenuTests 2 例（菜单项/选择器/快捷键逐项）、SettingsTabTests 2 例（顺序与占位阶段号）、StatusMenuTests 1 例（四项+分隔线+动作回调），共 28 测试 11 套件全绿；checks.sh 通过。
- 设置窗口标题新增独立键 settings.window.title（"设置"，无省略号）；窗口按契约持有 NSWindow 与 NSHostingController。

## Review Triage Log

盲审（Blind Hunter）结论 pass，4 条 low 全部处理：
- [low→已修] SettingsWindowController 改为持有 NSWindow 与 NSHostingController（对齐 app-shell.md/04 §6.9 措辞）。
- [low→已修] AppDelegate 过期注释更正（只剩备份由 1.13 接入）。
- [low→已修] 窗口标题改用独立键 settings.window.title（"设置"），不再复用菜单项的"设置…"。
- [low→已修] 本 spec 测试计数更正为 5 例新增/28 全套。
- [false×3] 程序化 NSWindow 的 isReleasedWhenClosed 风险（强 ARC 引用实测可安全复用）、performClick 重入递归与右键被面板监听吞掉（与 demo 同构；状态栏图标处监听返回 false）——复核均不成立。
- 真机验收遗留：设置窗口不在最前时的 orderFrontRegardless 回退。
