---
stepsCompleted:
  - step-01-validate-prerequisites
  - step-02-design-epics
  - step-03-create-stories
  - step-04-final-validation
inputDocuments:
  - _bmad-output/specs/spec-stage-0-foundation/SPEC.md
  - _bmad-output/specs/spec-stage-0-foundation/scope-boundaries.md
  - _bmad-output/specs/spec-stage-0-foundation/architecture-diagrams.md
  - _bmad-output/specs/spec-stage-0-foundation/stack.md
  - _bmad-output/specs/spec-stage-0-foundation/conventions.md
  - _bmad-output/specs/spec-stage-0-foundation/parser.md
  - _bmad-output/specs/spec-stage-0-foundation/data-layer.md
  - _bmad-output/specs/spec-stage-0-foundation/failure-modes.md
  - _bmad-output/specs/spec-stage-0-foundation/app-shell.md
  - docs/02-阶段路线图.md
  - docs/03-交互设计.md
  - docs/04-技术架构.md
  - docs/05-中文日期解析规格.md
  - docs/06-开发规范.md
---

# 拾刻 Shike - Epic Breakdown

## Overview

本文件把拾刻阶段 0（地基）的需求拆成可以逐个实现的故事。需求来源如下（06 §8）：

| 通常的来源 | 拾刻的对应来源 |
|---|---|
| PRD | 已定稿的阶段规格 `SPEC.md` |
| 架构文档 | 规格的伴随文件和 docs/04 |
| UX 文档 | docs/03 中与阶段 0 相关的章节 |

每个阶段对应一个史诗，史诗编号为阶段编号加 1，所以阶段 0 是 Epic 1（06 §8）。括号中的 CAP、S 编号用于追溯。

## Requirements Inventory

### Functional Requirements

**仓库与工程**

FR1：仓库包含以下文件，执行 `xcodegen generate` 并构建后 `git status` 是干净的（CAP-1、S0-01）：
- LICENSE（GPL-3.0 原文）；
- NOTICE，登记 GRDB 7.11.1、全部移植文件和 demo 基线提交 `e3c0260`；
- README，其中的构建步骤经过实测；
- .gitignore。

FR2：每个 `.swift`、`.sh` 源文件都以 06 §9 的 GPL 文件头开始；移植的文件另外带上来源和修改说明（CAP-1）。

FR3：用 XcodeGen 从 `project.yml` 生成工程，构建出 App「Shike」。它的最低系统为 macOS 15，使用 Swift 6，Bundle ID 为 `io.github.micbik.shike`，版本为 0.0.0（1）；运行时 Dock 中没有图标（CAP-2、S0-02）。

FR4：本地包 ShikeKit 提供 ShikeDateParser、ShikeData 两个库以及各自的测试目标，`swift test --package-path Packages/ShikeKit` 可以运行（CAP-2）。

**中文日期解析**

FR5：ChineseDateParser 的行为（CAP-3、S0-03）：
- 按 05 §4～§6 识别日期部分、时刻部分和相对时长，按 §5 顺延，按 §6 排除歧义；
- 输出 `date`、`hasTime`，以及按位置排序、互不重叠的 UTF-16 `matchedRanges`；
- 没有识别到时返回 nil。

FR6：解析结果与系统的区域、日历和"一周第一天"设置无关：内部固定使用公历，以周一为一周之首，时区由初始化参数给出（CAP-3）。

FR7：TitleCleaner 按 05 §7 的五个步骤，从原文得到待办标题（CAP-3）。

FR8：05 §9 的每一行（A01～M08）都有同编号的自动化测试。05 用例表与测试数据的编号或输入不一致时，守护测试失败（CAP-3）。

**数据层 v1**

FR9：打开数据库时，按 v1 结构（04 §5 和 data-layer.md）建立 `note`、`todo`、`stickyCard` 三张表及其约束和索引，迁移标识为 `v1`（CAP-4、S0-04）。

FR10：NoteRepository 支持新建、修改内容、置顶/取消置顶、软删除、恢复和永久删除（CAP-4）。

FR11：TodoRepository（CAP-4）：
- 支持新建、修改标题、设置或清除时间、完成/取消完成、稍后提醒、软删除、恢复和永久删除；
- 完成或修改时间时，清空 snoozedUntil；
- 全天待办的 dueAt 规范化为当天 00:00。

FR12：StickyCardRepository（CAP-4）：
- 支持钉出（幂等）、修改位置、修改选项和取消钉住；
- 便签软删除时卡片隐藏，恢复后重新出现；便签永久删除时，卡片级联删除。

FR13：数据观察以异步流的形式提供三类结果（CAP-4）：
- 未删除的便签，附带"是否已钉"；
- 未删除的待办；
- 可见的卡片，附带对应的便签。

订阅后先推送当前值，之后每次有相关的提交就推送新值。

FR14：时间与标识的存储规则（CAP-4）：
- updatedAt 只在内容类变化时更新（ADR-017）；
- uuid 以 36 位小写文本存储；
- 所有时间戳都取自注入的时钟。

FR15：操作不存在的记录时抛出 `notFound`；所有错误都以 `ShikeDataError` 和 `DataFailureReason` 分类抛出（CAP-4、CAP-5）。

**数据安全**

FR16：任何写入失败都以分类错误抛出，不存在"失败却返回成功"的路径（CAP-5、S0-05）。

FR17：PanelModel 把错误显示为顶栏下方的红色提示条（CAP-5）：
- 写入失败显示"保存失败：原因"，附"重试"；
- 读取失败显示"读取失败：原因"，"重试"会重新订阅。

FR18：调试启动参数 `-ShikeSimulateWriteFailure YES` 让所有仓储写方法抛出 `writeFailed(.simulated)`；迁移、观察和备份不受影响（CAP-5）。

FR19：启动时数据库打不开时，弹出提示（CAP-6、S0-05）：
- 触发情况：路径无效、目录不可用、文件损坏、迁移失败、库来自更新的版本、迁移前备份失败；
- 提示内容："拾刻无法打开数据文件"、原因、数据目录路径，以及"重试""打开数据目录""退出"三个按钮；
- App 不改用内存库，不新建空库，也不改动原文件。

FR20：打开失败提示的三个按钮（CAP-6）：
- "重试"：重新走完整的打开流程，成功后继续启动；
- "打开数据目录"：在访达中打开数据目录（目录不存在时打开上一级），然后回到提示；
- "退出"：退出 App。

FR21：调试启动参数 `-ShikeSimulateDatabaseOpenFailure YES` 只让第一次打开失败（CAP-6）。

FR22：每个本地自然日，在 `Backups/` 中生成一份 `shike-YYYY-MM-DD.sqlite`（CAP-7、S0-05）：
- 启动后在后台执行，跨天时再执行一次；当天已有备份则跳过；
- 按文件名中的日期保留最新的 7 份（`backup.keepCount`），忽略无关文件；
- 先写临时文件，再原子改名，并清理残留的临时文件；
- 失败只写日志。

FR23：打开已有的数据库、并且有待执行的迁移时，先生成 `Backups/shike-before-<迁移标识>-YYYY-MM-DD.sqlite`，这个文件不参与轮换。备份失败时不执行迁移，按"打不开"处理。新建的空库不做这种备份（CAP-14、ADR-018）。

**外壳界面**

FR24：菜单栏图标与面板的开关行为（CAP-8、S0-06）：
- 菜单栏显示模板图标 `note.text`，左键开关面板；面板打开后成为关键窗口；
- 点击面板和图标之外的地方时，面板收起；全局和本地监听作为兜底；
- 收起后 10 毫秒内的点击不再打开面板。

FR25：面板的内容与尺寸（CAP-8）：
- 默认尺寸 360×520，限制在所在屏幕的可见区域内；
- 顶栏有「便签｜待办」分段控件，默认为便签，不记忆上次的选择；
- 当前模式的列表为空时显示空状态（图标加标题），不为空时显示条数占位。

FR26：右键点击图标时弹出菜单：设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q）（CAP-9）。

FR27：隐藏主菜单提供设置…（⌘,）、退出拾刻（⌘Q），以及编辑菜单（撤销、重做、剪切、复制、粘贴、全选），均使用标准选择器和快捷键（CAP-9）。

FR28：设置窗口（CAP-10）：
- 只有一个实例，打开时显示在最前面；
- 六个分页依次为通用、快捷键、提醒、卡片、数据、关于；前五个显示"将在阶段 N 提供"，N 依次为 1、1、2、3、4；
- "设置…"停在当前分页，"关于拾刻"切到关于分页。

