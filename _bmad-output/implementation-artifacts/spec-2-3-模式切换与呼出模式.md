---
title: 'Story 2.3 模式切换与呼出模式'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/app-shell.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 面板模式是硬编码的便签、重启不记忆；没有"呼出时进入"的设置；⌘1/⌘2 不生效；设置-通用还是空占位。

**Approach:** Preferences 新增 `panel.lastMode`（默认 note）与 `panel.openMode`（默认 last，非法值回落 last）；PanelModel 接收 Preferences，`mode.didSet` 持久化 lastMode；呼出决策为纯函数 `initialMode(openMode:lastMode:)`，由 PopoverController 的 didShow 经回调触发 `applyOpenMode()`（每次呼出都应用，而非只在启动时）；面板显示期间的本地 keyDown 监听扩展 ⌘1/⌘2（经回调切模式，事件被消费）；设置-通用分页以"呼出时进入"三项选择真实化（开机自启项属 2.9）。**范围说明：**"在输入框中按 Tab"的切换依赖快速输入框（Story 2.4 的 CaptureTextView），本故事交付模式决策与回调框架，Tab 键随 2.4 在输入框内接线——此为故事顺序的既定安排，不是遗漏。

## Boundaries & Constraints

**Always:** 呼出决策是纯函数并有 L1 全组合测试；两个新偏好键集中在 Preferences.Key、默认值同处注册、同步 04 §5.5；general 分页的 placeholderStage 置 nil（已有真实内容），其断言同步更新。

**Never:** 不实现 CaptureTextView/Tab（2.4）；不做开机自启设置项（2.9）；不改 PopoverController 的开关语义。

</frozen-after-approval>

## Implementation Notes

- Preferences：`panel.lastMode`（默认 note）、`panel.openMode`（默认 last），非法存储值由消费端回落（存储层原样返回，解析在 PanelModel/SettingsModel）。
- PanelModel：init 第三参注入 Preferences；init 内读取 lastMode（init 赋值不触发 didSet，不产生额外写入）；`mode.didSet` 仅在变化时持久化；`initialMode(openMode:lastMode:)` 纯函数；`applyOpenMode()` 先读后写——openMode 为固定模式时呼出会经 didSet 改写 lastMode，这是 AC 括号句（"呼出不改写 lastMode 之外的状态"）明文许可的唯一写入。
- PopoverController：didShow sink 追加 `onShow` 回调（每次呼出应用 openMode）；Esc 监听扩展为通用面板按键处理（裸 Esc → escapeHandler，⌘1/⌘2 → modeKeyHandler；盲审后修饰键改为精确匹配 `subtracting([.numericPad, .function, .capsLock]) == .command`，杜绝 ⌘⌃1/⌘⌥1 误消费；⌘⇧1 因 charactersIgnoringModifiers 保留 Shift 产出 "!" 天然安全）。
- 设置：general 分页以"呼出时进入"三选一真实化（placeholderStage 置 nil，MainMenuTests 断言同步）；SettingsModel 改为持有 hotkeyService + preferences（AppDelegate 组装），panelOpenMode 计算属性供 @Bindable 绑定。
- 范围交接（盲审 Low-4）：AC1 的"输入框内 Tab"子句与 AC2（草稿互换、占位文案随模式变化）依赖快速输入框，随 Story 2.4 实现并验收——2.4 的 spec 须显式接走这两条，避免验收缝隙。
- 测试：ModeSwitchTests 5 个（initialMode 全 6 组合、偏好键默认/往返/非法、init 读 lastMode、切换持久化 + applyOpenMode、非法 openMode 回落）；App 51 全绿、包 76 全绿、checks 通过；PanelModelDataTests 的 suite 清理统一为 makeModel 返回 cleanup 闭包 + 调用方 defer。

## Review Triage Log

盲审（Blind Hunter）结论 **pass**，处置 4 low + 3 info：

- [low→已修] ⌘1/⌘2 修饰键包含匹配会误消费 ⌘⌃1/⌘⌥1。已改精确匹配并豁免设备位。
- [low→已修] initialMode 组合测试缺 2 条（AC 要求全组合）。已补至 6 组合。
- [low→已修] PanelModelDataTests 新建 suite 未清理（与 2.2 Low-1 同款）。已统一 makeModel 返回 cleanup + defer。
- [low→已记录] AC1 的 Tab 子句与 AC2 依赖 2.4 输入框，规格只记录了 Tab。已在 Implementation Notes 显式交接给 2.4。
- [info·判定相符] applyOpenMode 固定模式呼出改写 lastMode 是 AC 括号句明文许可的行为，非缺陷；语义后果已记入 Implementation Notes。
- [info·确认] init 赋值不触发 didSet（无多余写入）；didSet 的 guard 使幂等呼出为 no-op；@Bindable 绑定计算属性直写 preferences 合法。
- [info·留 L3] onShow 在 didShow 回合执行，通常无可视闪烁；组合态下 ⌘1/⌘2 的行为随 2.4 输入法定义一并处理。
