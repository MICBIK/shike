# 编码约定（适用于所有负责人和所有阶段）

本文只写 06 中没有的约定和细化；与 06 重复的部分以 06 为准。阶段 0 收尾时并入 docs（CAP-13）。

## 组装与依赖

- AppEnvironment 负责组装 AppDatabase、仓储、Preferences、各项服务和界面模型；AppDelegate 只负责生命周期，以及用 AppEnvironment 创建界面控制器。
- 不写 `static let shared` 或 `static var shared`；对象都通过 `init` 注入。移植代码里的单例（demo 的 `AppDelegate.shared`、`RightClickMenuHelper.shared` 等）一律改掉。
- 接入新服务的步骤：在 `Services/` 中新建类型 → 在 AppEnvironment 中组装 → 按 04 §6.1 的顺序在 AppDelegate 中启动 → 在 L2 测试中验证它能用内存库组装。

## 并发

- 界面类型、控制器和 `@Observable` 模型都显式标注 `@MainActor`；不启用"默认 MainActor 隔离"构建设置，这样 App 与 ShikeKit 的规则一致，移植和阅读时不会误判。
- ShikeKit 的公开类型是 `Sendable` 值类型；仓储是 `Sendable` 结构体。
- 界面模型在自己持有的 `Task` 中用 `for try await` 消费观察流；停止或释放时取消该 `Task`。
- 系统回调（NSEvent 监听、通知）只有在确定位于主线程时才用 `MainActor.assumeIsolated`，否则先切到主线程。

## 错误

- 仓储只抛出 `ShikeDataError`（data-layer.md）；App 用 `ErrorText` 把原因映射成文案，同时写日志。
- 写入和文件操作的失败不得用 `try?` 丢弃。确实可以忽略时，要写注释说明为什么可以忽略。
- 捕获错误后不走"降级"路径：不改用内存库，不用空数据或默认值覆盖用户数据。

## 文案

- 语义键采用 `区域.对象.含义` 的形式，如 `panel.empty.note.title`；值为简体中文；通过生成的符号访问，例如 `String(localized: .panelEmptyNoteTitle)`。
- 风格遵循 03 §15：称呼用"你"，按钮用动词，不用感叹号。
- 除注释和日志外，代码中不出现面向用户的中文字面量。

## 偏好设置与调试启动参数

- 偏好键集中在 `Preferences.Key`，名称与 04 §5.5 一致；默认值在同一处注册；新的键随所属能力在对应阶段加入，并同步更新 04 §5.5。
- `Preferences` 接收一个 `UserDefaults` 实例；测试使用独立的 suite，并在结束时清除。
- 调试启动参数定义在 `LaunchOptions` 中，格式为 `-Shike<名称> <值>`，登记到 06 §11，并在 XcodeGen 方案中预置为默认不勾选。
- 验收或调试可能损坏数据的场景时，用 `-ShikeDataDirectory` 指定一个临时目录，不要直接使用产品负责人的真实数据目录。

## 日志

- 使用 `Logger(subsystem: "io.github.micbik.shike", category:)`，category 只取 `app`、`data`、`backup`、`ui` 之一；需要新的类别时，先在 `Support/Log.swift` 中定义。
- 不记录便签和待办的内容；错误分类和错误代码用 `.public`，路径等其余信息保持默认的隐私级别。

## 测试

- 基准时间 T0 = 2026-09-23 12:00，时区 Asia/Shanghai，通过 `now` 参数或注入的时钟传入。数据库时间戳的精度是毫秒，因此基准取整秒。
- 一般测试用内存库；备份和打开失败的测试用临时目录中的磁盘库，测试结束后删除。
- L2 测试用内存库和独立的 UserDefaults 组装 AppEnvironment，不打开任何窗口。
- 测试标题用中文描述行为；解析用例以 05 的编号作为参数标识。

## 数据库迁移（阶段 2 起适用）

- 新迁移按 `v2`、`v3`…… 命名，只追加，不修改已有的迁移。
- 每个迁移配两类测试：空库迁移到最新版本；上一版本的库迁移到最新版本（以上一版本迁移生成的库作为夹具）。
- 表结构变化同步到 04 §5；重大取舍新增 ADR。

## 移植（GPL）

- 按 06 §9 加文件头和修改说明，并登记到 NOTICE 和 04 §7。移植基线为 demo 提交 `e3c0260a8630381224e80f5f0e0c6700f2e417aa`（2026-09-19），记录在 NOTICE 中。
- 凡是照搬或改写 demo 代码的文件都算移植，只取其中一部分函数也算。
- 移植时要去掉 EventKit 与授权流程、App Store 分支、全局单例和已废弃的 API（例如 `NSApp.activate(ignoringOtherApps:)` 改为 `NSApp.activate()`）；尺寸和文案以 03 为准。

## 目录与文件

- 目录按 04 §2 组织；一个文件放一个主要类型；只创建当前阶段用到的目录和文件。
- 每个 `.swift`、`.sh` 文件都以 06 §9 的文件头开始（`.sh` 用 `#` 注释，放在 shebang 之后）；Package.swift 的第一行必须是 `swift-tools-version`，文件头放在第二行之后。

## 检查项（CI `checks` 作业）

1. **文件头：**`Shike/`、`ShikeTests/`、`Packages/ShikeKit/`、`scripts/` 中每个 `.swift`、`.sh` 文件的前 5 行都包含 `SPDX-License-Identifier: GPL-3.0-only`；凡是含有"源自 Reminders MenuBar"的文件，其路径都要出现在 NOTICE.md 中。
2. **导入边界：**
   - `Packages/ShikeKit/` 中不出现对 AppKit、SwiftUI、Cocoa、UIKit、Carbon 的 import，包括带 `@testable` 或访问级别修饰的写法。
   - `Shike/`、`ShikeTests/` 中不出现 `import GRDB`。
   - `Sources/ShikeData/` 只能用 `internal import GRDB`。
   - `Sources/ShikeDateParser/` 只 import Foundation。
3. **解析器区域：**`Sources/ShikeDateParser/` 中不出现 `Calendar.current`、`Locale.current`、`autoupdatingCurrent`。
4. **禁用项：**Swift 源码中不出现 `eraseDatabaseOnSchemaChange`；`Shike/` 中不出现 `static let shared` 或 `static var shared`。

## 禁止清单（速查）

- 在 App 中 `import GRDB`；在 ShikeKit 中引入 AppKit 或 SwiftUI；在 ShikeData 中用 `public import GRDB` 或不带修饰的 `import GRDB`。
- 使用 `eraseDatabaseOnSchemaChange`；修改已发布的迁移；数据库打不开时降级处理。
- 在解析器中读取系统的日历或区域设置。
- 把 Swift `Regex` 作为 `static` 常量。它不是 `Sendable`，在 Swift 6 下编译失败（已实测），应改用 `NSRegularExpression`。
- 在 xcodebuild 命令行直接传 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`（stack.md）。
- 用 `try?` 丢弃写入或文件操作的失败；使用全局单例。