FR29：关于页（CAP-10）：
- 显示图标、名称、"版本 0.0.0（1）"、源码链接、版权声明、GPL 法律声明（无担保、可以依据 GPL 再分发和修改）以及致谢；
- "查看许可证"打开只读窗口，离线显示随 App 打包的 LICENSE。

**组装与可测试性**

FR30：AppEnvironment 是唯一的组装点，负责数据库、仓储、偏好设置、备份服务和面板模型。它不创建窗口，也不创建菜单栏图标，所以可以在测试中用内存库和独立的 UserDefaults 组装（CAP-11）。

FR31：在测试宿主中运行时（`SHIKE_TEST_HOST=1`），AppDelegate 跳过全部启动步骤：不建数据目录，不写入真实的偏好设置，不出现菜单栏图标（CAP-11）。

FR32：调试启动参数 `-ShikeDataDirectory <路径>` 把数据库和备份放到指定的绝对路径（会展开 `~`）。路径无效时按"打不开"处理，不会退回默认目录（CAP-11）。

FR33：启动顺序依次为：读取启动参数 → 打开数据库（失败则进入提示循环）→ 组装 AppEnvironment → 建立隐藏主菜单 → 创建菜单栏图标和常驻面板 → 在后台备份（CAP-11，04 §6.1）。

FR34：Preferences 以类型化的方式读写 UserDefaults，键名集中定义。阶段 0 只有一个键 `backup.keepCount`，默认值为 7（CAP-11、CAP-7）。

**CI 与交接**

FR35：GitHub Actions 在推送任意分支和发起 PR 时，运行三个作业（CAP-12、S0-07）：
- `checks`：检查文件头、导入边界、解析器区域设置和禁用项；
- `package-tests`：运行 `swift test`；
- `app`：用 XcodeGen 生成工程，然后运行 `xcodebuild build test`。

"警告即错误"只在 CI 上开启；任何一项失败都会让 CI 变红。

FR36：main 分支开启保护，要求三个作业都通过，并且只能经 PR 合并。`stage-0/foundation` 上的 CI 首次通过后、合并阶段 0 的 PR 之前，由产品负责人开启，或经其授权后执行（CAP-12）。

FR37：阶段 0 收尾时（CAP-13）：
- 04 写回经过实现验证的契约，并新增"扩展指南"；
- 07 为重大取舍新增 ADR；
- 06、NOTICE、README、CLAUDE.md 与 CI 的实测结果一致；
- 02 的状态随之更新。

### NonFunctional Requirements

NFR1：**工具链。**最低 macOS 15；Swift 6 语言模式，严格并发检查；Xcode 26 或更高。以 CI 为准（macos-26 镜像默认的 Xcode 26.6）；ShikeKit 的 `swift-tools-version` 为 6.2。

NFR2：**模块边界。**
- App 只依赖 ShikeData 和 ShikeDateParser，这两个库互不依赖。
- ShikeKit 不引入 AppKit/SwiftUI；ShikeDateParser 只依赖 Foundation。
- ShikeData 以 `internal import` 引入 GRDB，公开 API 中没有 GRDB 类型；App 不 `import GRDB`。

NFR3：**生命周期。**使用 `main.swift` 加 `AppDelegate`，不用 SwiftUI 的 App/Scene；窗口由 AppKit 管理，内容用 SwiftUI；`LSUIElement = YES`。

NFR4：**不丢数据。**
- 不静默吞掉错误：写入和文件操作的失败不用 `try?` 丢弃。
- 绝不降级为内存库或空库。
- 禁用 `eraseDatabaseOnSchemaChange`。
- 迁移只追加；执行新迁移前先备份。

NFR5：**组装。**除 AppEnvironment 外不使用全局单例，依赖都通过初始化参数注入。

NFR6：**依赖锁定。**GRDB 固定为 7.11.1；CI 中 XcodeGen 固定为 2.46.0 并校验 SHA-256；GitHub Actions 以提交 SHA 锁定。

NFR7：**GPL-3.0-only 合规。**所有源文件带文件头；移植文件登记到 NOTICE 和 04 §7。

NFR8：**测试的确定性。**基准时间 T0 = 2026-09-23 12:00，时区 Asia/Shanghai；时钟通过注入获得；优先用 L1 测试覆盖（06 §4）。

NFR9：**集中定义。**
- 界面文案放在 `Localizable.xcstrings` 中（zh-Hans，使用语义键和生成的符号）。
- 偏好键在 `Preferences.Key` 中定义。
- 调试参数在 `LaunchOptions` 中定义。

NFR10：**隐私。**没有遥测；阶段 0 没有网络访问。日志的 subsystem 为 `io.github.micbik.shike`，category 为 `app`、`data`、`backup`、`ui`，不记录用户内容。

NFR11：**零新增编译警告。**CI 以"警告即错误"执行。

NFR12：**性能。**
- 启动路径上不做同步的重活，备份在后台执行。
- 面板内容常驻。
- 解析器的正则预编译，单次解析低于 1 毫秒（在 S5-05 实测）。

NFR13：**最小化。**只创建阶段 0 用到的目录、类型和偏好键。

NFR14：**并发。**界面类型显式标注 `@MainActor`；ShikeKit 的公开类型是 `Sendable` 值类型；系统回调在主线程访问界面状态。

### Additional Requirements

**工程骨架**

- 没有现成的启动模板，工程由 `project.yml`（XcodeGen）从零生成。最先的两个故事搭好工程骨架（`project.yml`、`Package.swift`、最小可运行的 App、两类测试目标）和 CI，之后的每个故事都在 CI 下验证。
- `project.yml` 的要点（stack.md）：
  - 签名与安全：ad-hoc 签名，不启用 Hardened Runtime 和沙盒。
  - 构建设置：`SWIFT_TREAT_WARNINGS_AS_ERRORS: "$(SHIKE_WARNINGS_AS_ERRORS:default=NO)"`、`STRING_CATALOG_GENERATE_SYMBOLS: YES`、`developmentLanguage: zh-Hans`。
  - 资源：根目录的 LICENSE 作为资源打包。
  - 测试方案：注入 `SHIKE_TEST_HOST=1`，并预置三个默认不勾选的调试参数。
