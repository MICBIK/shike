# 阶段 3.5 主窗口 · 故事拆解（Epic 5）

来源：docs/02 阶段 3.5（v0.4）；产品分工 ADR-023；交互设计 docs/03 §16。
状态标记：规划完成（2026-09-29 夜），S3.5-01/02 本夜实现，其余随后续夜间推进。

### Story 5.1: 主窗口骨架（S3.5-01）

作为想完整浏览内容的人，
我能从菜单栏右键或设置打开一个可调大小的主窗口，
以便在大空间里管理便签和待办。

**依据：**docs/02 S3.5-01；docs/03 §16.1；ADR-023。

**验收标准：**

1. 菜单栏右键菜单与设置-通用页均有"打开主窗口"；重复打开前置聚焦既有窗口，不开第二扇。
2. 窗口可调整大小；尺寸与位置经 frameAutosave 记住，下次打开恢复。
3. 关闭窗口拾刻继续驻留菜单栏（无 Dock 图标语义不变）；重开后内容与状态都在。
4. 窗口内容走既有仓储观察流（数据目录、库实例与面板同源）。

### Story 5.2: 左栏三入口（S3.5-02）

作为使用主窗口的人，
我在左栏切换便签 / 待办 / 回收站三视图，
以便按内容类型找到要的东西。

**依据：**docs/02 S3.5-02；docs/03 §16.2。

**验收标准：**

1. 左栏三项：便签 / 待办 / 回收站；选中态高亮。
2. 选中态记忆（@AppStorage），重启主窗口回到上次入口。
3. 不出现项目/标签系统入口（边界不破）。
4. 右侧内容区随入口切换；未实现的故事显示诚实的占位说明（不冒充完成）。

### Story 5.3: 便签视图（S3.5-03）

依据 docs/03 §16.3。验收：全量便签置顶分组在前列；搜索即时过滤；单击原位编辑（防抖保存、清空=删除入撤销栈与面板同语义）；右键菜单与面板便签行一致；两侧增删改即时互见。

### Story 5.4: 待办视图（S3.5-04）

依据 docs/03 §16.4。验收：逾期/今天/以后/无日期/已完成分组与面板同规则复用；搜索过滤；勾选完成/勾回；带时间待办完成取消通知；右键菜单与面板一致。

### Story 5.5: 回收站（S3.5-05）

依据 docs/03 §16.5。验收：便签/待办两组列出（需 ShikeData 新增 observeDeleted 观察流，含删除时间）；恢复回到删除前状态（待办回面板对应分组）；单条永久删除与清空均需确认且不可恢复，反馈条如实提示；为 S4-05 保留期自动清除预留接口。

### Story 5.6: 导出（S3.5-06）

依据 docs/03 §16.6。验收：导出 Markdown（便签/待办分节）与 JSON（结构化全量）；NSSavePanel 选位置；成功后反馈显示路径；导出内容与面板所见一致（以同一观察流快照为源）。本故事提前实现 S4-06，阶段 4 只余备份设置。

## 实现顺序与依赖

5.1 → 5.2 →（5.3、5.4 可并行）→ 5.5 → 5.6。
5.5 依赖 ShikeData 新增 `observeDeleted()`（note/todo 两仓储）；5.6 无新依赖。
验收门槛：docs/02 阶段 3.5 验收清单 5 项全过 + 打磨轮次记录。

## 执行计划（2026-10-01 夜，4 子代理并行）

**分工与文件所有权（互不重叠）：**

| 代理 | 范围 | 新文件 |
|---|---|---|
| A 数据层 | ShikeData：NoteRepository.observeDeleted / TodoRepository.observeDeleted（软删除行，按 deletedAt 降序）/ TrashRepository（restore/permanentlyDelete/emptyTrash 组合两表事务）+ 单测 | Packages/ShikeKit/Sources/ShikeData/Repositories/TrashRepository.swift + ShikeKitTests/TrashRepositoryTests.swift |
| B 便签视图 | MainNotesModel（@Observable）+ MainNotesView（复用 NoteListItem 流、panelModel.saveNoteContent 同语义、分组置顶/全部）+ 单测 | Shike/MainWindow/MainNotesView.swift + ShikeTests/MainNotesModelTests.swift |
| C 待办视图 | MainTodosModel + MainTodosView（复用待办分组器与 Todo 流、panelModel.completeTodo 同语义、五分组）+ 单测 | Shike/MainWindow/MainTodosView.swift + ShikeTests/MainTodosModelTests.swift |
| D 回收站+导出 | TrashModel（闭包注入模式，测试 mock 闭包）+ TrashView + ExportService（纯函数 [Note]+[Todo]→Markdown/JSON）+ 单测 | Shike/MainWindow/TrashView.swift + Shike/Services/ExportService.swift + ShikeTests/{TrashModelTests,ExportServiceTests}.swift |

**接口约定（主线程预定义，代理不得更改）：**
- 数据层（A）：`NoteRepository.observeDeleted() -> AsyncThrowingStream<[Note], any Error>`、`TodoRepository.observeDeleted() -> AsyncThrowingStream<[Todo], any Error>`（deletedAt 非空、按 deletedAt 降序）、`TrashRepository(database:)`：observeNotes/observeTodos/restoreNote/restoreTodo/permanentlyDeleteNote/permanentlyDeleteTodo/emptyTrash（emptyTrash 单事务清两表）。
- 视图模型（B/C/D）：闭包注入模式（同 PanelModel Actions 风格），测试传 mock 闭包；集成由主线程接真实仓储。
- **本地化**：主线程预插全部新键（见下），代理直接用既有键 + 新键，**不得改 xcstrings**。
- **禁碰**：Localizable.xcstrings、MainRootView（MainWindowController.swift）、AppDelegate、AppEnvironment、Panel/* 现有文件、docs。集成（MainRootView 接三视图、环境接线）由主线程统一做。

**预插键（主线程，2026-10-01）：**
main.notes.search=搜索便签；main.notes.group.all=全部；main.notes.empty=还没有便签，从菜单栏面板记一条吧；main.todos.search=搜索待办；main.todos.empty=没有待办；main.trash.notes=便签；main.trash.todos=待办；main.trash.empty=回收站是空的；main.trash.restore=恢复；main.trash.delete=永久删除；main.trash.emptyAll=清空回收站；main.trash.confirmDelete=永久删除后无法恢复，确定吗？；main.trash.confirmEmpty=清空回收站后无法恢复，确定吗？；main.export.markdown=导出为 Markdown…；main.export.json=导出为 JSON…；main.export.done=已导出；main.export.failed=导出失败。
复用键：list.group.pinned/overdue/today/later/noDate/completed（分组标题）、search.placeholder（面板搜索）、panel.empty.note/todo.guide、list.menu.*（行右键菜单）、card.menu.unpin。

**审查审计（完成后 15 轮）**：5 批 × 3 视角（正确性与并发 / 测试覆盖与边界 / 规范与本地化与 UI 一致性），每轮必须产出真问题并修复后才进下一轮；全部轮次记录台账。
