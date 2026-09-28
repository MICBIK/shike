# 阶段 2 · 组件契约（stage-2-components）

> 本文件给出跨故事的组件级契约：签名层面的约定以代码为准，这里约束行为、数据流与可测性。故事规格引用这里的条目。

## 1. 时间识别（capture 集成）

```
PanelModel（待办模式）
  draft.todo 变化（非组合态）
    → recognition = dismissed ? nil : parser.parse(draft, now)   // 注入 now/timeZone
    → recognizedDue: TodoDue?          // parse?.date + hasTime
    → CaptureTextView 高亮 parse?.matchedRanges（强调色背景）
    → 提示条：🕒 <格式化文案>  ✕
```

- **提示文案规则（03 §4）：**带时刻"周五 15:00 提醒"；仅日期"周六（全天）"；已过"今天 09:00（已过）"（红）；相对时长"今天 12:30 提醒（30 分钟后）"。格式化纯函数注入 now/timeZone（复用/扩展 RelativeTimeFormatter 的口径：今年以内不显示年份）。
- **✕ 取消：**`recognitionDismissed = true`，提示变灰"不识别时间"、高亮清除；草稿清空（提交成功、模式切换清空、手动删空）时复位 false。
- **便签模式：**识别、高亮、提示全部关闭（不走 parser）。
- **性能（NFR21）：**每次文本变化同步解析一次；解析为纯字符串运算，无 IO；不解析组合态。
- **草稿恢复：**呼出恢复草稿后立即解析一次（高亮与提示随之出现）。

## 2. 提交与标题清理

- 带识别：`title = TitleCleaner.clean(text, ranges: matchedRanges)`，`due = recognizedDue`。
- 取消识别：`title = TitleCleaner.stripWhitespaceAndPunctuation(text)`，`due = nil`。
- 清理后为空 → 用原文去首尾空白（05 §7 第 6 步）。
- 提交失败：输入、识别状态全部保留（阶段 1 语义不变）。
- 05 §7 修订：第 3、4 步迭代执行直到不再变化（Issue #2）；docs/05 §7 与 §9.13 同提交更新。

## 3. 提醒计划与调度

```
ReminderPlan.plan(todos: [Todo], now: Date, timeZone: TimeZone, allDayMinutes: Int, limit: Int = 50)
  → [PlannedReminder]   // uuid, fireDate, title, hasTime
```

- 候选：`deletedAt == nil && completedAt == nil && due != nil`。
- fireDate：`snoozedUntil` 优先（不过期照样排）；否则 `hasTime ? dueAt : 当天00:00 + allDayMinutes`（按 timeZone）。
- 过滤 `fireDate <= now`；升序取前 `limit`。
- **纯函数、L1 全覆盖**：全天跨天、snooze 早于现在、恰为 now、恰好第 50/51 条等边界。

```
ReminderScheduler.reconcile()
  plan = ReminderPlan.plan(...)
  pending = scheduler.pendingRequests()                    // 标识集合
  for id in pending where plan 不含或 fireDate 变化 → remove(id)
  for r in plan where pending 不含 → add(r)                // 内容含 uuid 用户信息
```

- 通知内容：标题=待办标题；正文=时间文案（"今天 15:00"/"全天 · 今天"，经 §1 的格式化规则）；声音默认；类别=REMINDER（动作：完成 / 稍后提醒）。
- 触发：启动后、待办流每次变化（0.5s 合并）、`NSCalendarDayChanged`、`NSWorkspace.didWakeNotification`、`reminder.allDayMinutes`/`reminder.snoozeMinutes` 偏好变化。
- 幂等（NFR20）：相同输入重复 reconcile 不产生重复通知。
- **动作处理：**"完成"→ `setCompleted(uuid, true)`；"稍后提醒"→ `snooze(until: now + reminder.snoozeMinutes 分钟)`；snooze 后数据流触发 reconcile 重排；点击本体 → App 回调 `openPanel(todoMode: locate: uuid, highlight: 1.5s)`。
- App 未运行时：提前排期的系统本地通知照常送达；动作回调随启动走同一代理入口（冷启动时先等数据库就绪再执行动作）。

## 4. 通知权限

- 请求时机：PanelModel 待办提交且 `due != nil` 时，经闭包请求一次（系统只弹一次，后续调用为查询）。
- 状态：`notDetermined / granted / denied`；denied → PanelModel 置位 `notificationDenied` → 待办模式顶部黄色提示条"通知已关闭，到点不会提醒" + "打开系统设置"（`NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)`）。
- 设置-提醒分页显示当前状态 + 打开系统设置。
- L2：协议注入，零真实权限调用。

## 5. 待办分组与时间显示

```
groupTodos(todos, now, timeZone) -> (overdue, today, later, noDate, completed)
```