- `Package.swift` 的要点：第一行为 `swift-tools-version: 6.2`；GRDB 用 `exact: "7.11.1"`；包含四个目标；设置环境变量 `SHIKE_WARNINGS_AS_ERRORS=YES` 时启用 `treatAllWarnings(as: .error)`；`Package.resolved` 入库。
- 不要在 xcodebuild 命令行传 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`，它与 GRDB 冲突，会导致构建失败（已实测）。

**ShikeData 与解析器**

- ShikeData（data-layer.md）：
  - 以 `internal import GRDB` 引入 GRDB，同时显式 `import Foundation`；公开值类型与内部 Record 类型分离。
  - UUID 编码必须写成静态函数 `databaseUUIDEncodingStrategy(for:)`。写成静态属性会被静默忽略，结果存成 BLOB（已实测）。
  - 通过 `transactionClock` 注入时钟。
  - 磁盘上用 `DatabasePool`（WAL），内存中用 `DatabaseQueue`。
  - 打开时用 `hasBeenSuperseded` 检查库是否来自更新的版本。
  - 迁移器可以注入测试专用的迁移。
  - 使用类型化 ID；仓储是 `Sendable` 结构体；观察以去重的 `AsyncThrowingStream` 提供；错误按 data-layer.md 的分类表抛出。
- 解析器（parser.md）：
  - 用 `struct` 实现，正则用 `static let` 形式的 `NSRegularExpression`（Swift `Regex` 不是 `Sendable`）；日期通过回读来校验合法性。
  - 迁入步骤：先把旧代码原样迁入并改名，单独提交一次，再按 05 修复；`parser-check` 不迁入。
  - 行为差异按对照表处理；守护测试读取 docs/05 的用例表。

**移植、CI 与流程**

- 移植（app-shell.md）：
  - 以 demo 提交 `e3c0260` 为基线，涉及 PopoverController、StatusItemController、StatusMenu 三个文件。
  - 去掉单例和 EventKit；把 `activate(ignoringOtherApps:)` 改为 `activate()`；尺寸按 03 §3。
  - 每个文件都登记到 NOTICE 和 04 §7。
- CI：
  - `checks` 运行在 ubuntu-latest 上；`package-tests` 和 `app` 运行在 macos-26 上。
  - XcodeGen zip 的 SHA-256 为 `4d9e34b6…0196806`；actions/checkout 用 v7.0.1（`3d3c42e5…`）。
  - 启用 `concurrency` 取消重复运行；作业名固定。
- 数据位置：
  - 数据目录为 `~/Library/Application Support/Shike/`，备份在其中的 `Backups/`。
  - 文件名为 `shike-YYYY-MM-DD.sqlite` 和 `shike-before-<迁移>-YYYY-MM-DD.sqlite`，日期按公历和注入的时区计算。
- 流程（06 §6）：
  - 分支为 `stage-0/foundation`，经 PR squash 合并。
  - 收尾时在 main 上打 `v0.0.0` 标签。
  - 更新 02 中的状态。

### UX Design Requirements

UX-DR1：菜单栏图标使用 SF Symbol `note.text` 的模板图像，自动适配深浅色，辅助功能描述为"拾刻"（03 §2、§15）。

UX-DR2：面板默认 360×520 pt，限制在所在屏幕的可见区域内；背景使用系统默认的弹出材质，在 macOS 26 及以上为 Liquid Glass（03 §3）。

UX-DR3：顶栏左侧为「便签｜待办」分段控件；阶段 0 的顶栏没有搜索按钮和 ⋯ 按钮（03 §3）。

UX-DR4：空状态（03 §14）：
- 便签模式显示图标 `note.text` 和"还没有便签"；
- 待办模式显示图标 `checklist` 和"没有待办"；
- 引导句归 S1-10，阶段 0 不显示。

UX-DR5：列表不为空时，显示占位"共 N 条（列表将在阶段 1 提供）"。

UX-DR6：错误提示条显示在顶栏下方，红色，文案为"保存失败：原因"或"读取失败：原因"，带"重试"按钮（03 §3、§14）。

UX-DR7：打开失败提示的标题为"拾刻无法打开数据文件"，正文是原因和数据目录路径；按钮依次为"重试"（默认）、"打开数据目录"、"退出"（03 §14）。

UX-DR8：错误原因共 11 种，文案按 app-shell.md 的表格，例如"磁盘空间不足""数据文件已损坏""数据文件来自更新版本的拾刻""数据目录路径无效"。

UX-DR9：右键菜单的菜单项和顺序为：设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q）（03 §2）。

UX-DR10：设置窗口顶部为分页：通用、快捷键、提醒、卡片、数据、关于；占位分页的文案为"将在阶段 N 提供"（03 §9）。

UX-DR11：关于页依次显示（03 §9）：
- 图标（`note.text` 占位）、名称"拾刻"、"版本 0.0.0（1）"；
- 源码链接；
- 版权行"Copyright (C) 2026 Shike contributors"；
- 法律声明段落："拾刻是自由软件：你可以依据 GNU 通用公共许可证第 3 版（GPL-3.0-only）的条款再分发和修改它。本程序不提供任何担保。"；
- "查看许可证"按钮；
- 致谢：Reminders MenuBar、GRDB.swift。

UX-DR12：许可证窗口只有一个实例，是只读的文本窗口，标题为"许可证"，显示随 App 打包的 LICENSE。

UX-DR13：文案风格：简体中文，称呼用"你"，按钮用动词，不用感叹号；字体和颜色跟随系统（03 §15）。

UX-DR14：隐藏编辑菜单的文案为"编辑"，菜单项为撤销、重做、剪切、复制、粘贴、全选。

### FR Coverage Map

| FR | 内容 | 史诗 | 故事 |
|---|---|---|---|
| FR1 | 仓库基础文件（LICENSE、NOTICE、README、.gitignore）；生成并构建后工作区干净 | Epic 1 | 1.1；移植文件的登记见 1.9、1.11；收尾核对见 1.17 |
| FR2 | GPL 文件头与移植说明 | Epic 1 | 1.1、1.2 |
| FR3 | XcodeGen 工程与 App 基本属性，Dock 中没有图标 | Epic 1 | 1.1 |
| FR4 | ShikeKit 的两个库与测试目标 | Epic 1 | 1.1 |
| FR5 | 中文日期解析：识别、顺延、排除歧义 | Epic 1 | 1.15、1.16 |
| FR6 | 解析结果与系统区域设置无关 | Epic 1 | 1.15 |
| FR7 | 待办标题清理 | Epic 1 | 1.16 |
| FR8 | 05 用例表全覆盖与守护测试 | Epic 1 | 1.15、1.16 |
| FR9 | v1 表结构与迁移 | Epic 1 | 1.3 |
| FR10 | 便签仓储 | Epic 1 | 1.4 |
| FR11 | 待办仓储 | Epic 1 | 1.5 |
| FR12 | 卡片仓储与级联规则 | Epic 1 | 1.6 |
| FR13 | 三类数据观察 | Epic 1 | 1.4、1.5、1.6 |
| FR14 | updatedAt、uuid 与时钟规则 | Epic 1 | 1.3～1.6 |
| FR15 | notFound 与错误分类 | Epic 1 | 1.3～1.6 |
| FR16 | 写入失败一定抛出分类错误 | Epic 1 | 1.4 |
| FR17 | 面板错误提示条与重试 | Epic 1 | 1.10 |
| FR18 | 模拟写入失败参数 | Epic 1 | 1.4～1.6、1.8 |
| FR19 | 数据库打不开提示 | Epic 1 | 1.3、1.8、1.14 |
| FR20 | 打开失败提示的三个按钮 | Epic 1 | 1.8 |
| FR21 | 模拟打开失败参数 | Epic 1 | 1.8 |
| FR22 | 每日备份与轮换 | Epic 1 | 1.13 |
| FR23 | 迁移前备份 | Epic 1 | 1.14 |
| FR24 | 菜单栏图标与面板的开关 | Epic 1 | 1.9 |
| FR25 | 面板内容与尺寸 | Epic 1 | 1.9、1.10 |
| FR26 | 右键菜单 | Epic 1 | 1.11 |
| FR27 | 隐藏主菜单 | Epic 1 | 1.11 |
| FR28 | 设置窗口与分页占位 | Epic 1 | 1.11 |
| FR29 | 关于页与许可证窗口 | Epic 1 | 1.12 |
| FR30 | AppEnvironment 组装点 | Epic 1 | 1.7；1.9、1.13 接入新组件 |
| FR31 | 测试宿主中跳过启动 | Epic 1 | 1.8 |
| FR32 | 数据目录参数 | Epic 1 | 1.8 |
| FR33 | 启动顺序 | Epic 1 | 1.8；1.9、1.11、1.13 按顺序补入各自的步骤 |
| FR34 | 类型化偏好设置 | Epic 1 | 1.7 |
| FR35 | CI 的三个作业 | Epic 1 | 1.2 |
| FR36 | main 分支保护 | Epic 1 | 1.2 |
| FR37 | 架构交接与文档写回 | Epic 1 | 1.17；02 的状态在第 ⑧ 步验收通过后更新 |

**UX-DR 覆盖：**UX-DR1～UX-DR3 → 1.9；UX-DR4～UX-DR6 → 1.10；UX-DR7、UX-DR8 → 1.8；UX-DR9、UX-DR10、UX-DR14 → 1.11；UX-DR11、UX-DR12 → 1.12（1.11 先交付关于页的图标、名称和版本）；UX-DR13 → 1.8～1.12。

## Epic List

### Epic 1: 阶段 0 · 地基

完成后，产品负责人可以在 Mac 上运行拾刻：
- 菜单栏有图标，Dock 中没有图标；
- 左键弹出带「便签｜待办」切换和空状态的面板，点击外部即收起；
- 右键菜单能打开设置窗口（关于页完整），也能退出；
- 数据库打不开时给出明确提示，不改动原文件；写入失败一定报错；每天自动备份，执行迁移前先备份。

后续阶段的负责人拿到分层清晰、由 CI 守护的工程，以及按 05 全量测试的中文日期解析器和 v1 数据层，可以直接开始阶段 1。本史诗对应 02 中的 S0-01～S0-07 和阶段 0 的 7 条验收。

**覆盖的功能需求：**FR1～FR37（全部）。NFR1～NFR14 和 UX-DR1～UX-DR14 分配到各故事的验收标准中。

**实施说明：**
- 工程骨架和 CI 最先做，之后每个故事都在 CI 下验证。
- 解析器和数据层互不依赖。
- 数据安全的四项（写入失败、打不开提示、每日备份、迁移前备份）依赖数据层。
- 面板订阅数据变化和错误提示条依赖数据层；菜单栏图标、右键菜单和设置窗口只依赖工程骨架。
- 架构交接最后做。分支保护要等首次 CI 通过后，由产品负责人开启或授权。
- 本史诗不依赖任何后续史诗。阶段 1 依赖本史诗交付的契约：仓储与观察、AppEnvironment、PanelModel、Preferences。

## Epic 1: 阶段 0 · 地基

完成后，产品负责人可以在 Mac 上运行只驻留在菜单栏的拾刻，"不丢数据"的安全机制全部就位。后续阶段的负责人拿到分层清晰、由 CI 守护的工程，以及按 05 全量测试的中文日期解析器和 v1 数据层，可以直接开始阶段 1。本史诗对应 02 中的 S0-01～S0-07 和阶段 0 的 7 条验收。

- 故事按编号顺序实现，每个故事只依赖编号在它之前的故事。
- 每个故事的"依据"列出它实现的需求和要遵守的契约。伴随文件都在 `_bmad-output/specs/spec-stage-0-foundation/` 中；"03""04"等指 docs/ 下对应编号的文档。
- 所有故事都遵守全部 NFR，"依据"中只列出与该故事关系最密切的几条。

### Story 1.1: 搭建工程骨架

作为后续阶段的负责人，
我希望克隆仓库后就能生成工程、构建 App 并运行测试，
以便在统一、可复现的工程结构上开发，不必自己摸索环境。

**依据：**FR1～FR4；NFR1、NFR3、NFR6、NFR7、NFR13；stack.md「版本」「project.yml 要点」「ShikeKit（Package.swift）要点」「警告即错误：只在 CI 开启」；conventions.md「目录与文件」；app-shell.md「文件布局」。

**验收标准：**

**假如** 一份新克隆的仓库
**当** 查看根目录
**那么** 有 LICENSE、NOTICE.md、README.md 和 .gitignore；LICENSE 与 <https://www.gnu.org/licenses/gpl-3.0.txt> 逐字一致
**并且** NOTICE.md 登记了 GRDB.swift 7.11.1（MIT）和 demo 基线提交 `e3c0260a8630381224e80f5f0e0c6700f2e417aa`，移植清单暂时为空；README 中的构建步骤经过实测

**假如** 一台装有 Xcode 26 或更高版本、XcodeGen 2.46.0 的 Mac
**当** 在仓库根目录运行 `xcodegen generate`，再用 xcodebuild 构建 Shike 方案
**那么** 构建成功，App 的 Bundle ID 为 `io.github.micbik.shike`，版本为 0.0.0（1），最低系统为 macOS 15.0，显示名称为"拾刻"
**并且** 生命周期由 `main.swift` 和 `AppDelegate` 管理；运行后 Dock 中没有图标（`LSUIElement`）

**假如** 同一份仓库
**当** 运行 `swift test --package-path Packages/ShikeKit`
**那么** ShikeDateParserTests 和 ShikeDataTests 都至少有一个测试，并全部通过
**并且** ShikeDataTests 中有测试通过 GRDB 实际打开数据库，证明 GRDB 7.11.1 能在 Swift 6 严格并发检查下使用

**假如** 已经生成工程
**当** 用 xcodebuild 运行 Shike 方案的测试
**那么** ShikeTests 全部通过，其中一个测试通过字符串目录生成的符号读取 `app.name`，得到"拾刻"

**假如** 查看工程和包的依赖配置
**那么** App 只依赖 ShikeData 和 ShikeDateParser 两个产品，不直接依赖 GRDB；ShikeDateParser 没有依赖；GRDB 以 `exact: "7.11.1"` 锁定，`Packages/ShikeKit/Package.resolved` 入库
**并且** ShikeData 中凡是引入 GRDB 的源文件，都写 `internal import GRDB`，并显式 `import Foundation`
**并且** 只创建本故事用到的目录；两个库只包含阶段 0 契约中的类型，不写之后要删除的占位代码

**假如** 仓库中任意一个 `.swift` 或 `.sh` 文件
**那么** 它以 06 §9 的文件头开始；Package.swift 的第一行是 `// swift-tools-version: 6.2`，文件头紧随其后

