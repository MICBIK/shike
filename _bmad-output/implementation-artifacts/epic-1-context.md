# Epic 1 Context: 阶段 0 · 地基

<!-- Compiled from planning artifacts. Edit freely. Regenerate with compile-epic-context if planning docs change. -->

## Goal

交付拾刻阶段 0 地基：一个只驻留菜单栏、可在 Mac 上运行的 macOS 应用骨架（菜单栏面板、设置/关于、中文日期解析器、v1 数据层），以及"不丢数据"的全部安全机制（写入失败必报错、打不开不碰原文件、每日备份与迁移前备份）；同时交付由 CI 裁决的分层工程与文档交接，阶段 1 拿到仓储、AppEnvironment 等契约即可开工。

## Stories

- Story 1.1: 搭建工程骨架
- Story 1.2: 建立 CI 流水线
- Story 1.3: 数据库的打开与 v1 表结构
- Story 1.4: 便签的保存与观察
- Story 1.5: 待办的保存与观察
- Story 1.6: 桌面卡片的数据
- Story 1.7: 组装点与偏好设置
- Story 1.8: 数据库打不开时的提示
- Story 1.9: 菜单栏图标与面板
- Story 1.10: 面板的数据与错误提示
- Story 1.11: 设置窗口、右键菜单与主菜单
- Story 1.12: 关于页与许可证
- Story 1.13: 每日自动备份
- Story 1.14: 迁移前备份
- Story 1.15: 识别中文日期与时刻
- Story 1.16: 排除误识别、高亮与标题清理
- Story 1.17: 架构交接

## Requirements & Constraints

- 工程合规：新克隆仓库 `xcodegen generate` + 构建后 `git status` 干净；含 GPL-3.0 原文 LICENSE、NOTICE.md（登记 GRDB、移植文件与 demo 基线提交）、实测过的 README、.gitignore；所有源文件带 GPL 文件头，移植文件另带来源与修改说明。
- App 属性：Bundle ID `io.github.micbik.shike`，版本 0.0.0（1），最低 macOS 15，显示名"拾刻"，Dock 无图标；零新增编译警告，"警告即错误"只在 CI 开启。
- 解析器：识别中文日期/时刻/相对时长并顺延、排除歧义，输出 `date`、`hasTime` 与按位置排序互不重叠的 UTF-16 `matchedRanges`，未识别返回 nil；结果与系统区域/日历/一周第一天无关；TitleCleaner 五步清理标题；规格全部用例有同编号测试，守护测试保证规格与测试数据同步，不同步即失败。
- 数据层 v1：`note`/`todo`/`stickyCard` 三表及约束索引；三仓储支持各自完整的写操作（含软删/恢复/永久删，卡片钉出幂等、随便签隐藏重现与级联删除）；三类异步观察流先推当前值、提交后推新值；操作不存在的记录抛 `notFound`；错误一律分类抛出。
- 数据安全：写入失败必抛分类错误，无"失败却成功"路径；打不开时提示三按钮，不降级内存库/空库、不改原文件；每日备份按文件名日期保留 7 份；迁移前先备份，失败则不迁移。
- 外壳：左键开关面板、点外部收起；面板含「便签｜待办」切换、空状态与条数占位；右键菜单、隐藏主菜单（⌘,、⌘Q、编辑菜单）；设置窗口六分页（前五占位）；关于页完整、离线看许可证。
- CI：三个作业（checks/package-tests/app）覆盖推送与 PR；main 分支保护要求三项全过、仅 PR 合并；收尾把实测契约写回架构文档、补 ADR，并使各规范文档与实测一致。
- 横切：不丢数据优先——禁 `try?` 吞错、禁 `eraseDatabaseOnSchemaChange`、迁移只追加；无遥测无网络，日志不记用户内容；文案全部来自字符串目录（zh-Hans）；测试确定性：T0=2026-09-23 12:00 Asia/Shanghai、时钟注入、优先 L1。

## Technical Decisions