- 界定（本地时区当天 [00:00, 24:00)）：逾期=due < 今天0点（未完成）；今天=今天内；以后≥明天；无日期=due==nil；已完成=completedAt != nil（进组排序按 completedAt 降序）。
- 组内排序：逾期/今天/以后按 due 升序（snoozedUntil 不影响分组显示）；无日期按 createdAt 降序（保持阶段 1 的"新条目在顶部"）。
- 纯函数、注入 now/timeZone；跨天/唤醒由 PanelModel 重新求值（订阅 NSCalendarDayChanged + didWake）。
- 行尾时间文案（03 §6）：今天 15:00 / 明天 / 周五 15:00 / 9月30日 / 2027年3月5日 15:00；全天不带时刻；逾期红。格式化纯函数与 §1 共用。

## 6. 菜单栏计数与角标

- 计数口径：`overdueAndToday` = 逾期未完成 + 今天未完成；`allIncomplete` = 全部未完成（不含无日期? 含——"全部未完成"即所有未完成待办）；`none` 不显示。
- 数据源：同一 observeActive 待办流 + now 求值；跨天/唤醒/数据变化立即更新；数字 0 不显示。
- 位置：状态项图标右侧文本；待办模式分段控件"待办"文字旁数字角标。
- 计数求值为纯函数（注入 now/timeZone），L2 覆盖三种口径。

## 7. 搜索

- 状态：`isSearching`、`query`；进入：⌘F（面板键监听）或顶栏放大镜按钮；搜索框替换 CaptureTextView 位置（同一容器切换）。
- 匹配：未删除便签的 content、未删除待办的 title（含已完成）；case-insensitive `contains`；0.2 秒防抖后执行；结果 = 便签组（按 updatedAt 降序）+ 待办组（按 updatedAt 降序）。
- 渲染：复用列表行；匹配子串高亮（强调色背景，UTF-16 区间）。
- 点击：退出搜索 → 切到对应模式 → ScrollViewReader 定位该条 → 高亮 1.5 秒。
- 关闭：Esc（顺序：结束编辑 → 退出搜索 → 收起面板）；"没有找到"××"" + 清除按钮（03 §14）。
- 注意：搜索态输入不进草稿、不触发识别、TypingBuffer 呼出即打字在搜索态关闭（搜索框获得焦点）。

## 8. 设置-提醒分页

| 项 | 控件 | 偏好键 |
|---|---|---|
| 全天待办提醒时间 | 时:分选择（0:00–23:59） | `reminder.allDayMinutes` |
| 稍后提醒时长 | 5 / 10 / 15 / 30 / 60 分钟 | `reminder.snoozeMinutes` |
| 通知权限状态 + 打开系统设置 | 状态文本 + 按钮 | —（读系统） |

通用分页新增"菜单栏计数"（不显示 / 逾期+今天 / 全部未完成）。

## 9. 文案键（新增，全部 extractionState: manual）

capture.recognition.remind（"🕒 %@ 提醒"）、capture.recognition.allDay（"%@（全天）"）、capture.recognition.past（"%@（已过）"）、capture.recognition.relative（"%@ 提醒（%@后）"）、capture.recognition.dismissed（"不识别时间"）、capture.placeholder.todo（改"要做什么？比如：周五下午三点交报告"）、todo.menu.setTime（"设置时间…"）、todo.time.today/tomorrow 等时间文案经格式化函数、search.placeholder、search.empty（"没有找到"%@""）、search.clear、banner.notificationDenied（"通知已关闭，到点不会提醒"）、banner.openSystemSettings（"打开系统设置"）、settings.reminder.allDayTime、settings.reminder.snooze（"稍后提醒时长"）、settings.reminder.snoozeMinutes（"%lld 分钟"）、settings.reminder.permission、settings.general.menuBarCounter（"菜单栏计数"）及三选项、menu.counter 等按需拆分；完成/稍后提醒按钮文案给通知类别用（"完成""稍后提醒"）。

## 10. 测试映射（每项至少一条 L1/L2）

| 契约条目 | 测试 |
|---|---|
| §1 识别状态机（识别/取消/清空复位/便签不识别/组合态不解析） | CaptureRecognitionTests（L2） |
| §2 清理（含 Issue #2 迭代、空回退、取消识别入口） | TitleCleanerTests（L1，docs/05 §9.13 + 新用例） |
| §3 ReminderPlan 边界 + reconcile 幂等/增删改 | ReminderPlanTests（L1）、ReminderSchedulerTests（L2 内存替身） |
| §4 权限状态→提示条 | NotificationPermissionTests（L2） |
| §5 分组界定与排序、跨天重排 | TodoGroupingTests（L2 纯函数） |
| §6 三种口径计数、0 隐藏 | MenuBarCounterTests（L2） |
| §7 搜索防抖、匹配高亮区间、导航 | SearchTests（L2） |
| 时间显示格式 | TimeDisplayTests（L2，扩展现有 RelativeTimeFormatter 测试） |
