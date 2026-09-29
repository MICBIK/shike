# 阶段 1 + 阶段 2 自验收记录（2026-09-29 夜）

按 docs/02 两份验收清单执行。产品负责人 2026-09-29 授权："你直接去验收吧，剩下这几个点，反正你也能看见"。
本记录区分三类结论：**✅ 已自查通过**（测试/真机只读证据）、**👤 待负责人复核**（需真人操作/真实输入法/通知链路，步骤见晨报）、**⏳ 进行中**（时间门槛项）。
基线：stage-2/reminders @ 6c0a3bc，本地 App 测试 141 绿 + ShikeKit 67 绿（包未改动），CI 见 PR。

## 阶段 1 · 随手记（v0.1）

| # | 清单项 | 结论 | 证据 |
|---|---|---|---|
| 1 | 快捷键呼出→输入→回车 3 秒内列表出现 | 👤 | 呼出链路今日上午负责人已实测可用（tapID 安装）；3 秒内提交/刷新由 CaptureInputTests（提交即入观察流）覆盖逻辑层。⚠️ 今晚重建后需重新授权辅助功能（见晨报步骤） |
| 2 | 拼音组合中回车只上屏不提交 | 👤 | 组合态保护在 CaptureNSTextView（hasMarkedText 不提交/不触碰属性），Esc 组合态交还输入法；需真实输入法复核手感 |
| 3 | 呼出后连续打字不丢字 | 👤 | TypingBufferTests：呼出即缓冲、面板就绪回放全绿；真机节奏感需负责人 |
| 4 | ⇧↩ 换行；列表显示前 3 行 | ✅+👤 | CaptureTextView allowsLineBreaks 分模式；NoteRow lineLimit(3) + 测试；真机按键复核 |
| 5 | 输入一半 Esc 收起，草稿保留 | ✅+👤 | PanelBehaviorTests（草稿分模式保留、Esc 收起）；真机复核 |
| 6 | 删除后点撤销/⌘Z 恢复，内容位置不变 | ✅ | DeleteUndoTests 5 例全绿：入栈、逆序撤销、双视角反馈、编辑清空入栈、计时消失 |
| 7 | 拖动调大小并记住（不超屏） | ✅+👤 | PopoverSizingTests：钳制+持久化；CI 小屏钳制断言；真机拖拽复核 |
| 8 | 开机自启，注销重登自动运行 | ✅+👤 | LaunchAtLoginTests：SMAppService 状态以系统为准；注销重登需负责人（本轮未做，避免杀会话） |
| 9 | 退出重开，便签/待办/完成状态都在 | ✅ | 真机只读核查：shike.sqlite 完整（WAL 在跑），昨日/今日备份 integrity_check 均 ok；现存便签 2 条与负责人今日实测数据一致。重启验证待负责人顺手确认 |
| 10 | 连续自用一周不丢内容 | ⏳ | 负责人 09-28 起自用中；09-28/09-29 两日备份连续落盘（00:00 准点）；到期日 10-05 复核 |

## 阶段 2 · 到点提醒（v0.2）

| # | 清单项 | 结论 | 证据 |
|---|---|---|---|
| 1 | "周五下午三点交报告"：高亮+提示+列表"交报告 · 周五 15:00" | ✅+👤 | CaptureRecognitionTests（识别区间/高亮范围）+ TodoSubmissionTests（标题清理、due 落库）全绿；负责人上午实测过一次（反馈高亮不明显→本夜已加强为青绿药丸，待复核） |
| 2 | 2 分钟后到点收到通知；"稍后提醒"10 分钟后再响 | ✅+👤 | ReminderSchedulerTests（到点排程、snooze 时长档位）+ NotificationCoordinatorTests 全绿；真机通知链路需负责人 |
| 3 | 通知上点"完成"→待办完成 | ✅+👤 | NotificationCoordinatorTests：complete 动作→completeTodo(uuid)；真机点击复核 |
| 4 | 退出拾刻后通知照常；点"完成"拉起并完成 | 👤 | UNUserNotificationCenter 系统投递（不依赖进程存活）为平台行为；动作路由有测试；整链路需真机 |
| 5 | "有两点需要注意"不高亮；"两点开会"高亮；× 后不再识别 | ✅ | ShikeKit 解析 125+ 用例（A1–A4 歧义规则）+ CaptureRecognitionTests ×取消；全绿 |
| 6 | 系统设置关通知→面板提示条+跳转按钮 | ✅+👤 | NotificationPermissionTests：denied→提示条状态；真机跳转复核 |
| 7 | 过午夜"今天"→"逾期" | ✅ | TodoGroupingTests 跨午夜用例 + PanelModel.handleTimeContextChanged（NSCalendarDayChanged/wake）真机已注册 |
| 8 | 菜单栏数字=逾期+今天，完成即减 | ✅+👤 | MenuBarCounterTests 三口径全绿；角标同口径（todoBadgeCount）；真机瞄一眼 |
| 9 | 搜索"报告"同时命中便签+待办 | ✅+👤 | SearchTests 双组结果+定位；真机复核 |

## 真机只读核查（2026-09-29 09:20）

- 进程 99513 运行中（纸感批次构建 6c0a3bc）；菜单栏状态项在（System Events 计 3 个 menu bar item）。
- 真实数据目录：WAL 正常；`Backups/shike-2026-09-28.sqlite`、`shike-2026-09-29.sqlite` 双备份 integrity_check = ok（跨天备份 00:00 准点触发，S1-13 真机证据）。
- 备份快照：现存便签 2、待办 0，与负责人自用状态一致。
- 应用日志（5 分钟窗口）：无应用层错误；仅系统 AppIntents/linkd 注册噪音（LSUIElement 已知良性）。
- ⚠️ 已知状态：本夜重建使辅助功能授权失效（授权绑定构建 cdhash，ADR-021）→ ⌥N 在重新授权前不可用；重试循环会在授权恢复后自动装回 tap，无需重启。

## 结论

逻辑层与数据安全底座全部有测试证据；需要真人感官/系统链路的 11 项汇总到晨报清单（预计 10 分钟）。两项时间门槛：自用一周（10-05）、注销重登（负责人方便时）。建议按现状态合并 main 并打 v0.1.0 / v0.2.0（负责人已授权"按推荐处理"），真机复核如有问题以修复+补提交处理。
