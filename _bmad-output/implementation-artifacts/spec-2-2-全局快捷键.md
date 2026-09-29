---
title: 'Story 2.2 全局快捷键'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/scope-boundaries.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 面板只能点击图标开关；没有全局快捷键，"3 秒捕捉"的前提缺失。设置-快捷键分页还是占位。

**Approach:** 引入 KeyboardShortcuts 3.1.0（MIT，ADR-015，精确版本锁定，登记 NOTICE）；新增 `Shike/Services/HotkeyService.swift`（自 demo KeyboardShortcutService 移植改造：去单例、依赖注入、默认开启）：快捷键名 `togglePanel`，默认 ⌃⌥N；启用状态持久化到新偏好键 `hotkey.togglePanel.enabled`（默认 true，与 KeyboardShortcuts 的 enable/disable 桥接，测试可注入替身）；AppEnvironment 组装，AppDelegate 在面板创建后 `register`，动作经 StatusItemController 暴露的图标按钮调用 PopoverController.toggle（锚点与外部点击豁免一致）。设置-快捷键分页真实化：Recorder 录制控件 + 启用开关。

## Boundaries & Constraints

**Always:** KeyboardShortcuts 以 `exact: "3.1.0"` 锁定；移植文件加 GPL 来源头并登记 NOTICE 与 04 §7；新偏好键同步 04 §5.5；L2 不真实注册系统热键（enable/disable 经注入替身测试，真机路径 L3 验证）。

**Never:** 不在 ShikeKit 中引入该依赖（仅 App 目标）；不做"新建便签/待办"快捷键（S4-01）；不改 PopoverController 的开关语义。

</frozen-after-approval>

## Implementation Notes

- 依赖：project.yml 加 KeyboardShortcuts `exactVersion: 3.1.0`（App 目标唯一引用；ShikeKit 未动）；Package.resolved 由工具自动更新（3.1.0，revision 772133d）。
- HotkeyService（移植）：`KeyboardShortcuts.Name.togglePanel` 用 `initial:`（3.1.0 的 API；demo 的 initial 语义在库层——首次写 UserDefaults.standard，用户改后永不复活默认值，移植保留该机制）；`register(onAction:)` 注册 onKeyDown 并按存储状态 applyEnabled，`registered` 幂等（demo 的 onKeyDown 是 append，重复调用会双触发，此处为改进）；`setEnabled` 持久化 `hotkey.togglePanel.enabled` 并调 enable/disable 闭包；init 只读偏好不触库（L2 惰性成立，静态 Name 在测试中零触达）。
- 设置分页：shortcuts 占位取消（SettingsTabTests 断言同步更新）；ShortcutsSettingsView = Recorder + 启用 Toggle；文案键 settings.shortcuts.togglePanel/.enabled（含 extractionState: manual——缺它不生成符号，本次踩坑）。SettingsModel 改为持有 HotkeyService（init 注入），SettingsWindowController 构造参数随之扩展。
- 接线：AppDelegate 在 statusItemController 创建后 register，动作经 `statusBarButton` 调 `popoverController.toggle(from:)`——与点击图标同锚点、同外部点击豁免语义；[weak self] 避环。
- 并发：KeyboardShortcuts 3.1.0 自身 defaultIsolation MainActor；Carbon 回调断言主线程，onKeyDown 闭包内 `MainActor.assumeIsolated` 与库自身模式一致；严格并发零警告。
- 测试：HotkeyServiceTests 4 个（默认开/读关/setEnabled 双向/组装惰性，enable-disable 注入替身，suite defer 清理）；App 46 全绿、包 76 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 **pass**，处置两条 low 与四条 info：

- [low→已修] 新测试未按约定在结束时 removePersistentDomain。已统一 makeSuite + defer cleanup。
- [low→记录] Package.resolved 在 swift test（剪掉 App 依赖 pin）与 xcodebuild resolve（写回）间抖动；真正的锁是 project.yml 的 exactVersion，CI 用全新 checkout 不受影响。接受现状，提交说明注明该文件由工具生成。
- [info·判定合规] ShortcutsSettingsView 直接 import KeyboardShortcuts 用 Recorder——spec Intent 与 app-shell.md 明文要求该控件放设置分页，注册/启用逻辑全部经 HotkeyService 中介，按契约语境合规。
- [info·与 demo 一致] Recorder 清空组合后库标记 disabled 而偏好开关仍为开（isEnabled 是"用户想要启用"的镜像）；与 demo 行为一致，留作后续 UX 打磨（可展示 getShortcut(for:)）。
- [info] 动作闭包强捕获 popoverController（全局静态存储）——均为应用生命周期单实例，无实际泄漏。
- [info] 包测试计数 76（此前简报写 78 有误），与 @Test 源码计数一致。
- AC 六条在 L2/代码层面全部满足；Library 源码审计（Name/KeyboardShortcuts/HotKey/Recorder/Package）逐一对照；真机 ⌃⌥N 行为归 L3。

## Post-Story Fix Log（验收期，2026-09-28）

人工验收第 1 项即失败：真实按下 ⌃⌥N 面板无反应。排查结论与处置：

- **根因（外部环境，非本项目代码缺陷）：** macOS 26 起 Carbon `RegisterEventHotKey` 的回调不再触发。本机 lldb 断点证实注册链完整执行（`registerIfNeeded → HotKey.init → HotKeyCenter.register → RegisterEventHotKey` 返回成功），但热键永不回调；独立 CLI 持有者（InstallEventHandler + RegisterEventHotKey + RunLoop）同样永不触发。社区有相同记录（voiceTyper 因此迁移 NSEvent 监听）。KeyboardShortcuts 3.1.0（当时最新，2026-09-11 发布）无修复。
- **修复（ADR-021）：** 新增 `Shike/Services/HotkeyEventTap.swift`——激活机制改走 CGEventTap（`cghidEventTap` + `defaultTap`，命中即消费按键）；KeyboardShortcuts 仍负责录制（Recorder）与存储（defaults）。两条通道共用 `dispatchHotkeyAction`，150ms 内重复触发折叠为一次（未来 Carbon 若恢复不会双动作）。匹配只比较 ⌃⌥⌘⇧ 四个修饰位——实测系统会在事件上附加 SecondaryFn（0x2000_0000，无同名 CGEventFlags 成员）等额外位，`subtracting` 无法对未知位容错。
- **权限：** `defaultTap` 需要"辅助功能"授权；未授权时 install 弹系统提示并返回 false，`HotkeyService.tapAuthorizationDenied` 置位，设置-快捷键页显示提示，onAppear / 录制变更 / 开关切换时重试安装。注意本地 ad-hoc 签名下授权与具体构建绑定，重新构建后需重新授权（正式分发的签名构建不受此影响）。
- **测试：** HotkeyServiceTests +3（tap 通道启停生命周期、安装失败/组合清空、150ms 去重用合成时间验证）；App 83 全绿（警告即错误）、包 76 全绿、checks 通过。真机按键归 L3 人工验收。