**假如** 设置了环境变量 `SHIKE_WARNINGS_AS_ERRORS=YES`，并向 xcodebuild 传入同名设置
**当** 运行包测试和 App 构建
**那么** ShikeKit 的四个目标和 App 目标都按"警告即错误"编译：临时加入一处警告时构建失败；GRDB 不受影响，不出现 `-warnings-as-errors` 与 `-suppress-warnings` 冲突
**并且** 不设置时，本地构建不会因为警告而失败

**假如** 已经执行过上述生成、构建和测试
**当** 运行 `git status`
**那么** 工作区是干净的：`Shike.xcodeproj`、`.build/`、DerivedData 等构建产物都被忽略

### Story 1.2: 建立 CI 流水线

作为产品负责人，
我希望每次推送和发起 PR 时，GitHub 都自动检查、测试并构建，
以便"是否完成"由 CI 裁决，main 只接受检查通过的合并。

**依据：**FR2、FR35、FR36；NFR2、NFR6、NFR11；stack.md「CI 工作流」「分支保护」；conventions.md「检查项（CI checks 作业）」。

**验收标准：**

**假如** 向任意分支推送，或者发起 PR
**当** GitHub Actions 运行 `.github/workflows/ci.yml`
**那么** 出现 `checks`（ubuntu-latest）、`package-tests`（macos-26）、`app`（macos-26）三个作业，并全部通过
**并且** 两个 macOS 作业的日志中打印了 `xcodebuild -version`

**假如** 查看工作流文件
**那么** 所有 action 都以提交 SHA 锁定，并在注释中写明版本（actions/checkout v7.0.1 为 `3d3c42e5aac5ba805825da76410c181273ba90b1`）
**并且** 启用了 `concurrency`，同一 ref 上新的运行会取消旧的；`permissions` 为 `contents: read`；每个作业 `timeout-minutes: 30`

**假如** `app` 作业需要 XcodeGen
**当** 作业安装它
**那么** 下载 2.46.0 的 `xcodegen.zip`，用 `shasum -a 256 -c` 校验 SHA-256（`4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`）通过后才解压使用；校验不符时作业失败
**并且** 随后运行 `xcodegen generate`，再用 xcodebuild 执行 build 和 test

