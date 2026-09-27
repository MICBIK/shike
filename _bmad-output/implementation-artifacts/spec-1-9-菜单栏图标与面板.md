---
title: 'Story 1.9 菜单栏图标与面板'
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

**Problem:** 拾刻还没有菜单栏存在感：没有图标、没有面板，菜单栏应用的形态尚未成立。

**Approach:** 按移植清单从 demo（基线 e3c0260）移植 `StatusItemController`（模板图标 note.text，辅助功能描述"拾刻"；左键开关面板；本故事右键不响应）与 `PopoverController`（常驻 PanelView；transient、不动画；activate() 后 makeKey；didClose 10ms 防重开；显示期间全局+本地外部点击兜底监听，收起时移除；尺寸 360×520 钳制在图标所在屏幕可见区域，最小 300×360、最大 600×1000 定义为常量）。新建 `PanelModel`（@MainActor @Observable：mode 默认便签可切换、notes/todos 空数组，重启回便签不写偏好）与 `PanelView`（顶栏只有「便签｜待办」分段控件）。AppEnvironment 组装 PanelModel；AppDelegate 在组装之后创建图标与面板。文件头按 06 §9 带来源与修改说明，登记 NOTICE.md 与 04 §7。

## Boundaries & Constraints

**Always:** 常驻内容启动时创建一次；测试宿主不创建图标；移植文件去掉单例与 EventKit。

**Never:** 不做右键菜单（1.11）、不做数据流/空状态/提示条（1.10）、不做尺寸调整把手（S1-01）、不移植 SettingsOpenerView 与 SwiftUI Settings 场景。

</frozen-after-approval>

## Implementation Notes

- 移植要点：didClose 通知记录时间戳防"刚关上又弹开"；didShow 安装外部点击兜底（全局监听转发 assumeIsolated；本地监听吞掉事件以贴合系统 transient 行为）；combine 订阅随 popover 生命周期，监听的停止入口由 applicationWillTerminate 调用（与 App 同生命周期，不在 deinit 里做主线程清理）。
- PopoverController.clampedSize 设计为纯函数（internal static），L2 可直接验证钳制。
- 验收结果：ShikeTests 新增 PanelModelTests（模式默认/切换）与 PanelSizingTests（常量与钳制，3 例），共 16 测试 7 套件全绿；checks.sh 移植文件头检查通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes，已全部处理：
- [medium→已修] PopoverController.visibleFrame 去掉错误的 nonisolated 标注（AppKit 访问不该 nonisolated，且每次编译产生两条主线程隔离警告；clampedSize 保持 nonisolated 纯函数供 L2）。
- [low→已修] StatusItemController 文件头修改说明改为"右键菜单暂不响应（1.11 接 StatusMenu）"，与 NOTICE.md 及代码实态一致。
- [low→已修] 本 spec 的测试计数更正为 16 测试 7 套件。
- [false×2] init 时以 NSScreen.main 回退钳制初始尺寸（toggle 每次显示前会按按钮所在屏幕重新钳制，幂等）；PanelView 根 VStack 结构与 demo 同构、弹出尺寸属真机人工验收——复核均不成立。
- 真机验收遗留：其他 App 前台时面板是否成为关键窗口（必要时补 orderFrontRegardless 回退）。
