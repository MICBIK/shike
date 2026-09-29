---
title: 'Story 2.5 呼出即打字与草稿'
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

**Problem:** 快捷键呼出到输入框获得焦点之间存在空窗，性子急的用户此刻打字会丢字；草稿的"退出拾刻重开恢复"（2.4 已持久化）还差呼出聚焦与回放的完整链路验证。

**Approach:** 移植 TypingBuffer（源：NewReminderTypingCoordinator + ContentView 的按键监听）：可打印按键（无 ⌘/⌃ 修饰）在面板未显示期间被本地监听截获入缓冲（上限 200，丢弃最早），输入框成为焦点时经 `keyDown(with:)` 按序回放；面板收起/显示后丢弃缓冲。CaptureTextView 增加 onViewReady 钩子（becomeFirstResponder 就绪回调，回放在此触发）。判断逻辑提为纯函数 isTypingEvent。草稿链路（2.4 已有持久化）在 L2 验证完整闭环。

## Boundaries & Constraints

**Always:** isTypingEvent 与缓冲上限为纯函数并有 L1；缓冲事件只在主线程（与 demo 一致存 NSEvent）；GPL 来源头 + NOTICE + 04 §7。

**Never:** 不用全局监听（app 未激活时的击键不属于拾刻）；不改 PopoverController 的收起语义；列表不在本故事。

</frozen-after-approval>

## Implementation Notes

- TypingBuffer（移植）：isTypingEvent 纯函数（无 ⌘/⌃ 的可打印字符 + **裸回车 "\r" 显式入缓冲**）；appended 纯函数（上限 200 丢最早）；replayPendingEvents 单趟回放（无 demo 的 isHandoffActive 门——面板显示期监听不入队，无重入可能）。
- **盲审高项的修复——回车链路**：① isTypingEvent 为 "\r" 开口（⌘↩/⌃↩ 不缓冲）；② CaptureNSTextView 增加 isReplayingKeys 标志，Coordinator 的 doCommandBy/shouldChangeTextIn 读修饰键时回放期间按"空"处理——绕开 NSApp.currentEvent 残留呼出热键 ⌃⌥ 的问题，回放的回车据此走 .submit；标志由 AppDelegate 的 replayBufferedKeys 接线在回放前后置位/复位。
- **盲审中项的修复——截获条件**：installMonitor 参数改为 shouldInterceptKeys（"呼出空窗"语义）= 输入框未就绪（!isCaptureReady）且焦点不在其它键窗（NSApp.keyWindow 非面板窗口时放行，不吞设置窗口等的按键）。PanelModel 新增 isCaptureReady + beginCaptureWindow（onShow 复位）/endCaptureWindow（onClose 复位）+ captureDidBecomeReady（就绪置位 + 触发回放）。
- 已显示但输入框未就绪的丢字窗口（盲审中低项）：就绪语义调整后同样入缓冲覆盖；彻底闭环依赖 L3 实测"按 ⌃⌥N 后立刻狂敲+回车"。
- 测试：TypingBufferTests 6 个（分类 12 例含 \r 三态、上限丢最早、按序回放+清空、reset、就绪生命周期）；删除了无窗口夹具噪音（keyDown 不依赖窗口）。App 61 全绿、包 76 全绿、checks 通过。
- 草稿 AC（收起保留/切模式保留/退出重开恢复）2.4 已实现并测试，本轮复核交接成立。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 high / 1 medium / 1 medium-low / 1 low / 2 提示），全部处置：

- [high→已修] 回车不被缓冲（"\r" 属控制字符被排除），且回放的回车不会提交（NSApp.currentEvent 残留呼出热键修饰键 → newlineDecision passThrough）。已修复：isTypingEvent 为 "\r" 开口 + isReplayingKeys 回放通道（修饰键按空处理），补 \r 三态断言。
- [medium→已修] 截获条件只看面板未显示，会吞掉设置窗口等其它键窗的按键并串扰缓冲。已加目的地判定（keyWindow 非面板窗口放行）。
- [medium-low→已修] "已显示但输入框未就绪"的放行丢字窗口（demo 覆盖了这半边）。就绪语义调整后（isCaptureReady 未置位即截获）该窗口同样入缓冲。
- [low→已修] 回放测试的窗口夹具失效（textView 未挂窗）且注释前提错误。已删除夹具，注释改为"keyDown 不依赖窗口"。
- [提示→已修] isTypingEvent 缺 "\r" 显式断言。已补（含 ⇧↩ 语义注释与 ⌘↩ 反例）。
- [提示·核查通过] 监听生命周期与三条 keyDown 监听链的顺序；Swift 6 并发（NSEvent 不跨隔离域逃逸）；demo 移植等价性（enqueue 上限为规格要求的增强）。
- 遗留 L3 人工项：真实"⌃⌥N 后立刻狂敲一串+回车"端到端（含时序极限）。