**假如** 某次提交在 ShikeKit 或 App 中新增了一处编译警告
**当** CI 运行
**那么** `package-tests` 或 `app` 失败：两个作业都设置了 `SHIKE_WARNINGS_AS_ERRORS=YES`，并向 xcodebuild 传入同名设置
**并且** 命令行中没有直接传 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`

**假如** 出现 conventions.md「检查项」中的任一违规：
- 缺少文件头，或含"源自 Reminders MenuBar"的文件没有登记到 NOTICE.md；
- ShikeKit 引入 AppKit、SwiftUI、Cocoa、UIKit 或 Carbon（包括带 `@testable` 或访问级别修饰的写法）；App 或 ShikeTests 中 `import GRDB`；ShikeData 中不是 `internal import GRDB`；ShikeDateParser 引入 Foundation 以外的模块；
- 解析器源码中出现 `Calendar.current`、`Locale.current` 或 `autoupdatingCurrent`；
- 出现 `eraseDatabaseOnSchemaChange`，或 `Shike/` 中出现 `static let shared`、`static var shared`。

**当** `checks` 作业运行检查脚本（本地也能运行同一个脚本）
**那么** 作业失败，并指出违规的文件和规则
**并且** 检查脚本带有自检：为每条规则构造一个违规样例，确认会失败；`checks` 作业先运行自检

**假如** CI 第一次运行 `app` 作业
**那么** 1.1 中通过生成的符号读取 `app.name` 的测试，在 CI 的 Xcode 上通过
**并且** 如果 CI 的 Xcode 不支持生成符号，按 stack.md 改用 `String(localized: "键")`，并同步修改 stack.md、conventions.md，以及 NFR9 与 1.1 中"生成的符号"相关验收标准的措辞

**假如** `stage-0/foundation` 上的 CI 首次全部通过
**当** 产品负责人开启 main 的分支保护，或明确授权后由 AI 用 `gh` 执行
**那么** main 要求 `checks`、`package-tests`、`app` 三项通过，并且只能经 PR 合并
**并且** 这一步在合并阶段 0 的 PR 之前完成

### Story 1.3: 数据库的打开与 v1 表结构

作为产品负责人，
我希望拾刻打开数据文件时，要么完整成功，要么明确失败而且不碰原文件，
以便从阶段 1 起每天记下的真实内容，都保存在结构正确、不会被意外改写的库里。

**依据：**FR9、FR14、FR15、FR19；NFR2、NFR4、NFR8、NFR14；data-layer.md「AppDatabase」「结构细节」「错误分类」，以及「L1 测试清单」中关于打开和结构的各项；04 §5；failure-modes.md。

**验收标准：**

**假如** 一个尚不存在的绝对路径目录
**当** 调用 `AppDatabase.open(directory:options:)`
**那么** 目录被创建，其中生成 WAL 模式的 `shike.sqlite`，迁移 `v1` 在一个事务中执行完毕
**并且** `AppDatabase.inMemory(options:)` 执行同样的迁移

**假如** 刚迁移完的空库
**当** 用 `PRAGMA table_info`、`index_list`、`foreign_key_list` 检查
**那么** `note`、`todo`、`stickyCard` 三张表的列、类型、可空性和默认值都与 04 §5 及 data-layer.md 一致；存在索引 `note_on_deletedAt`、`todo_on_deletedAt`、`todo_on_completedAt_dueAt`；`stickyCard.noteId` 唯一，外键指向 `note(id)` 并设置 `ON DELETE CASCADE`
**并且** 直接用 SQL 插入 `dueHasTime = 1` 而 `dueAt` 为空的待办会被拒绝；为同一张便签插入第二张卡片也会被拒绝

**假如** `directory` 是相对路径，或者不是文件 URL
**当** 调用 `open`
**那么** 抛出 `openFailed(.invalidLocation)`，不创建任何文件或目录

**假如** 数据目录无法创建，或者没有访问权限
**当** 调用 `open`
**那么** 抛出 `openFailed(.permissionDenied)`，不写任何文件

**假如** 目录中的 `shike.sqlite` 已损坏（内容不是 SQLite 数据库）
**当** 调用 `open`
**那么** 抛出 `openFailed(.corrupted)`；该文件逐字节不变，也没有生成替代的新库

**假如** 一个登记了未知迁移标识的库（来自更新版本的拾刻）
**当** 调用 `open`
**那么** 抛出 `openFailed(.newerSchema)`，库文件没有被写入（夹具由内部工厂注册 `v1` 与一个测试迁移建库，再用只注册 `v1` 的生产迁移器打开；不通过 user_version 伪造）

**假如** SQLite 返回各种主结果码
**当** ShikeData 把它们转换为 `ShikeDataError`
**那么** 分类与 data-layer.md「错误分类」表一一对应，每种 DataFailureReason 都有映射测试，例如 SQLITE_FULL 为 `diskFull`，SQLITE_NOTADB 为 `corrupted`，SQLITE_BUSY 为 `busy`，SQLITE_IOERR 为 `ioError`，表外的代码为 `unknown(code:)`
**并且** 公开 API 中不出现任何 GRDB 类型

**假如** 通过 `Options.clock` 注入了固定时钟
**当** 在写事务中读取当前时间
**那么** 得到注入的时间：时钟经 GRDB 的 `transactionClock` 注入，同一事务内的时间相同
**并且** 注入每次调用返回不同时间的时钟时，同一次写入中的时间相同、两次独立写入的时间不同

**假如** 测试在 v1 之后追加了一个测试专用的迁移
**当** 打开数据库
**那么** 该迁移也被执行：迁移器由内部工厂创建，可以注入测试迁移，生产代码只注册 `v1`
**并且** 代码中没有 `eraseDatabaseOnSchemaChange`

### Story 1.4: 便签的保存与观察

作为后续阶段的负责人，
我希望通过仓储新建、修改、置顶、删除和恢复便签，并用观察流自动拿到最新的列表，
以便界面代码不直接访问数据库，数据一变，列表就自动更新。

**依据：**FR10、FR13～FR16、FR18；NFR4、NFR8、NFR14；data-layer.md「公开类型」「仓储」「观察」「错误分类」「L1 测试清单」。

**验收标准：**

**假如** 注入了固定时钟 T0（2026-09-23 12:00，Asia/Shanghai）的内存库
**当** 调用 `NoteRepository.create(content:)`
**那么** 返回的便签带有新的 uuid，createdAt 和 updatedAt 都等于 T0
**并且** 库中 uuid 列的 `typeof` 为 `text`，值匹配 `^[0-9a-f-]{36}$`，时间以 UTC 文本存储
**并且** `Note`、`Note.ID`、`NoteListItem` 是 `Sendable` 值类型；与数据库之间的编解码由内部 Record 类型负责，Record 用**静态函数** `databaseUUIDEncodingStrategy(for:)` 指定小写文本

**假如** 一张已有的便签
**当** 分别调用 `updateContent`、`setPinned`、`softDelete`、`restore`
**那么** 只有 `updateContent` 会更新 updatedAt（ADR-017）
**并且** `setPinned` 把 pinnedAt 设为当前时间或 nil，已经是目标状态时不改动；`softDelete` 设置 deletedAt，已删除的保留原来的 deletedAt；`restore` 清空 deletedAt；已软删除的便签仍然可以 `updateContent`

**假如** 一张已有的便签
**当** 调用 `permanentlyDelete`
**那么** 该行从库中删除

**假如** 一个不存在的便签 ID
**当** 调用任何一个修改方法
**那么** 抛出 `notFound`

**假如** 订阅了 `observeActive()`
**那么** 先收到当前值：未删除的便签按 updatedAt 降序、id 降序排列，每项附带 `isPinnedToDesktop`
**并且** 每次写入提交后收到新值，软删除的便签从结果中消失；写入无关的表时不推送重复的值；取消消费的 Task 即停止观察
**并且** 读取失败时，流以 `readFailed(原因)` 结束（测试中在观察进行时用第二个连接对同一库执行 `DROP TABLE note`）

**假如** 以只读方式打开同一个库文件
**当** 调用写方法
**那么** 抛出 `writeFailed(.readOnly)`
**并且** 不存在"失败却返回成功"的路径；ShikeData 中没有用 `try?` 丢弃写入或文件操作失败的地方

**假如** `Options.simulateWriteFailure` 为真
**当** 调用 NoteRepository 的任何写方法
**那么** 抛出 `writeFailed(.simulated)`，库中数据不变；迁移、观察和备份照常工作
**并且** 这一机制由三个仓储共用，之后的待办和卡片仓储直接沿用

### Story 1.5: 待办的保存与观察

作为后续阶段的负责人，
我希望通过仓储管理待办的标题、时间、完成状态和稍后提醒，并用观察流拿到最新的列表，
以便阶段 1、2 的待办功能直接建立在规则正确的数据层上。

**依据：**FR11、FR13～FR15、FR18；NFR8、NFR14；data-layer.md「公开类型」「仓储」「观察」「L1 测试清单」。

**验收标准：**

**假如** 时区为 Asia/Shanghai、时钟为 T0 的内存库
**当** 用 `TodoRepository.create(title:due:)` 新建一条全天待办，日期为 2026-09-25 15:30
**那么** dueAt 存为 2026-09-25 00:00（Asia/Shanghai），dueHasTime 为否；带时刻的待办按原样保存
**并且** uuid 以小写文本存储，createdAt 和 updatedAt 都等于 T0；`Todo`、`Todo.ID`、`TodoDue` 是 `Sendable` 值类型

**假如** 一条设置了 snoozedUntil 的待办
**当** 调用 `setDue`（包括清除时间）或 `setCompleted(true)`
**那么** snoozedUntil 被清空
**并且** `setCompleted(true)` 把 completedAt 设为当前时间，`setCompleted(false)` 清空 completedAt，已经是目标状态时不改动

**假如** 一条已有的待办
**当** 调用 `updateTitle`、`setDue`、`setCompleted` 或 `snooze`
**那么** updatedAt 更新
**并且** `softDelete`、`restore` 不更新 updatedAt（ADR-017）

**假如** 一条待办
**当** 调用 `snooze(_:until:)`
**那么** snoozedUntil 存为传入的时间，updatedAt 更新

**假如** 一条已有的待办，以及一个不存在的待办 ID
**当** 调用 `softDelete`、`restore`、`permanentlyDelete`，以及对不存在的 ID 调用任何修改方法
**那么** 前三者的语义与便签相同；对不存在的待办抛出 `notFound`

**假如** 订阅了 `observeActive()`
**那么** 先收到当前值：未删除的待办（包括已完成的）按 createdAt 降序、id 降序排列
**并且** 每次写入提交后收到新值

**假如** `Options.simulateWriteFailure` 为真
**当** 调用 TodoRepository 的任何写方法
**那么** 抛出 `writeFailed(.simulated)`，库中数据不变

### Story 1.6: 桌面卡片的数据

作为阶段 3 的负责人，
我希望卡片的位置和选项已经能保存，并且随便签的删除和恢复自动隐藏、重新出现，
以便实现桌面卡片时不需要改动 v1 表结构。

**依据：**FR12、FR13、FR18；data-layer.md「公开类型」「仓储」「观察」「L1 测试清单」。

**验收标准：**

**假如** 一张未删除的便签
**当** 调用 `StickyCardRepository.pin(_:frame:options:)`
**那么** 新建一张卡片，createdAt 和 updatedAt 都等于当前时间
**并且** 再次钉出同一张便签时，返回现有的卡片，不做任何改动；便签不存在或已软删除时抛出 `notFound`

**假如** 一张已有的卡片
**当** 调用 `updateFrame` 或 `updateOptions`
**那么** 对应的列被更新，卡片的 updatedAt 更新
**并且** `hiddenOpacity` 在类型内钳制到 0.0～0.6；`StickyCard`、`CardFrame`、`StickyCardOptions`（以及层级、颜色、字号三个枚举）、`VisibleCard` 都是 `Sendable` 值类型

**假如** 一张已有的卡片
**当** 调用 `unpin`
**那么** 卡片被删除，便签不变

**假如** 一个不存在的卡片 ID
**当** 调用 `updateFrame`、`updateOptions` 或 `unpin`
**那么** 抛出 `notFound`

**假如** 一张已钉出卡片的便签
**当** 便签被软删除，然后被恢复
**那么** 卡片先从 `observeVisible()` 的结果中消失，恢复后重新出现
**并且** 便签被永久删除时，卡片随之级联删除

**假如** 订阅了 `observeVisible()`
**那么** 先收到当前值：所属便签未删除的卡片，每项附带该便签，按 createdAt 升序、id 升序排列；每次相关的写入提交后收到新值
**并且** 便签观察中的 `isPinnedToDesktop` 在钉出后为是，取消钉住后为否

**假如** `Options.simulateWriteFailure` 为真
**当** 调用 StickyCardRepository 的任何写方法
**那么** 抛出 `writeFailed(.simulated)`，库中数据不变

### Story 1.7: 组装点与偏好设置

作为后续阶段的负责人，
我希望有唯一的组装点来创建数据库、仓储和各项服务，偏好设置可以类型化地读写，
以便新增服务、窗口和偏好键时有固定的接入位置，测试也能脱离真实数据组装整个 App。

**依据：**FR30、FR34；NFR5、NFR9、NFR14；app-shell.md「组件契约」中的 AppEnvironment 和 Preferences；conventions.md「组装与依赖」「偏好设置与调试启动参数」。

**验收标准：**

**假如** 一个内存库和一个独立 suite 的 UserDefaults
**当** 在 L2 测试中构造 `AppEnvironment(database:preferences:)`
**那么** 它提供三个仓储和 Preferences；通过它的仓储写入的便签，能从同一个库的观察中读到
**并且** AppEnvironment 标注 `@MainActor`，不创建任何窗口，也不创建菜单栏图标

**假如** 一个空的独立 suite
**当** 读取 `backup.keepCount`
**那么** 得到默认值 7；写入新值后能读回；测试结束时清除该 suite
**并且** 键名只在 `Preferences.Key` 中定义，默认值在同一处注册；`Preferences` 通过 `init(defaults:)` 接收 UserDefaults

**假如** 查看 `Shike/` 中的代码
**那么** 除 AppEnvironment 外没有全局单例，依赖都通过初始化参数注入；CI 的禁用项检查通过

### Story 1.8: 数据库打不开时的提示

作为产品负责人，
我希望拾刻启动时如果打不开数据文件，会告诉我原因，并让我选择重试、打开数据目录或退出，
以便数据出问题时我清楚发生了什么，而拾刻绝不会拿空库顶替或覆盖我的数据。

**依据：**FR18～FR21、FR31～FR33；UX-DR7、UX-DR8、UX-DR13；NFR4、NFR9、NFR10；failure-modes.md「打开失败提示」「日志」；app-shell.md「组件契约」中的测试宿主和 LaunchOptions，以及「阶段 0 文案」；architecture-diagrams.md §3、§4；stack.md「project.yml 要点」中的方案配置。

**验收标准：**

**假如** 数据库能正常打开
**当** 拾刻启动
**那么** AppDelegate 依次读取启动参数、打开数据目录中的数据库、组装 AppEnvironment（architecture-diagrams.md §3），并把数据目录传入 AppEnvironment
**并且** 默认数据目录为 `~/Library/Application Support/Shike/`

**假如** 启动时数据库打不开（路径无效、目录不可用、文件损坏、迁移失败，或库来自更新的版本）
**当** 拾刻启动
**那么** 先调用 `NSApp.activate()`，再显示提示：标题为"拾刻无法打开数据文件"，正文为原因文案和数据目录路径，按钮依次为"重试"（默认）、"打开数据目录"、"退出"
**并且** 提示期间还没有组装 AppEnvironment；App 不改用内存库，不新建空库，也不改动原文件

**假如** 打开失败的提示正在显示
**当** 点"打开数据目录"
**那么** 在访达中打开数据目录（目录不存在时打开上一级），然后再次显示提示
**并且** 点"重试"会重新走完整的打开流程，成功后继续启动；点"退出"会退出拾刻

**假如** 以 `-ShikeSimulateDatabaseOpenFailure YES` 启动
**那么** 只有第一次打开失败，原因为"模拟的错误（调试参数）"；点"重试"后走真实的流程，正常启动（02 验收第 6 条）

**假如** 以 `-ShikeDataDirectory <路径>` 启动
**那么** 数据库放在该目录中，路径中的 `~` 会被展开
**并且** 展开后仍不是绝对路径时，按"打不开"处理，原因为"数据目录路径无效"，绝不退回默认目录

**假如** 以 `-ShikeSimulateWriteFailure YES` 启动
**那么** 该值传入 `AppDatabase.Options`，所有仓储写方法都抛出 `writeFailed(.simulated)`

**假如** 在测试宿主中运行（方案为测试设置了环境变量 `SHIKE_TEST_HOST=1`）
**当** 运行 ShikeTests
**那么** AppDelegate 跳过全部启动步骤：不创建数据目录，不写入真实的偏好设置

**假如** 查看 Xcode 方案
**那么** Run 的参数中预置了三个调试参数，默认都不勾选

**假如** 运行 L2 测试
**那么** 测试覆盖：LaunchOptions 能解析三个参数、能展开 `~`、把相对路径判为无效；ErrorText 为 11 种原因都给出不为空的文案，文案与 app-shell.md 的文案表一致

**假如** 打开失败
**那么** 写入日志：打开失败写到 category `data`，提示的展示写到 `ui`；只记录错误分类和代码，不记录用户内容
**并且** 界面文案全部来自 `Localizable.xcstrings`

### Story 1.9: 菜单栏图标与面板

作为产品负责人，
我希望在菜单栏看到拾刻的图标，左键打开面板，再点一次或点击别处就收起，
以便拾刻像菜单栏应用那样随叫随到，不占 Dock。

**依据：**FR24、FR25、FR30、FR33；UX-DR1～UX-DR3、UX-DR13；app-shell.md「组件契约」中的 StatusItemController、PopoverController、PanelModel、PanelView，以及「移植清单」；conventions.md「移植（GPL）」；03 §2、§3。

**验收标准：**

**假如** 拾刻正常启动
**那么** 组装 AppEnvironment 之后创建菜单栏图标：模板图标 `note.text`，随菜单栏深浅色自动适配，辅助功能描述为"拾刻"
**并且** Dock 中没有图标（02 验收第 3 条）
**并且** 右键菜单在 1.11 提供，本故事中右键点击图标暂不响应

**假如** 面板没有打开
**当** 左键点击图标
**那么** 面板弹出，拾刻被激活（`NSApp.activate()`），面板成为关键窗口
**并且** 再次左键点击图标时，面板收起
**并且** 实测在其他 App 处于前台时面板未能成为关键窗口的，补充回退调用（如 `orderFrontRegardless()`）

**假如** 面板已打开
**当** 点击面板和图标以外的任何地方，包括其他 App 的窗口
**那么** 面板收起
**并且** 面板显示期间装有全局和本地的鼠标按下监听作为兜底，收起时移除

**假如** 面板刚刚收起
**当** 10 毫秒内的点击落在图标上
**那么** 面板不会重新弹开；连续快速点击图标，也不会出现"刚关上又弹开"

**假如** 面板弹出
**那么** 尺寸为默认的 360×520 pt，并限制在图标所在屏幕的可见区域内；背景为系统默认的弹出材质
**并且** 最小 300×360、最大 600×1000 已定义为常量，供 S1-01 使用；面板内容在启动时创建一次，之后常驻

**假如** 查看面板顶栏
**那么** 左侧是「便签｜待办」分段控件，默认为"便签"，可以切换；重启后回到"便签"，不保存到偏好设置
**并且** 顶栏没有搜索按钮和 ⋯ 按钮；AppEnvironment 创建 PanelModel，L2 测试验证模式默认为便签并能切换

**假如** 查看 PopoverController 和 StatusItemController
**那么** 两个文件都按 conventions.md 的移植规则处理：文件头带来源和修改说明，去掉单例和 EventKit，`activate(ignoringOtherApps:)` 改为 `activate()`
**并且** 两个文件都登记到 NOTICE.md 和 04 §7；在测试宿主中不创建菜单栏图标

### Story 1.10: 面板的数据与错误提示

作为产品负责人，
我希望面板按当前模式显示空状态或条数，数据读写出错时在顶栏下方看到红色提示条并可以重试，
以便面板从一开始就连着真实数据，出了错也不会悄无声息。

**依据：**FR17、FR25；UX-DR4～UX-DR6、UX-DR13；NFR14；app-shell.md「组件契约」中的 PanelModel、PanelView，以及「L2 测试清单」；failure-modes.md 中写入失败、读取失败两行；03 §3、§14。

**验收标准：**

**假如** 数据库是空的
**当** 打开面板
**那么** 便签模式显示图标 `note.text` 和"还没有便签"，待办模式显示图标 `checklist` 和"没有待办"（02 验收第 4 条）
**并且** 不显示引导句（由 S1-10 提供）

**假如** 当前模式有未删除的条目（阶段 0 没有输入界面，验收时可用 `-ShikeDataDirectory` 指向临时目录、以 sqlite3 手工插入一行后重启）
**当** 打开面板
**那么** 显示"共 N 条（列表将在阶段 1 提供）"，N 随数据变化自动更新（数据变化部分由 L2 验证）

**假如** PanelModel 已经 `start()`
**那么** 它在自己持有的 Task 中用 `for try await` 消费便签和待办两个观察流；停止或释放时取消这个 Task

**假如** 面板正在显示
**当** 调用 `report(.writeFailed(原因), retry:)`
**那么** 顶栏下方出现红色提示条"保存失败：原因"和"重试"按钮；点"重试"会调用传入的闭包（本组由 L2 验证：阶段 0 的界面没有写路径，人工验收不触发真实失败）

**假如** 观察流以 `readFailed(原因)` 结束
**那么** 提示条显示"读取失败：原因"和"重试"；点"重试"会重新订阅

**假如** 运行 L2 测试
**那么** 测试用内存库组装 AppEnvironment 并驱动 PanelModel：空库时两种列表都为空；插入一条便签后 `notes` 随之更新；调用 `report(.writeFailed(.diskFull), retry:)` 后出现"保存失败：磁盘空间不足"和"重试"，点"重试"会调用闭包；让观察流以 `readFailed(.ioError)` 结束后，出现"读取失败：读写数据文件时出错"和"重试"，点"重试"会重新订阅

**假如** `report(.writeFailed(原因), retry:)` 被调用
**那么** 写入日志：category `data`，只记录错误分类和代码，不记录用户内容

### Story 1.11: 设置窗口、右键菜单与主菜单

作为产品负责人，
我希望右键点击图标就能打开设置、查看关于、退出拾刻，而且没有可见的菜单栏时，⌘,、⌘Q 和编辑快捷键也能用，
以便拾刻的基本操作入口从阶段 0 起就齐全。

**依据：**FR26～FR28、FR33；UX-DR9、UX-DR10、UX-DR13、UX-DR14；app-shell.md「组件契约」中的 StatusItemController、StatusMenu、SettingsWindowController、SettingsTab、MainMenu，以及「移植清单」；03 §2、§9；04 §6.9。

**验收标准：**

**假如** 拾刻正在运行
**当** 右键点击菜单栏图标
**那么** 弹出菜单：设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q）
**并且** 菜单只在右键时临时挂到图标上，关闭后卸下；左键仍然开关面板

**当** 选择"设置…"或按 ⌘,
**那么** 打开设置窗口，并显示在最前面：先调用 `NSApp.activate()`，再 `makeKeyAndOrderFront`；实测不在最前面时，补充调用 `orderFrontRegardless()`
**并且** 窗口只有一个实例；已经打开时，再选"设置…"只会把它带到最前面，停在当前分页（02 验收第 5 条）

**假如** 设置窗口已打开
**那么** 顶部依次为通用、快捷键、提醒、卡片、数据、关于六个分页；前五个显示"将在阶段 N 提供"，N 依次为 1、1、2、3、4
**并且** 分页由有序的注册表定义，后续阶段只需替换对应分页的占位视图

**当** 选择"关于拾刻"
**那么** 打开设置窗口并切到关于分页；本故事中的关于页先显示图标、名称和版本

**当** 选择"退出拾刻"或按 ⌘Q
**那么** 拾刻退出（02 验收第 5 条）

**假如** 拾刻启动
**那么** 在组装 AppEnvironment 之后、创建菜单栏图标之前，建立隐藏的主菜单：应用菜单包含"设置…"（⌘,）和"退出拾刻"（⌘Q）；"编辑"菜单包含撤销（`undo:`，⌘Z）、重做（`redo:`，⇧⌘Z）、剪切（`cut:`，⌘X）、复制（`copy:`，⌘C）、粘贴（`paste:`，⌘V）、全选（`selectAll:`，⌘A），target 为 nil，由响应链处理
**并且** L2 测试确认主菜单的菜单项、选择器和快捷键，以及分页的顺序和占位阶段号

**假如** 查看 StatusMenu
**那么** 它按移植规则处理：带来源和修改说明，去掉单例和与更新相关的菜单项，并登记到 NOTICE.md 和 04 §7
**并且** 不移植 `SettingsOpenerView`，也不使用 SwiftUI 的 `Settings` 场景

### Story 1.12: 关于页与许可证

作为产品负责人，
我希望关于页完整显示版本、源码、许可证、法律声明和致谢，并且能离线查看许可证全文，
以便拾刻从第一个版本起，就满足 GPL-3.0 第 5(d) 条对交互界面的要求。

**依据：**FR29；UX-DR11～UX-DR13；app-shell.md「组件契约」中的关于页，以及「阶段 0 文案」；stack.md「project.yml 要点」中把 LICENSE 作为资源打包；06 §9。

**验收标准：**

**假如** 设置窗口已打开
**当** 切到关于分页
**那么** 依次显示：图标（`note.text`，占位）、名称"拾刻"、"版本 0.0.0（1）"（从 Info.plist 读取）、源码链接 <https://github.com/MICBIK/shike>、版权行"Copyright (C) 2026 Shike contributors"、法律声明段落、"查看许可证"按钮，以及致谢（Reminders MenuBar，GPL-3.0；GRDB.swift，MIT）
**并且** 法律声明为"拾刻是自由软件：你可以依据 GNU 通用公共许可证第 3 版（GPL-3.0-only）的条款再分发和修改它。本程序不提供任何担保。"

**当** 点击源码链接
**那么** 在默认浏览器中打开该地址

**当** 点"查看许可证"
**那么** 打开标题为"许可证"的只读文本窗口，显示随 App 打包的 LICENSE 全文
**并且** 窗口只有一个实例；断网时也能显示

**假如** 查看工程配置和 App 包
**那么** 根目录的 LICENSE 在 project.yml 中作为资源打包，仓库中不另存副本；L2 测试确认 App 包中有 LICENSE，且内容不为空
**并且** 第三方许可证全文不随 App 打包（规格的非目标）

### Story 1.13: 每日自动备份

作为产品负责人，
我希望拾刻每天自动保留一份数据备份，只留最近 7 份，而且不拖慢启动、不打扰我，
以便数据出问题时，总能找回最近几天的内容。

**依据：**FR22、FR33、FR34；NFR4、NFR8、NFR10、NFR12；data-layer.md「备份」，以及「L1 测试清单」中的备份各项；app-shell.md「组件契约」中的 BackupService；failure-modes.md 中备份失败、备份中途退出、系统时区或日期变化三行。

**验收标准：**

**假如** `Backups/` 中还没有当天的备份
**当** 调用 `backupIfNeeded(into:keep:)`
**那么** 先用 SQLite 在线备份写入临时文件 `.shike-YYYY-MM-DD.sqlite.partial`，成功后原子改名为 `shike-YYYY-MM-DD.sqlite`，返回 `.created`
**并且** 把备份文件复制到不含 -wal/-shm 的目录后重新打开，`PRAGMA journal_mode` 返回 `delete`，行数与主库一致

**假如** 数据目录存在但 `Backups/` 不存在或已被删除
**当** 备份
**那么** 先创建 `Backups/`，再照常备份

**假如** `Options.simulateWriteFailure` 为真
**当** 调用 `backupIfNeeded(into:keep:)`
**那么** 备份照常执行并返回 `.created`

**假如** 当天的备份已经存在
**当** 再次调用
**那么** 返回 `.alreadyExists`，不重复备份，但照常执行轮换

**假如** 时区为 Asia/Shanghai，当前时间为 UTC 2026-09-23 16:30
**当** 备份
**那么** 文件名为 `shike-2026-09-24.sqlite`：日期按公历和 `Options.timeZone` 计算，年月日补零，与系统的区域设置无关

**假如** 已有 8 份文件名符合 `^shike-\d{4}-\d{2}-\d{2}\.sqlite$` 的备份
**当** 以 `keep: 7` 备份
**那么** 按文件名中的日期，删除最旧的一份
**并且** 不符合该模式的文件（包括 `shike-before-*`）保持不动

**假如** 目录中残留了上次中断时的临时文件
**当** 备份
**那么** 先清理残留，再备份；备份失败时删除临时文件，抛出 `backupFailed(原因)`，主库不受影响

**假如** 拾刻启动
**那么** 在创建菜单栏图标之后，由 AppEnvironment 用数据目录和 `backup.keepCount` 创建 BackupService 并调用其 `start()`，在后台执行一次备份，保留份数取自 `backup.keepCount`（默认 7）；收到 `NSCalendarDayChanged` 时再执行一次（订阅仅转发到可直调的备份方法，L2 直接调用验证）
**并且** 启动不等待备份完成；结果和失败都只写日志（category `backup`），不打扰用户；在测试宿主中不备份

**假如** 产品负责人运行一次拾刻
**那么** 数据目录的 `Backups/` 中有当天的备份，能打开，数据与主库一致（02 验收第 7 条）

### Story 1.14: 迁移前备份

作为产品负责人，
我希望拾刻在升级数据库结构之前自动留一份备份，备份失败就不升级，
以便阶段 2 起的结构迁移即使出了问题，我的数据也能找回。

**依据：**FR19、FR23；NFR4；data-layer.md「迁移前备份（ADR-018）」，以及「L1 测试清单」中的迁移前备份各项；failure-modes.md 中迁移前备份失败一行。

**验收标准：**

**假如** 一个已经执行过 `v1` 的库，测试在 v1 之后追加了测试专用的迁移 `v2-test`
**当** 调用 `open`
**那么** 执行迁移之前，`Backups/` 中已经生成 `shike-before-v2-test-YYYY-MM-DD.sqlite`，内容与迁移前的库一致；随后迁移正常执行
**并且** 写入方式与每日备份相同：先写临时文件，再原子改名

**假如** 备份目录不可写
**当** 调用 `open`
**那么** 抛出 `openFailed(原因)`，不执行迁移，库仍然停留在 v1
**并且** App 按"打不开"处理，显示打开失败的提示

**假如** 数据目录存在但 `Backups/` 不存在
**当** 需要生成迁移前备份
**那么** 先创建 `Backups/`，再照常备份

**假如** 新建的空库
**当** 调用 `open`
**那么** 不生成迁移前备份

**假如** 同一天、同一迁移已经有备份
**那么** 不再重复生成
**并且** 这类文件不参与每日轮换，也不会被自动删除；生产代码只注册正式迁移

### Story 1.15: 识别中文日期与时刻

作为阶段 2 的负责人，
我希望有一个严格按 05 实现、经过全量测试的中文日期解析器，
以便待办的时间识别（S2-01）直接调用它，结果与用户的系统设置无关。

**依据：**FR5、FR6、FR8；NFR8、NFR12、NFR14；parser.md（全文）；05 §1～§6、§9.1～§9.9。

**验收标准：**

**假如** 旧项目的解析器位于 `../TZMemo/Packages/TZMemoDateParser/Sources/TZMemoDateParser/`
**当** 把它迁入 ShikeDateParser
**那么** 先原样复制到 `Packages/ShikeKit/Sources/ShikeDateParser/`，改名并加上文件头，单独提交一次；之后的修改放在后续提交中
**并且** 不迁入 `parser-check`；旧的断言与 05 冲突时，一律以 05 为准

**假如** 迁入完成
**那么** 公开 API 为 `ChineseDateParser`（`struct`、`Sendable`、`init(timeZone:)`、`parse(_:now:)`）和 `DateParseResult`（`date`、`hasTime`，以及按位置排序、互不重叠的 UTF-16 `matchedRanges`）；没有识别到时间时返回 nil

**假如** 05 §9.1～§9.9 的 98 个用例
**当** 运行 ShikeDateParserTests
**那么** 每个用例都有同编号的参数化测试（时区为 Asia/Shanghai，基准时间按 05 的约定），并全部通过
**并且** parser.md 行为差异表中的每一项都已按 05 修正，"当天"不再识别

**假如** 查看解析器的实现
**那么** 内部固定使用公历、以周一为一周之首，时区只取 `init` 的参数；源码中没有 `Calendar.current`、`Locale.current`、`autoupdatingCurrent`，CI 检查通过
**并且** 正则预编译为 `static let` 形式的 `NSRegularExpression`，解析时不编译正则；日期用 `DateComponents` 构造后回读校验

### Story 1.16: 排除误识别、高亮与标题清理

作为阶段 2 的负责人，
我希望解析器不误识别容易混淆的说法，给出准确的高亮区间，能从原文得到干净的待办标题，而且 05 与测试一旦不同步，CI 就会失败，
以便待办的时间识别可靠，05 始终是解析规则的唯一来源。

**依据：**FR5、FR7、FR8；parser.md「公开 API」「测试组织」；05 §6、§7、§9.10～§9.13；Issue #2。

**验收标准：**

**假如** 05 §9.10、§9.11 的用例（J01～J13、K01）
**当** 运行测试
**那么** J 组按 §6 的规则排除误识别，全部返回 nil，其中包括非法日期和越界的时刻；K01 只识别日期部分

**假如** 05 §9.12 的用例（L01～L05）
**当** 运行测试
**那么** `matchedRanges` 与期望的 UTF-16（起始位置, 长度）逐一相等，按位置排序、互不重叠

**假如** 05 §9.13 的用例（M01～M08）
**当** 用解析得到的区间调用 `TitleCleaner.clean(_:removing:)`
**那么** 得到期望的标题
**并且** 清理严格按 05 §7 原文的五个步骤执行；步骤顺序是否修订由 Issue #2 跟踪，本故事不改

**假如** 守护测试从 `#filePath` 出发，找到仓库中的 `docs/05-中文日期解析规格.md`
**当** 提取 §9 各表每一行的（编号, 输入），与测试数据中的（编号, 输入）比较
**那么** 两者的对称差为空；任何一边增加、删除或修改用例而另一边没有同步时，测试失败
**并且** 05 的全部 125 个用例都有测试，并全部通过

