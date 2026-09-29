# Story 4.7 实现规格：卡片上编辑（S3-06）

- context: SPEC-stage-3-cards/SPEC.md（CAP-7）；ADR-025 结论 4（编辑焦点）；docs/03 §10.2；deferred-work 2.8（清空语义）

## 实现

- `CardModel` 增 `isEditing`/`editingText`；`CardContentView` 双击正文进入 `TextEditor`（FocusState 下一拍聚焦；`onExitCommand` 接 Esc 结束）。
- `StickyCardPanel.allowsKey` 编辑态置 true（borderless+nonactivatingPanel 子类可成为 key，ADR-025 实测）；结束置回 false。
- 编辑中不自动隐藏：`beginEditing/endEditing` 经 `autoHide.setBusy`（S3-03 状态机的 busy 输入）。
- **点击外部结束**：`panel.delegate = self`，`windowDidResignKey` → `endEditing(save: true)`。
- **防抖自动保存**：0.5 秒（FR44 同面板）；收尾（Esc/失焦/✕ 关闭）立即保存；保存走 `Actions.updateNoteContent` → `PanelModel.saveNoteContent`——与面板完全同语义（未变跳过、清空=软删除入撤销栈、失败提示条+重试）。
- **双向同步**：同一观察流；`apply(card:note:)` 编辑中不改写正文（本地编辑是唯一真相，保存后经流回流）。
- 关闭卡片（✕/取消钉住）先冲未保存编辑再关闭。

## 测试

- 编辑 UI 的焦点/IME 属 L3（ADR-025 L3 项）；保存语义复用 `PanelModel.saveNoteContent`（面板侧 DeleteUndoTests 覆盖清空=删除、未变跳过）。
- 回归：App 167 全绿。

## Post-story notes

- 双击后键盘焦点落地与中文 IME 在真机复核（晨报清单）；若 FocusState 落焦失败，备选方案是给编辑态换原生 NSTextView（4-8 恢复工作前不动）。
- Esc 优先级：卡片编辑 > 面板编辑 > 搜索 > 收起面板（各自窗口独立监听，无冲突）。
