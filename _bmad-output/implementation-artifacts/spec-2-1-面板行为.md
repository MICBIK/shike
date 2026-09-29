---
title: 'Story 2.1 面板行为——Esc 与尺寸记忆'
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

**Problem:** 面板不能按 Esc 收起，尺寸固定 360×520 不能调整也不记忆；列表行编辑（2.6/2.7 引入）需要一个统一的"结束编辑"入口，Esc 的两级顺序要先把框架搭好。

**Approach:** PopoverController 增加本地按键监听处理 Esc（顺序：结束编辑 → 收起面板；"结束编辑"经 PanelModel 的回调，本阶段返回 false，2.6/2.7 接入真实编辑状态）；新增 PopoverResizeHandle（自 demo 移植：PopoverResizeHandleView + NSCursor 扩展）嵌入面板右下角，拖动实时改 NSPopover.contentSize，鼠标抬起时经纯函数钳制（300×360～600×1000 且不超出所在屏幕可见区域）后保存 `panel.size`；启动时从 `panel.size` 读取初始尺寸（默认 360×520）。Preferences 新增 panelSize。防"刚关又开"（阶段 0 的 10ms）回归验证。

## Boundaries & Constraints

**Always:** 钳制为纯函数并有测试；移植文件按 06 §9 加 GPL 来源头并登记 NOTICE 与 04 §7；新偏好键同步 04 §5.5。

**Never:** 不引入 KeyboardShortcuts（2.2 的事）；不改 ShikeData；不做列表（2.6/2.7）。

</frozen-after-approval>

## Implementation Notes

- Preferences：`panel.size` 以"宽x高"文本存储（`defaults read` 可直接检查），解析失败/零/负/三段一律回落 360×520；默认值同时注册进 `defaultValues`；setter 为 `nonmutating`（本类型是 UserDefaults 门面，无可变状态——这也解决了经由 `AppEnvironment.preferences`（let）写回的编译问题）。
- PopoverController：`init(initialSize:)` 经既有 `clampedSize` 钳制；`applyResize(_:isFinal:)` 实时钳制应用、仅 isFinal 持久化（`persistSize` 闭包由 AppDelegate 接到 preferences）；Esc 用本地 keyDown 监听（面板显示期间安装，didClose/stop 移除），`escapeOutcome(editingHandled:)` 纯函数承载两级顺序；盲审后补：裸 Esc 守卫（`modifierFlags` 为空才处理，⌘/⌥+Esc 放行；IME 候选窗的 Esc 留待 2.6 编辑状态接入时设计）、`shouldDebounceClose(isShown:intervalSinceClose:window:)` 纯函数替代 toggle 内联判断（防抖回归测试由此落地）。
- PopoverResizeHandle：与 demo 行为等价（startSize+translation、minimumDistance 0、hover 光标 push/pop 配对含 onDisappear 兜底）；差异三处均已在来源头/NOTICE/04 §7 登记：回调式去掉单例、系统 crosshair 替代图片光标、省略帮助气泡。
- 接线：PanelModel 增三个 @ObservationIgnored 回调（默认空实现，L2 可注入替身），AppDelegate 以 weak 闭包接到 popoverController/preferences，无保留环；`stop()` 停止 Esc 监听。
- 测试：ShikeTests 42 个全绿（新增 PanelBehaviorTests 8 个：panel.size 默认/往返/损坏回落/解析、Esc 顺序、防抖窗口边界、把手钳制与仅结束持久化、初始尺寸钳制、模型回调默认与注入）；钳制期望值用同一纯函数计算（接线验证，数学由 PanelSizingTests 兜底）。checks.sh 通过；Swift 6 严格并发零警告。
- 坑：新增源文件后必须 `xcodegen generate`，否则工程里找不到新类型（本次实际踩到）。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 medium / 6 low），全部处置：

- [medium→已修] AC 要求的"10ms 防抖回归 L2 测试"缺失。已把 toggle 内联判断提为纯函数 `shouldDebounceClose` 并补防抖窗口边界测试（显示中→关、0.005s→不开、恰 0.01s→开、超窗→开）。
- [low→已修] PopoverController 的 GPL 修改说明头未随本次实质改动更新。已补 S1-01 改动说明并更新日期。
- [low→已修] panel.size 默认值未进 `defaultValues` 注册表（与 conventions"默认值同一处注册"不自洽）。已注册 "360.0x520.0"。
- [low→已修] Esc 监听 self==nil 时吞事件，与同文件外点监听的放行语义相反。已改为放行（return false）。
- [low→已修] 500×600 断言在小屏机器会误报。已与 5000 情形统一：期望值用 clampedSize 计算。
- [low→已修] Esc 监听不区分修饰键。已加裸 Esc 守卫（无修饰键才处理）；IME 候选窗的 Esc 属 2.6/2.7 编辑状态设计，已在本文 Implementation Notes 记录。
- [low→已修] spec 的 Implementation Notes 未填写。本轮已填。
- [确认] 拖动方向与 demo 逐字一致（全局坐标向下拖=增高，面板自锚点向下生长）；onChange 双参签名是 macOS 14+ API，无废弃警告；无保留环；stop() 覆盖新监听；范围合规（无 KeyboardShortcuts、无列表、ShikeKit 未动）。
