# App 外壳：组件契约与阶段 0 界面（S0-02、S0-05、S0-06）

交互规格以 03 §2、§3、§9、§14、§15 为准。本文规定阶段 0 各组件的职责、行为细节、文案和移植清单。

## 文件布局（阶段 0）

| 路径 | 职责 |
|---|---|
| `Shike/App/main.swift` | 创建 `NSApplication`，然后 `run()`；`AppDelegate` 由全局常量强引用，因为 `delegate` 属性是弱引用 |
| `Shike/App/AppDelegate.swift` | 执行启动流程（architecture-diagrams.md §3）；检测到测试宿主时直接返回；创建界面控制器 |
| `Shike/App/AppEnvironment.swift` | 唯一的组装点：AppDatabase、三个仓储、Preferences、BackupService、PanelModel |
| `Shike/App/LaunchOptions.swift` | 从参数域读取调试启动参数 |
| `Shike/App/MainMenu.swift` | 构建隐藏的主菜单 |
| `Shike/App/DatabaseOpenFailureAlert.swift` | 打开失败提示的循环（failure-modes.md） |
| `Shike/MenuBar/StatusItemController.swift` | 菜单栏图标，左右键分派（移植） |
| `Shike/MenuBar/PopoverController.swift` | 面板的显示与收起（移植） |
| `Shike/MenuBar/StatusMenu.swift` | 右键菜单（移植） |
| `Shike/Panel/PanelView.swift`、`PanelModel.swift`、`EmptyStateView.swift`、`Banner.swift` | 面板内容 |
| `Shike/Settings/SettingsWindowController.swift`、`SettingsTab.swift`、`SettingsView.swift`、`AboutSettingsView.swift`、`PlaceholderSettingsView.swift`、`LicenseWindowController.swift` | 设置窗口；许可证窗口 |
| `Shike/Services/Preferences.swift`、`BackupService.swift` | 服务 |
| `Shike/Support/Log.swift`、`ErrorText.swift` | 日志分类；错误原因到文案的映射 |
| `Shike/Resources/Localizable.xcstrings` | 资源（文案目录）。阶段 0 的图标全部用 SF Symbol，不建 Assets.xcassets；正式图标定稿时（阶段 4）再创建（1.17 修订：原列为 `Assets.xcassets、Localizable.xcstrings`，资产目录无故事认领且阶段 0 用不到） |
| 仓库根目录的 `LICENSE` | 在 project.yml 中作为资源打包，不复制副本 |
| `ShikeTests/…` | L2 测试（见本文末节） |

## 组件契约

- **测试宿主：**环境变量为 `SHIKE_TEST_HOST=1` 时，AppDelegate 什么都不做：不打开库，不建菜单栏图标，不做备份（CAP-11）。
- **AppEnvironment**（`@MainActor`）：`init(database:preferences:dataDirectory:)`，由它创建仓储、BackupService 和 PanelModel；BackupService 使用 `dataDirectory` 下的 `Backups/` 与 `backup.keepCount`。它不创建任何窗口，也不创建菜单栏图标，所以 L2 测试可以直接组装它（测试传入临时目录）。
- **LaunchOptions：**
  - `simulateDatabaseOpenFailure` ← `-ShikeSimulateDatabaseOpenFailure YES`（只让第一次打开失败）。
  - `simulateWriteFailure` ← `-ShikeSimulateWriteFailure YES`，传给 `AppDatabase.Options`。
  - `dataDirectory` ← `-ShikeDataDirectory <路径>`。先展开 `~`，结果不是绝对路径时视为无效：走打开失败提示，原因为 `invalidLocation`，绝不退回默认目录。数据库和 `Backups/` 都放在这个目录下。
  - 默认数据目录为 `~/Library/Application Support/Shike/`。
- **Preferences：**`init(defaults: UserDefaults)`；`Key` 中只有 `backup.keepCount`（默认 7）。
- **StatusItemController：**
  - 图标为 `NSImage(systemSymbolName: "note.text", accessibilityDescription: 拾刻)`，模板图像。
  - `sendAction(on: [.leftMouseUp, .rightMouseUp])`：左键开关面板；右键时临时挂上 StatusMenu，执行 `performClick`，然后卸下（04 §6.2）。
