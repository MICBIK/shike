# 阶段 1 范围分界

每个组件在阶段 1 交付什么，其余部分留给哪个阶段。表中没有列出的能力，都不在阶段 1。

## 组件分界

| 组件 | 阶段 0 已有 | 阶段 1 交付 | 留给后续 |
|---|---|---|---|
| StatusItemController | 图标、左键开关、右键挂菜单 | 无改动（防刚关又开回归） | 计数显示（S2-08） |
| StatusMenu | 设置…、关于拾刻、退出拾刻 | 打开拾刻、开机自启（勾选项） | 隐藏/显示所有卡片（S3-09） |
| PopoverController | 显示收起、外部点击兜底、防刚关又开、默认尺寸 | Esc 收起（结束编辑→收起）、右下角拖动把手调整尺寸并记住（`panel.size`） | 快捷键呼出联动见 HotkeyService；按键缓冲在 TypingBuffer |
| PanelModel | 模式（默认便签）、观察消费、错误提示条 | 模式决策（`panel.lastMode`/`panel.openMode`）、Tab/⌘1/⌘2 切换、两份草稿、提交动作（便签/待办 create）、删除入栈与 ⌘Z 撤销、新条目高亮标识 | 时间识别提示状态（S2-01）、搜索状态（S2-09）、撤销栈与提示条的标识化改造（见 deferred-work） |
| PanelView | 顶栏分段控件、空状态（图标+标题）、错误提示条 | CaptureTextView 输入区、便签/待办列表（分组与行）、底部撤销提示条、空状态引导句 | 时间识别提示区（S2-01）、搜索按钮与 ⋯ 按钮（S2-09/S3-09） |
| CaptureTextView（新） | — | 输入法安全、⇧↩ 换行、高度自适应（便签 6 行/待办 2 行）、占位文案、焦点管理 | 解析高亮渲染接口（S2-01 接入 ShikeDateParser） |
| TypingBuffer（新） | — | 呼出到输入框就绪间的按键缓存与回放 | — |
| NoteListView / TodoListView / 行视图（新） | — | 置顶/便签分组、待办与已完成（N）分组、行 UI（前 3 行+相对时间；○ 标题+划线灰）、原位编辑（0.5 秒防抖自动保存）、行右键菜单、勾选完成/勾回 | 待办时间显示（S2）、逾期红色（S2-06）、图钉标记（S3-01）、悬停 ⋯ 按钮（S5-02 一并的行增强可后置，右键菜单已覆盖功能） |
| 撤销提示条（新） | — | "已删除「…」 撤销"5 秒、连续删除显示最近一条 | 标识化重试条改造（deferred-work，S1 写路径一并设计） |
| HotkeyService（新） | — | KeyboardShortcuts `togglePanel`，默认 ⌃⌥N 默认开启；设置-快捷键分页真实化（录制控件 + 开关） | 新建便签/待办快捷键（S4-01） |
| LaunchAtLoginService（新） | — | SMAppService 封装：注册/注销/读状态/需要批准 | — |
| 设置窗口 | 骨架与占位、关于页 | 通用分页真实化：呼出时进入、开机自启（含需要批准的引导）；快捷键分页真实化 | 其余分页项（S2-03、S2-04、S3-02～、S4-05～、S5-04、S5-01） |
| Preferences | `backup.keepCount` | `panel.size`、`panel.lastMode`、`panel.openMode`、`panel.draft.note`、`panel.draft.todo` | 其余键按阶段加入 |
| ShikeData | 三仓储、观察流、错误分类 | 无改动（阶段 1 只调用现有方法） | 按 uuid 查找（S2-04）、搜索（S2-09）、最近删除（S4-05） |
| ShikeDateParser | 完整（125 用例） | 无接线（App 不调用） | S2-01 接入输入框 |
| MainMenu | 应用菜单+编辑菜单 | 无改动 | — |
| 依赖 | GRDB 7.11.1 | + KeyboardShortcuts（锁定精确版本） | Sparkle（阶段 4） |

## 阶段 1 新增的目录与文件

`Shike/Panel/`：CaptureTextView.swift、TypingBuffer.swift、PopoverResizeHandle.swift、NoteListView.swift、TodoListView.swift（行视图可并入列表文件，一文件一主要类型）、UndoBar.swift；`Shike/Services/`：HotkeyService.swift、LaunchAtLoginService.swift；`Shike/Support/`：RelativeTimeFormatter.swift。不创建 Cards/、不引入 UpdateService。

## 02 阶段 1 验收清单与能力的对应

| 02 验收条目 | 能力 |
|---|---|
| 1. 快捷键 → 输入 → 回车，3 秒内完成并出现在列表 | CAP-2、CAP-4、CAP-6、CAP-7 |
| 2. 拼音组合中回车只上屏不提交 | CAP-4 |
| 3. 呼出后立即打字一个不丢 | CAP-5 |
| 4. ⇧↩ 换行；列表行显示前 3 行 | CAP-4、CAP-6 |
| 5. 输入一半 Esc 收起，草稿还在 | CAP-1、CAP-5 |
| 6. 删除后撤销，内容和位置不变 | CAP-8 |
| 7. 拖动调整大小，退出重开后保持 | CAP-1 |
| 8. 开机自启，注销再登录自动运行 | CAP-9 |
| 9. 退出重开，条目与完成状态都在 | CAP-4、CAP-6、CAP-7（数据层阶段 0 已保证） |
| 10. 连续自用一周无丢失 | 全部 |

CAP-3、CAP-10 没有独立验收条目：CAP-3 由条目 1 的呼出行为与 L2 测试覆盖，CAP-10 由条目 1 的首条记录体验与 UI 测试覆盖。
