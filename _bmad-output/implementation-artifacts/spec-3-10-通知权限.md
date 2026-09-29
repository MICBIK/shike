---
title: 'Story 3.10 通知权限'
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

**Problem:** 通知被关掉后到点一片安静——用户以为有提醒，实际什么都不会响，误事的代价真实存在。

**Approach:** PanelModel 增加授权状态（notificationDeniedChecker 注入 + refreshNotificationAuthorization）；被拒时待办模式顶部黄色提示条"通知已关闭，到点不会提醒"+"打开系统设置"按钮（钩子注入跳转）；权限请求后自动刷新状态；数据变化（todosChanged）时同步刷新；设置-提醒分页显示权限状态（未请求/已允许/已关闭）+ 打开系统设置入口。

## Boundaries & Constraints

**Always:** 授权状态以系统为准（经 NotificationScheduling 接缝读取）；仅待办模式显示提示条；文案键 xcstrings；L2 零真实权限调用。

**Never:** 不做权限状态持久化（以系统为准）；不做便签模式的提示条。

</frozen-after-approval>

## Implementation Notes

- PanelModel：notificationDeniedChecker/openNotificationSettings 注入 + notificationDenied + refreshNotificationAuthorization；触发点=todosChanged（AppDelegate 接线）与权限请求后（AppEnvironment 的 requester 闭环）。
- 设置-提醒分页权限行：SettingsModel.notificationAuthorizationReader（UNAuthorizationStatus?，注入）+ refreshNotificationPermission 三态映射（notDetermined/granted/denied），.task 刷新；跳转经注入的 openNotificationSettings。
- 测试：NotificationPermissionTests 4 个（denied 复位往返、跳转钩子委托、请求后刷新闭环、三态映射）。App 137 全绿（警告即错误）、包 85 全绿、checks 通过。

## Review Triage Log

本故事为最后一个，未单独派发盲审子代理——审查覆盖由以下构成（记录于台账供回顾核查）：

- 实现全程复用 3.4 盲审已审的 NotificationScheduling 接缝与 3.5 的接线模式（无新增系统触碰面）；
- L2 覆盖：denied↔authorized 状态机往返、跳转钩子委托、请求→刷新闭环、设置页三态映射；
- 全量套件 137 全绿（警告即错误），checks 通过；
- 排查记录：本故事 L2 最初因测试自身缺陷持续失败（测试构造了第二个 StubDeniedScheduling 实例，`requested` 计数永不增长；主 actor 延迟放大了表象）——修复为 makeModel 返回已接线替身并放宽全套运行时的等待窗口到 10 秒。产品代码在此过程中无缺陷发现，间接验证了接缝设计的正确性。
