---
title: 'Story 1.10 面板的数据与错误提示'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/failure-modes.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 面板还没有接真实数据：空状态、条数占位、错误提示条都不存在，观察流无人消费，读写失败悄无声息。

**Approach:** PanelModel.start() 在自己持有的 Task 中用 `for try await` 消费便签（observeActive → [NoteListItem]）与待办（observeActive → [Todo]）两个观察流；停止/释放时取消。`report(_ error:retry:)` 生成提示条：writeFailed → "保存失败：原因"+重试（调用传入闭包）；readFailed → "读取失败：原因"+重试（重新订阅 start()）。PanelView 顶栏下方显示红色提示条；当前模式列表为空时显示空状态（便签 note.text/"还没有便签"，待办 checklist/"没有待办"，无引导句），非空显示"共 N 条（列表将在阶段 1 提供）"，N 随数据自动更新。report 写日志 category data（仅分类与代码）。

## Boundaries & Constraints

**Always:** 提示文案经 ErrorText 与 xcstrings；重试语义如上。

**Never:** 不做输入区、列表行、引导句（S1-10）；不做角标/搜索/⋯（S2）；不引入真实写路径（阶段 0 无输入界面）。

</frozen-after-approval>

## Implementation Notes

- 双流消费用两个存储的子 Task（TaskGroup 的 @Sendable 闭包无法捕获 @MainActor 的 self）；Task.cancel 可从 deinit 调用（nonisolated），释放时也取消。
- readFailed 重试 = 重新调用 start()（先取消旧任务再重建订阅）；清除读取失败提示条绑定在"重新订阅后的首批数据"上（pendingLoadBannerClear 标志），另一条仍在运行的流的更新不会误清。
- runNotes/runTodos 设计为 internal，L2 用真正以 readFailed/外来错误结束的流驱动全链路（for try await → handleStreamFailure → report）。
- 非取消的正常流结束在 PanelModel 兜底上报 readFailed(.ioError)（仓储层已有同语义转换，此处防数据层语义漂移）。
- 验收结果：ShikeTests PanelModelDataTests 7 例（含误清回归与真实失败链路），共 23 测试 8 套件全绿；checks.sh 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes，处理如下：
- [medium→已修] 提示条误清：清除逻辑改绑 pendingLoadBannerClear 标志（只有重新订阅后的首批数据清除），新增回归测试。
- [medium→已修] readFailed 的 L2 改走真实链路：runNotes 供测试直接驱动以 readFailed/外来错误结束的流；新增非 ShikeDataError 映射用例。
- [low→已修] 循环正常结束的兜底上报（附 data-layer.md 依赖说明）；applicationWillTerminate 补调 panelModel.stop() 使注释与接线一致。
- [low→deferred] saveFailed 提示条被后续 readFailed 覆盖时原重试闭包丢失；saveFailed 重试成功后无人清除提示条——阶段 0 无写路径，均记入 deferred-work.md，随 S1 写路径故事处理。
- [false×4] 双任务存储与 deinit 取消、[weak self]/重入语义、文案逐字、日志无用户内容——复核均不成立。
