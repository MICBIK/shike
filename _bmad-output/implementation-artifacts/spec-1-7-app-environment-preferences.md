---
title: 'Story 1.7 组装点与偏好设置'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** App 层还没有组装点：后续的服务、窗口、偏好键没有固定接入位置，测试也无法脱离真实数据组装 App 逻辑。

**Approach:** 实现 `AppEnvironment`（@MainActor、持有 database + 三仓储 + Preferences，不建窗口不建图标；BackupService 与 PanelModel 随 1.13/1.9 接入）与 `Preferences`（init(defaults:) 接收 UserDefaults；键名与默认值同处注册；本阶段仅 `backup.keepCount`，默认 7）。

## Boundaries & Constraints

**Always:** 除 AppEnvironment 外无全局单例；依赖经初始化参数注入；键名与 04 §5.5 一致。

**Never:** 不创建窗口/菜单栏图标；不实现 BackupService（1.13）与 PanelModel（1.9/1.10）。

</frozen-after-approval>

## Implementation Notes

- Preferences 默认值经 `UserDefaults.register(defaults:)` 在 init 时注册（suite 内内存生效，测试结束 removePersistentDomain 即清干净，符合"空 suite 读到 7"验收）。
- 验收结果：ShikeTests 新增 AppEnvironmentTests（组装后经仓储写入、从同库观察读到）与 PreferencesTests（默认 7 / 写读回 / suite 清理），xcodebuild test 通过；checks.sh 的禁用项检查（static shared）通过。

## Review Triage Log

- 自查修正四处 Swift 6 严格并发/测试问题：`[String: Any]` 静态默认表改计算属性（避免非 Sendable 共享状态）；Preferences 因 UserDefaults 非 Sendable 不声明 Sendable（随主 actor 使用，1.13 备份服务取值时快照）；ShikeTests 目标补 ShikeData 依赖；struct 属性赋值需 var 声明。
- App 层测试新增 3 项（组装读回、不建窗口、偏好默认/写读/suite 清理），xcodebuild test（严格警告模式）通过；checks.sh 通过。
