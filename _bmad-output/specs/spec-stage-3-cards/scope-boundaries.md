# 阶段 3 · 范围与边界（scope-boundaries）

## 修改的组件

### NoteListView / NoteRow（Shike/Panel/NoteListView.swift）

- 右键菜单新增"钉到桌面"（已钉显示"取消钉住"）；已钉便签行显示图钉标记（`item.isPinnedToDesktop`，SF Symbol `pin`，青绿色）。
- 纸感卡片样式（PaperCard 装订条）不变；钉出动作走 PanelModel 回调。

### PanelModel（Shike/Panel/PanelModel.swift）

- 新增**钉出/收回动作**：`pinNoteToDesktop(id)`（经 StickyCardRepository 创建，默认值来自 `card.default.*` 偏好）、`unpinNoteFromDesktop(id)`；动作与面板数据流解耦（卡片有自己的控制器集合）。
- 新增**在面板中显示**回调目标：供卡片菜单"在面板中显示"复用（呼出面板 + 切便签 + locateNoteID 高亮）。
- 删除/撤销联动保持既有 deleteNote/undo 路径，卡片随观察流自行进退（卡片控制器订阅便签与卡片两条流，见下），PanelModel 不直接操纵卡片窗口。

### 新组件：StickyCardController / StickyCardWindow（Shike/Cards/）

- 职责：一张便签卡片对应一个控制器 + 一个 `NSWindow`（contentViewController 用 SwiftUI 或 NSView，按 CAP-1 结论）；管理层级、空间行为、自动隐藏状态机、编辑态、拖动与缩放、右键菜单。
- **自动隐藏状态机**（纯逻辑抽为可测类型 `AutoHideStateMachine`，注入时钟与"鼠标是否在卡片上"）：显示中→(离开满 N 秒)→淡出中→隐藏中→(悬停 0.2 秒)→淡入中→显示中；编辑/菜单/拖动期间强制显示中；淡出淡入参数 0.3/0.15 秒经 Motion 降级。
- **唤回监听**：按 CAP-1 结论选型（全局 mouseMoved 监听或低频轮询 `NSEvent.mouseLocation`）；监听器在卡片管理器中共享一个（不每卡一个），分发命中到各卡片。
- **坐标换算与恢复**：`stickyCard` 记录 ↔ 窗口 frame 的换算集中在纯函数（含可见区域钳制）；显示器变化通知（`NSApplication.didChangeScreenParametersNotification`）后对全部卡片重钳制。
- **不抢焦点**：窗口 styleMask 不含 `.activatable`；编辑态经 `canBecomeKey` 窗口子类按需升级（CAP-1 结论四）。

### 新组件：CardManager（Shike/Cards/CardManager.swift）

- 职责：订阅 `NoteRepository.observeActive()` 与 `StickyCardRepository` 观察流，做差量对账——便签出现/消失、卡片记录出现/消失/变化 → 创建/销毁/更新对应 StickyCardController；"钉出位置错开 24 pt"的定位纯函数在此调用；启动时一次性恢复（04 §6.1 插槽）。
- "隐藏所有卡片"临时开关（内存态，不入库）；显示器变化时统一重钳制。
- 由 AppEnvironment 组装注入仓储与偏好；AppDelegate 在启动顺序中 start。

### StickyCardRepository（ShikeKit/ShikeData，已存在骨架按需补齐）

- 补齐观察流 `observeAll()`（卡片记录变化推送全量或差量）；`create(noteId:initial:)`（noteId 唯一冲突返回现记录而非报错）；`update(frame:level:color:fontSize:autoHide:...)` 按列更新；`delete(noteId)`。
- 便签软删除期间卡片记录保留不显示的规则在 CardManager 落实（join 流时过滤）；永久删除级联由外键保证（L2 验证）。

### StatusMenu（Shike/MenuBar/StatusMenu.swift）

- 右键菜单新增"隐藏所有卡片 / 显示所有卡片"（互斥；仅当存在卡片记录时可用）。

### Settings（Shike/Settings/）

- 卡片分页真实化（03 §9）：新卡片默认层级/颜色/字号/自动隐藏/延迟/隐藏后不透明度/空间/全屏，全部写入 `card.default.*`。

### Preferences（Shike/Services/Preferences.swift）

- 新键（集中 `Preferences.Key` 注册，同步 04 §5.5）：`card.default.level`（String，默认 `floating`）、`card.default.color`（String，默认 `yellow`）、`card.default.fontSize`（String，默认 `medium`）、`card.default.autoHide`（Bool，默认 false）、`card.default.hideDelay`（Double，默认 3.0）、`card.default.hiddenOpacity`（Double，默认 0.2）、`card.default.allSpaces`（Bool，默认 true）、`card.default.showOverFullScreen`（Bool，默认 false）。

### ShikeKit / ShikeData

- `StickyCard` 领域类型已存在（阶段 0）；按需补齐仓储接口与观察流；**无 schema 迁移**。
- 纯函数落点：钉出定位（错开 24 pt）、frame 钳制（可见区域、最小尺寸 160×100）放 ShikeData 或 App 层纯类型均可，倾向 App 层 `CardGeometry`（依赖 NSScreen 的部分隔离在 App 层，纯计算部分 L2 直测）。

## 不动的组件

- `note` / `todo` 表与两仓储的现有语义（便签列表、待办、提醒调度零改动）。
- PopoverController / TypingBuffer / HotkeyService / BackupService / ReminderScheduler。
- 纸感视觉批次的面板样式（PaperCard/GroupHeader/问候行/统计条）。
- 04 §7 已登记的移植文件清单（本阶段预计无新增移植；若卡片拖拽参考某开源实现，按 06 §9 登记）。

## 与其他阶段的边界

- 卡片编辑自动保存复用"停止输入 0.5 秒"节奏（03 §10.2），但不改面板侧防抖实现。
- "在面板中显示"复用搜索的定位高亮机制（locateNoteID，1.5 秒），不改其语义。
- 撤销删除后卡片恢复依赖既有删除撤销栈（deletedAt 清空），卡片重建走 CardManager 对账，不进撤销栈本身。
- S3.5 主窗口（v0.4）、S5-01 完成动画、S5-04 外观设置不做。