- **PopoverController：**
  - `NSPopover`，`behavior = .transient`，`animates = false`。
  - 内容是启动时创建一次、之后常驻的 `NSHostingController(PanelView)`（04 §10）。
  - 显示时先 `NSApp.activate()`，再让面板窗口成为关键窗口。
  - 收起后 10 毫秒内的点击不再打开面板（防刚关又开）。
  - 显示期间安装全局和本地的鼠标按下监听，点在面板和图标之外就关闭面板；关闭时移除监听。
  - 尺寸为默认的 360×520，限制在图标所在屏幕的可见区域内。最小 300×360、最大 600×1000 这两个常量现在就定义好，供 S1-01 使用。
- **StatusMenu：**
  - 菜单项依次为：设置…（⌘,）、关于拾刻、分隔线、退出拾刻（⌘Q）。
  - "设置…"打开设置窗口，停在当前分页；"关于拾刻"打开设置窗口并切到关于分页。
- **PanelModel**（`@MainActor`、`@Observable`）：
  - 状态有 `mode`（`.note` 或 `.todo`，默认为 `.note`）、`notes`、`todos`、`banner`。
  - `start()` 订阅两类观察。
  - `report(_ error: ShikeDataError, retry:)` 生成提示条；读取失败时，"重试"会重新订阅。
- **PanelView：**
  - 顶栏只有分段控件「便签｜待办」；提示条位于顶栏下方（03 §3）。
  - 当前模式的列表为空时显示空状态：便签用图标 `note.text` 和"还没有便签"，待办用图标 `checklist` 和"没有待办"。
  - 列表不为空时，只显示条数占位。
- **SettingsWindowController：**
  - 单实例，持有 `NSWindow` 和 `NSHostingController`。
  - 打开时先 `NSApp.activate()`，再 `makeKeyAndOrderFront`（04 §6.9）。如果实测窗口不在最前面，补充调用 `orderFrontRegardless()`。
- **SettingsTab：**有序的注册表，依次为通用、快捷键、提醒、卡片、数据、关于。前五个是占位分页，显示的阶段号依次为 1、1、2、3、4；关于页没有占位。后续阶段只需把对应分页的占位视图换掉。
- **关于页：**
  - 图标用 SF Symbol `note.text`（占位，正式图标在阶段 4）；名称"拾刻"；版本"版本 0.0.0（1）"，从 Info.plist 读取。
  - 源码链接 <https://github.com/MICBIK/shike>。
  - 法律声明（GPL-3.0 第 5(d) 条）包括版权行和声明段，文字见下方文案表。
  - "查看许可证"按钮打开 LicenseWindowController：一个单实例的只读文本窗口，显示随 App 打包的 LICENSE，断网时也能查看。
  - 致谢：Reminders MenuBar（GPL-3.0）、GRDB.swift（MIT）。第三方许可证全文暂不打包（SPEC 非目标）。
- **MainMenu：**
  - 应用菜单：设置…（⌘,）、退出拾刻（⌘Q）。
  - 编辑菜单：撤销（`undo:`，⌘Z）、重做（`redo:`，⇧⌘Z）、剪切（`cut:`，⌘X）、复制（`copy:`，⌘C）、粘贴（`paste:`，⌘V）、全选（`selectAll:`，⌘A）。这些菜单项的 target 都为 nil，由响应链处理。
- **BackupService：**
  - `start()` 在后台执行一次 `backupIfNeeded(to: 数据目录/Backups, keep: preferences.backupKeepCount)`，并订阅 `NSCalendarDayChanged`，跨天时再执行一次。（1.17 修订：参数标签按实现 `to:keep:` 更正，原为 `into:`）
  - 结果和失败都写入日志（category `backup`）。
- **ErrorText：**把 `DataFailureReason` 映射为文案。

## 阶段 0 文案（写入 Localizable.xcstrings）