### Story 1.17: 架构交接

作为接手后续阶段的负责人，
我希望只读 docs/ 就能按统一的方式扩展拾刻，文档中的命令和事实都与 CI 实测一致，
以便不必回头翻阶段 0 的规格和对话，就能从阶段 1 的第一个故事开工。

**依据：**FR37；conventions.md（全文）；scope-boundaries.md；06 §7。

**验收标准：**

**假如** 阶段 0 的其余故事都已实现
**当** 查看 04
**那么** 04 已写回经过实现验证的契约：模块与目录、ShikeData 的公开 API、错误分类、观察语义、备份与迁移前备份、组装点、启动流程、调试参数，以及 §7 的移植清单
**并且** 04 新增"扩展指南"一节，为以下每一项给出步骤和示例位置：新增仓储方法、偏好键、设置分页、界面文案、服务、调试参数、移植文件、数据库迁移

**假如** 阶段 0 的其余故事都已实现
**当** 查看 06 和 07
**那么** conventions.md 中的约定已并入 docs，规格的伴随文件不再是唯一来源
**并且** 07 为阶段 0 的重大取舍新增了 ADR，例如公开类型与内部 Record 分离、只在 CI 开启"警告即错误"

**当** 核对 06、NOTICE.md、README 和 CLAUDE.md
**那么** 其中的命令和事实都与 CI 实测一致，例如 CLAUDE.md 的"常用命令"不再标注"阶段 0 完成后可用"
**并且** 02 中阶段 0 的状态保持"进行中"，由第 ⑧ 步在验收通过后更新

**假如** 第 ⑥ 步人工验收已经完成
**当** 写回 02 时核对其中阶段 0 的第 1 条验收（"GitHub 上 main 分支的 CI 显示通过"）
**那么** 该条改为两段式表述：合并前以 `stage-0/foundation` 上 CI 三项全绿且 main 分支保护已开启为准；合并到 main 后由 main 的首次 CI 复核通过

**假如** 一份新克隆的仓库
**当** 按 README 的步骤操作
**那么** 能生成工程、构建 App，并通过全部测试
