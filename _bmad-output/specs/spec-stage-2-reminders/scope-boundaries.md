# 阶段 2 · 范围与边界（scope-boundaries）

## 修改的组件

### CaptureTextView（Shike/Panel/CaptureTextView.swift，阶段 1 移植文件）

- 新增**时间高亮**：待办模式且识别未被取消时，把 `matchedRanges`（UTF-16）映射到 NSTextStorage 加强调色背景；组合态（hasMarkedText）不刷新属性；取消识别时清除高亮。
- 新增**提示条状态输出**：把"当前识别结果 / 已取消"经闭包或绑定上报给 PanelModel（识别本身在 PanelModel 或专用小模型里做，文本视图只管显示）。
- 占位文案：待办模式改为「要做什么？比如：周五下午三点交报告」（03 §4）。
- 高度规则不变（待办最多 2 行）；⇧↩ 在待办模式仍无作用；输入法安全规则不变。

### PanelModel（Shike/Panel/PanelModel.swift）

- 新增**时间识别状态**：`recognizedDue: TodoDue?`、`recognitionDismissed: Bool`（✕ 后置位，draft 清空时复位）；每次待办草稿变化重新解析（注入 now/timeZone）。
- **提交路径**：待办提交改走"标题清理 + due"：`TitleCleaner.clean` → `TodoRepository.create(title:due:)`；识别被取消时 due 为 nil、标题只做空白标点清理（05 §7 第 4 步语义，经同一清理函数的关闭开关或独立入口）。
- 新增**搜索状态**：`isSearching`、`searchQuery`、搜索结果（0.2 秒防抖）；Esc 顺序插入"退出搜索"层。
- 新增**待办分组**：observeActive 的消费从"待办/已完成"两组改为五组（逾期/今天/以后/无日期/已完成）；分组与排序为纯函数（注入 now/timeZone）；跨天通知与唤醒时重新求值。
- 新增**待办右键菜单动作**：设置时间…（弹层回调 `setDue`）。

### TodoListView（Shike/Panel/TodoListView.swift）

- 分组标题与行样式更新：行尾时间文案（03 §6 格式），逾期红字；"设置时间…"菜单项；时间弹层（DatePicker + 包含时刻开关 + 时刻 + 快捷按钮）。
- 搜索结果复用列表行渲染（便签组复用 NoteList 行样式）。

### 新组件：ReminderScheduler（Shike/Services/ReminderScheduler.swift）

- 职责：按 04 §6.7 对账——从 PanelModel/仓储观察流取活跃待办，调 `ReminderPlan.plan`（ShikeData 纯函数）得前 50 条计划，与 UNUserNotificationCenter 已排通知（pendingNotificationRequests）对比：删除多余/变化的（uuid 为标识），补缺少的；写入时带类别与用户信息（uuid）。
- 对账触发：启动、待办数据变化（0.5 秒合并）、`NSCalendarDayChanged`、`NSWorkspace.didWakeNotification`、`reminder.allDayMinutes`/`reminder.snoozeMinutes` 变化。
- UNUserNotificationCenter 经协议 `NotificationScheduling` 注入（pending/add/remove），L2 用内存替身。

### 新组件：NotificationCoordinator（Shike/Services/NotificationCoordinator.swift 或并入 Scheduler）

- 启动时注册通知类别（完成 / 稍后提醒），设置代理：前台展示横幅；"完成"→仓储 setCompleted(true)；"稍后提醒"→仓储 snooze(until: now + reminder.snoozeMinutes)；点击本体→回调 App 打开面板、切待办、定位高亮 1.5 秒。
- 权限：首次创建带时间待办时请求（PanelModel 提交钩子经闭包触发）；授权状态变化回报（提示条、设置页显示）。

### StatusItemController（Shike/MenuBar/StatusMenu.swift / StatusItemController.swift）

- 图标右侧计数文本（`menuBar.counter` 口径：逾期+今天未完成 / 全部未完成 / 不显示；0 不显示）；数据源与列表同源（observeActive 待办流 + 当前时刻求值），跨天/唤醒重新求值。
- 待办模式分段按钮数字角标（PanelView 顶栏）。

### Settings（Shike/Settings/）

- 提醒分页真实化：全天待办提醒时间（时:分选择）、稍后提醒时长（5/10/15/30/60）、通知权限状态 + 打开系统设置。
- 通用分页新增：菜单栏计数（不显示 / 逾期+今天 / 全部未完成）。

### Preferences（Shike/Services/Preferences.swift）

- 新键：`menuBar.counter`（String，默认 `overdueAndToday`）、`reminder.allDayMinutes`（Int，默认 540）、`reminder.snoozeMinutes`（Int，默认 10）；`Preferences.Key` 集中注册，默认值同处；同步 04 §5.5。

### ShikeKit / ShikeData

- `ReminderPlan`（新，ShikeData，纯函数）：输入活跃待办、now、时区、全天提醒分钟 → [(uuid, fireDate, dueHasTime, title…)]，前 50。
- `TitleCleaner`：按修订后的 05 §7（第 3、4 步迭代到不动点）；提供"仅空白与标点清理"入口供取消识别的提交复用。
- docs/05 同步修订 §7 规则文本与 §9.13 用例（同一次提交，Issue #2 关闭）。

## 不动的组件

- NoteRepository / Note 领域类型（搜索只读）。
- 数据库 schema 与迁移（todo 列已就位，阶段 0 建表）。
- PopoverController 的开关语义、尺寸把手；TypingBuffer 的缓冲回放；LaunchAtLoginService；BackupService。
- 04 §7 已登记的移植文件清单（本阶段无新增移植；提醒相关为原创实现，reminders-menubar 的对应代码基于 EventKit，不适用）。

## 与其他阶段的边界

- 通知点击定位高亮 1.5 秒复用阶段 1 的 recentlyCreated 高亮机制，但不改其语义。
- ⌘F 搜索的结果点击定位依赖"滚动定位"能力：列表用 ScrollViewReader 实现，定位高亮同样 1.5 秒。
- S5-02 的键盘导航（↑↓ 选择、⌘⌫ 删除）不做；S5-03 转为便签/待办不做。