| 键 | 文案 |
|---|---|
| `app.name` | 拾刻 |
| `menu.settings` / `menu.about` / `menu.quit` | 设置… / 关于拾刻 / 退出拾刻 |
| `mainMenu.edit`，以及 `mainMenu.undo`、`redo`、`cut`、`copy`、`paste`、`selectAll` | 编辑；撤销、重做、剪切、复制、粘贴、全选 |
| `panel.mode.note` / `panel.mode.todo` | 便签 / 待办 |
| `panel.empty.note.title` / `panel.empty.todo.title` | 还没有便签 / 没有待办 |
| `panel.placeholder.count` | 共 %lld 条（列表将在阶段 1 提供） |
| `banner.saveFailed` / `banner.loadFailed` / `banner.retry` | 保存失败：%@ / 读取失败：%@ / 重试 |
| `dbAlert.title` | 拾刻无法打开数据文件 |
| `dbAlert.retry` / `dbAlert.openFolder` / `dbAlert.quit` | 重试 / 打开数据目录 / 退出 |
| `error.reason.diskFull` | 磁盘空间不足 |
| `error.reason.readOnly` | 数据文件是只读的 |
| `error.reason.permissionDenied` | 没有访问数据目录的权限 |
| `error.reason.corrupted` | 数据文件已损坏 |
| `error.reason.busy` | 数据文件正被占用，请稍后重试 |
| `error.reason.newerSchema` | 数据文件来自更新版本的拾刻 |
| `error.reason.ioError` | 读写数据文件时出错 |
| `error.reason.constraintViolation` | 数据不符合约束（程序错误） |
| `error.reason.invalidLocation` | 数据目录路径无效 |
| `error.reason.simulated` | 模拟的错误（调试参数） |
| `error.reason.unknown` | 未知错误（代码 %d） |
| `settings.tab.general` … `settings.tab.about` | 通用、快捷键、提醒、卡片、数据、关于 |
| `settings.placeholder` | 将在阶段 %lld 提供 |
| `about.version` / `about.source` / `about.acknowledgments` | 版本 %1$@（%2$@） / 源码 / 致谢 |
| `about.copyright` | Copyright (C) 2026 Shike contributors |
| `about.legalNotice` | 拾刻是自由软件：你可以依据 GNU 通用公共许可证第 3 版（GPL-3.0-only）的条款再分发和修改它。本程序不提供任何担保。 |
| `about.viewLicense` / `license.window.title` | 查看许可证 / 许可证 |

## 移植清单（阶段 0）

来源为 `../TZMemo/demo/reminders-menubar/`，基线提交为 `e3c0260`。每个文件都按 conventions.md 的"移植"一节处理，并登记到 NOTICE 和 04 §7。

| 拾刻文件 | demo 来源 | 主要修改 |
|---|---|---|
| `MenuBar/PopoverController.swift` | `AppDelegate.swift` 中与面板有关的部分（togglePopover、外部点击监听、didClose/didShow）；`MainPopoverSizing.swift` | 拆成独立的控制器；去掉 EventKit 授权；尺寸改为 03 §3 的规定；`activate(ignoringOtherApps:)` 改为 `activate()`；去掉单例 |
| `MenuBar/StatusItemController.swift` | `AppDelegate.swift` 中与菜单栏按钮有关的部分（configureMenuBarButton、handleStatusBarButtonAction、showRightClickMenu） | 去掉计数和预览；图标改为 `note.text`；在 04 §7 补登一行 |
| `MenuBar/StatusMenu.swift` | `Services/RightClickMenuHelper.swift` | 菜单项换成阶段 0 的三项；去掉单例和与更新相关的菜单项 |

不移植 `SettingsOpenerView.swift`，也不用 SwiftUI 的 `Settings` 场景（04 §6.9）。

## L2 测试清单（ShikeTests）

- Preferences：默认值和读写，使用独立的 suite。
- LaunchOptions：三个参数都能解析；`-ShikeDataDirectory` 能展开 `~`，相对路径判为无效。
- MainMenu：菜单项、选择器和快捷键。
- SettingsTab：分页顺序和占位阶段号。
- ErrorText：每个原因都有不为空的文案。
- 关于页的资源：App 包中有 LICENSE，并且内容不为空。
- 用内存库组装 AppEnvironment，验证以下几点：
  - PanelModel 能切换模式；
  - 空库时两种模式的列表都为空；
  - 插入一条便签后 `notes` 随之更新，证明从写入到观察的链路是通的；
  - 调用 `report(.writeFailed(.diskFull), retry:)` 后，出现"保存失败：磁盘空间不足"提示条和"重试"，点"重试"会调用传入的闭包。
  - 让观察流以 `readFailed(.ioError)` 结束后，出现"读取失败：读写数据文件时出错"提示条和"重试"，点"重试"会重新订阅。