- 工具链：Swift 6 严格并发，Xcode 26+（CI macos-26），`swift-tools-version: 6.2`；XcodeGen 2.46.0 从 `project.yml` 生成；ad-hoc 签名，无 Hardened Runtime/沙盒；根目录 LICENSE 作为资源打包。
- 警告即错误经 `SHIKE_WARNINGS_AS_ERRORS` 控制，只在 CI 打开；绝不在 xcodebuild 命令行传 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`（与 GRDB 冲突，实测构建失败）。
- 生命周期：`main.swift` + `AppDelegate`（不用 SwiftUI App/Scene），`LSUIElement=YES`；窗口 AppKit、内容 SwiftUI；界面类型标 `@MainActor`。
- 模块边界：App 只依赖 ShikeData、ShikeDateParser（互不依赖）；ShikeKit 无 AppKit/SwiftUI；GRDB `exact: "7.11.1"`、`Package.resolved` 入库；ShikeData 用 `internal import GRDB`，公开 API 无 GRDB 类型，App 不 import GRDB。
- ShikeData：磁盘 `DatabasePool`（WAL）、内存 `DatabaseQueue`；时钟经 `transactionClock` 注入；UUID 编码必须是静态函数 `databaseUUIDEncodingStrategy(for:)`（静态属性写法被静默忽略）；`hasBeenSuperseded` 拒绝新版本库；公开 `Sendable` 值类型与内部 Record 分离；仓储为 `Sendable` struct，观察为去重 `AsyncThrowingStream`；迁移器可注入测试迁移；uuid 存 36 位小写文本，updatedAt 只在内容类变化时更新。
- 解析器：`struct`，正则为 `static let` 的 `NSRegularExpression`（Swift Regex 非 Sendable），日期回读校验；内部固定公历、周一为首，时区只来自 `init` 参数；禁 `Calendar.current`/`Locale.current`/`autoupdatingCurrent`（CI 检查）；旧代码先原样迁入改名单独提交再按规格修正，`parser-check` 不迁入。
- 移植基线：demo 提交 `e3c0260`；PopoverController、StatusItemController、StatusMenu 三文件去单例去 EventKit，`activate(ignoringOtherApps:)` 改 `activate()`；不移植 `SettingsOpenerView`、不用 SwiftUI `Settings` 场景。
- 组装与启动：`AppEnvironment` 唯一组装点（`@MainActor`，不建窗口/图标，可用内存库+独立 UserDefaults 测试）；此外无全局单例，依赖构造注入。启动顺序：读启动参数 → 开数据库（失败进提示循环）→ 组装 AppEnvironment → 隐藏主菜单 → 菜单栏图标+常驻面板 → 后台备份。
- 调试参数（`LaunchOptions` 集中定义，方案预置不勾选）：`-ShikeDataDirectory`（展开 `~`，无效按打不开处理、不退默认）、`-ShikeSimulateWriteFailure`、`-ShikeSimulateDatabaseOpenFailure`（仅首次）；测试宿主以 `SHIKE_TEST_HOST=1` 跳过全部启动。
- 数据位置：`~/Library/Application Support/Shike/`，备份在 `Backups/`；先写临时文件再原子改名并清理残留。
- CI：checks 跑 ubuntu-latest，另两作业跑 macos-26；XcodeGen zip 校验 SHA-256；actions 以提交 SHA 锁定；concurrency 取消旧运行；每作业 30 分钟超时。
- 集中定义：偏好键在 `Preferences.Key`（阶段 0 仅 `backup.keepCount`，默认 7）；`Preferences` 经 `init(defaults:)` 接收 UserDefaults；日志 subsystem `io.github.micbik.shike`，category `app`/`data`/`backup`/`ui`。
- 流程：分支 `stage-0/foundation`，PR squash 合并；收尾打 `v0.0.0` 标签。

## UX & Interaction Patterns

- 文案：简体中文，称呼"你"，按钮用动词，无感叹号；字体颜色随系统。
- 菜单栏图标：SF Symbol `note.text` 模板图像，随深浅色适配，辅助功能描述"拾刻"。
- 面板：默认 360×520、限屏幕可见区域、系统弹出材质；内容常驻；顶栏仅「便签｜待办」分段（默认便签、不记忆），无搜索/⋯按钮。
- 空状态：便签 `note.text`+「还没有便签」，待办 `checklist`+「没有待办」；非空显示「共 N 条（列表将在阶段 1 提供）」，N 随数据更新。
- 错误提示条：顶栏下方红色，"保存失败：原因"/"读取失败：原因"+重试（读取失败重试=重新订阅）；失败原因共 11 种固定文案。
- 打开失败提示：标题「拾刻无法打开数据文件」，正文为原因+数据目录路径，按钮"重试"（默认）/"打开数据目录"/"退出"。
- 右键菜单顺序：设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q），仅右键时临时挂载；隐藏主菜单的编辑菜单用标准选择器（撤销/重做/剪切/复制/粘贴/全选），target nil 走响应链。
- 设置窗口六分页：通用、快捷键、提醒、卡片、数据、关于，占位"将在阶段 N 提供"（N=1、1、2、3、4）；"设置…"停当前分页，"关于拾刻"切到关于页。
- 关于页依次：图标（`note.text` 占位）、名称、版本（读 Info.plist）、源码链接、版权行、GPL 法律声明、"查看许可证"（单实例只读窗口，离线显示打包 LICENSE）、致谢（Reminders MenuBar、GRDB.swift）。

## Cross-Story Dependencies

- 故事严格按编号顺序实现，只依赖更小编号的故事；1.1（骨架）、1.2（CI）最先，之后每个故事都在 CI 下验证。
- 解析器（1.15、1.16）与数据层（1.3–1.6）互不依赖；数据安全故事（1.8、1.13、1.14）与面板数据/错误提示（1.10）依赖数据层；1.9、1.11 只依赖骨架。
- 1.9、1.11、1.13 按顺序向启动流程补入各自步骤（图标、主菜单、后台备份）。
- main 分支保护须等 CI 首次全绿后由产品负责人开启或授权，且在合并阶段 0 的 PR 之前完成。
- 1.17 架构交接最后做。
- 本史诗不依赖后续史诗；阶段 1 依赖其交付的契约：仓储与观察、AppEnvironment、PanelModel、Preferences。
