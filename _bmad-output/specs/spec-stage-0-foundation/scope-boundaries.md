# 阶段 0 范围分界

每个组件在阶段 0 交付什么，其余部分留给哪个阶段。表中没有列出的能力，都不在阶段 0。

## 组件分界

| 组件 | 阶段 0 交付 | 留给后续 |
|---|---|---|
| StatusItemController | 模板图标 `note.text`；左键开关面板；右键时临时挂上菜单并弹出 | 计数显示（S2-08） |
| StatusMenu | 设置… ⌘,、关于拾刻、退出拾刻 ⌘Q | 打开拾刻（S1-09）、开机自启（S1-08）、隐藏/显示所有卡片（S3-09） |
| PopoverController | 显示与收起；`.transient`，`animates = false`；外部点击兜底；防刚关又开；激活 App 并让面板成为关键窗口；默认尺寸 360×520，限制在可见区域内 | Esc（S1-01）；拖动调整尺寸并记住（S1-01）；按键缓冲与聚焦输入框（S1-04）；快捷键开关（S1-02） |
| PanelView / PanelModel | 「便签｜待办」分段控件（默认便签，不记忆）；空状态（图标 + 标题）；订阅观察；错误提示条 | 快速输入框（S1-04）；列表与编辑（S1-05、S1-06）；模式快捷键与记忆（S1-03）；空状态引导句（S1-10）；撤销提示条（S1-07）；搜索（S2-09）；⋯ 菜单；待办数字角标（S2-08） |
| 设置窗口 | 单实例窗口；六个分页的骨架与占位；完整的关于页（包括法律声明，以及能离线查看 LICENSE 的窗口） | 各分页的具体设置项（03 §9 中对应的 S 编号）；关于页的检查更新、反馈、重新打开引导（S4-02、S4-08、S4-09） |
| MainMenu | 应用菜单（设置… ⌘,、退出 ⌘Q）；编辑菜单（撤销、重做、剪切、复制、粘贴、全选） | — |
| Preferences | 类型化封装、键的集中定义、默认值注册；只有一个键 `backup.keepCount` | 其余键在各自阶段按 04 §5.5 加入 |
| LaunchOptions | `-ShikeSimulateDatabaseOpenFailure`、`-ShikeSimulateWriteFailure`、`-ShikeDataDirectory` | 按需增加，并登记到 06 §11 |
| BackupService | 启动后和跨天时的每日备份；保留 7 份；失败只写日志 | 在设置中显示上次失败、立即备份、修改保留份数（S4-07） |
| ShikeData 仓储 | 04 §4.2 中列出的全部方法（见 data-layer.md） | 按 uuid 查找（S2-04）、搜索查询（S2-09）、最近删除列表（S4-05） |
| ShikeData 迁移 | v1；迁移前备份机制（阶段 0 用测试专用迁移验证） | v2 及以后的迁移，按 conventions.md 的迁移规则加入 |
| ShikeData 观察 | 未删除的便签（附带是否已钉）、未删除的待办、可见的卡片（附带便签） | 菜单栏计数（S2-08） |
| ShikeData 领域逻辑 | 无 | 待办分组（S2-06）、提醒计划（S2-05）、搜索转义（S2-09）、最近删除自动清理（S4-05） |
| ShikeDateParser | 05 的全部规则与用例，包括标题清理 | 规则变更随 05 一起修改 |
| CI | `checks`、`package-tests`、`app` 三个作业；分支保护 | 发布流水线（S4-03） |
| 文档 | NOTICE、README、04/06/07 写回，扩展指南（CAP-13） | 各阶段各自同步 |
| 未排期 | — | 单实例（Issue #1）；05 §7 标题清理顺序（Issue #2，在 S2-02 之前决定）；第三方许可证随 App 打包（项目全部完工时再定） |

## 阶段 0 创建的目录

`Shike/App`、`Shike/MenuBar`、`Shike/Panel`、`Shike/Settings`、`Shike/Services`、`Shike/Support`、`Shike/Resources`、`ShikeTests`、`Packages/ShikeKit`（含两个库和两个测试目标）、`.github/workflows`；如果检查脚本不内联在工作流中，再加 `scripts/`。`Shike/Cards` 在阶段 3 创建，UpdateService 在阶段 4 创建，不预先建空目录。

## 验收清单与能力的对应

| 02 阶段 0 验收条目 | 能力 |
|---|---|
| 1. main 分支的 CI 通过 | CAP-12 |
| 2. `swift test --package-path Packages/ShikeKit` 全部通过 | CAP-3、CAP-4、CAP-5、CAP-6、CAP-7 |
| 3. 生成工程后运行：有菜单栏图标，Dock 无图标 | CAP-2、CAP-8 |
| 4. 左键弹出面板，有模式切换和空状态；点击外部收起 | CAP-8 |
| 5. 右键菜单；"设置…"打开的窗口在最前面；"退出拾刻"能退出 | CAP-9、CAP-10 |
| 6. 模拟数据库打不开：提示加三个按钮 | CAP-6 |
| 7. 运行一次后 `Backups/` 中有当天的备份 | CAP-7 |

CAP-1、CAP-11、CAP-13、CAP-14 没有对应的验收条目，在评审和收尾时，通过 CI 检查、L1/L2 测试和文档核对来确认。
