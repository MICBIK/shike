# ShikeData：契约（S0-04、S0-05）

表结构以 04 §5 为准。本文规定公开 API、04 中没有写到的结构细节、各操作的语义、错误分类和备份。以下签名表达的是契约的意图；实现时可以做不改变语义的调整，但要同步本文件，收尾时写回 04。

## 公开类型

```swift
public struct Note: Sendable, Equatable, Identifiable {
    public struct ID: Hashable, Sendable { public let rawValue: Int64 }
    public let id: ID
    public let uuid: UUID
    public var content: String
    public var pinnedAt: Date?          // 非空即置顶
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?         // 非空即在"最近删除"中
}
public struct NoteListItem: Sendable, Equatable, Identifiable { public let note: Note; public let isPinnedToDesktop: Bool }

public struct Todo: Sendable, Equatable, Identifiable {
    public struct ID: Hashable, Sendable { public let rawValue: Int64 }
    public let id: ID
    public let uuid: UUID
    public var title: String
    public var due: TodoDue?            // 对应 dueAt + dueHasTime
    public var snoozedUntil: Date?
    public var completedAt: Date?
    public let createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?
}
public struct TodoDue: Sendable, Equatable { public var date: Date; public var hasTime: Bool }

public struct StickyCard: Sendable, Equatable {        // 以所属便签为键：一张便签最多一张卡片
    public let noteID: Note.ID
    public var frame: CardFrame                        // AppKit 屏幕坐标，原点在左下角
    public var options: StickyCardOptions
    public let createdAt: Date
    public var updatedAt: Date
}
public struct CardFrame: Sendable, Equatable { public var x, y, width, height: Double }
public struct StickyCardOptions: Sendable, Equatable {
    public var level: CardLevel            // floating / normal / desktop
    public var color: CardColor            // yellow / green / blue / pink / purple / gray
    public var fontSize: CardFontSize      // small / medium / large
    public var autoHide: Bool
    public var hideDelay: TimeInterval     // 大于 0
    public var hiddenOpacity: Double       // 在类型内钳制到 0.0～0.6
    public var allSpaces: Bool
    public var showOverFullScreen: Bool
}
public struct VisibleCard: Sendable, Equatable { public let card: StickyCard; public let note: Note }
```

## AppDatabase

```swift
public final class AppDatabase: Sendable {
    public struct Options: Sendable {
        public var timeZone: TimeZone = .current          // 用于全天规范化和备份命名
        public var clock: @Sendable () -> Date = { Date() }
        public var simulateWriteFailure = false           // 对应 -ShikeSimulateWriteFailure
    }
    public static let fileName = "shike.sqlite"
    public static func open(directory: URL, options: Options = .init()) throws -> AppDatabase  // 同步执行，启动时需要立即知道成败
    public static func inMemory(options: Options = .init()) throws -> AppDatabase             // 供测试和 SwiftUI 预览使用
    public func backupIfNeeded(into directory: URL, keep: Int) async throws -> BackupOutcome
}
```

- 数据目录由 App 传入，默认为 `~/Library/Application Support/Shike/`；`-ShikeDataDirectory` 可以覆盖它（app-shell.md）。`open` 依次执行以下步骤，任何一步失败都抛出 `openFailed(原因)`，不会创建替代库：
  1. 校验 `directory` 是绝对路径的文件 URL，否则原因为 `invalidLocation`。
  2. 创建目录。
  3. 以 `DatabasePool`（WAL）打开数据库。
  4. 调用 `hasBeenSuperseded` 检查。结果为真说明库来自更新的版本，此时失败，不写入。
  5. 库中已有迁移、又有待执行的迁移时，先做迁移前备份（见下文）。
  6. 在事务中执行迁移。
- `inMemory` 使用 `DatabaseQueue`，执行同样的迁移。
- `clock` 通过 GRDB 的 `Configuration.transactionClock` 注入；所有时间戳都取自 `try db.transactionDate`，所以同一事务内的时间相同，测试结果确定（已实测）。
- `import Foundation` 必须显式写出。`internal import GRDB` 之后，Foundation 不再随 GRDB 一起可见（已实测）。

## 结构细节（补充 04 §5）

- 迁移标识为 `v1`，整个迁移在一个事务中完成。
- 索引名：`note_on_deletedAt`、`todo_on_deletedAt`、`todo_on_completedAt_dueAt`。
- `stickyCard.noteId` 设置 UNIQUE，外键指向 `note(id)`，`ON DELETE CASCADE`。GRDB 默认开启外键，保持默认即可。
- CHECK 只有 04 规定的 `dueHasTime = 0 OR dueAt IS NOT NULL`。枚举值和取值范围由 Swift 类型保证，不加 SQL CHECK：SQLite 修改 CHECK 需要重建表，而迁移只允许追加。
- **uuid：**以 TEXT 存储 36 位小写字符串。内部 Record 类型必须实现**静态函数** `static func databaseUUIDEncodingStrategy(for column: String) -> DatabaseUUIDEncodingStrategy { .lowercaseString }`。如果误写成静态属性，GRDB 会静默忽略，uuid 变成 16 字节的 BLOB，也就是 ADR-006 记录的旧缺陷（已实测）。必须有测试断言 `typeof(uuid) = 'text'`，并且值匹配 `^[0-9a-f-]{36}$`。
- 时间使用 GRDB 默认的 UTC 文本格式（`YYYY-MM-DD HH:MM:SS.SSS`，精度为毫秒）；布尔值存为 0/1。
- 公开模型与内部 Record 类型分离：公开类型不能遵循从 `internal import` 引入的协议（已实测，编译报错），所以由内部 Record 类型负责与数据库之间的编解码。

## 仓储

三个仓储都是 `Sendable` 结构体，通过 `init(database: AppDatabase)` 创建。写方法都是 `async throws`，只抛出 `ShikeDataError`。`create` 和 `pin` 返回新建的模型，其余写方法不返回值，界面通过观察拿到结果。对不存在的记录执行操作时，抛出 `notFound`。

| 仓储 · 方法 | 写入 | updatedAt（ADR-017） |
|---|---|---|
| Note · `create(content:)` | 新 uuid；createdAt = updatedAt = 当前时间；内容可以为空，空内容如何处理由界面决定（S1-04/S1-05） | 设为当前时间 |
| Note · `updateContent(_:to:)` | content；已软删除的便签也可以更新，避免自动保存与删除同时发生时报错 | 更新 |
| Note · `setPinned(_:_:)` | pinnedAt 设为当前时间或 nil；已经是目标状态时不改动 | 不变 |
| Note/Todo · `softDelete(_:)` | deletedAt 设为当前时间；已删除的保留原来的 deletedAt | 不变 |
| Note/Todo · `restore(_:)` | deletedAt 设为 nil | 不变 |
| Note/Todo · `permanentlyDelete(_:)` | 删除该行；便签的卡片级联删除 | — |
| Todo · `create(title:due:)` | 新 uuid；due 规范化（见下） | 设为当前时间 |
| Todo · `updateTitle(_:to:)` | title | 更新 |
| Todo · `setDue(_:_:)` | dueAt、dueHasTime；snoozedUntil 设为 nil | 更新 |
| Todo · `setCompleted(_:_:)` | 完成：completedAt 设为当前时间，snoozedUntil 设为 nil；取消完成：completedAt 设为 nil；已是目标状态时不改动；软删除的行不受影响（回收站行不被迟到的完成/取消写改动，C3 修复 2026-10-03） | 更新 |
| Todo · `snooze(_:until:)` | snoozedUntil；软删除的行抛 `notFound`（C3 家族防御 2026-10-03，通知路径经 uuid 包装前置检查不受影响） | 更新 |
| Card · `pin(_:frame:options:)` | 新建卡片；便签已钉时返回现有卡片，不做改动；便签不存在或已软删除时抛出 `notFound` | 卡片的 createdAt = updatedAt = 当前时间 |
| Card · `updateFrame(_:_:)`、`updateOptions(_:_:)` | 对应的列 | 更新卡片的 updatedAt |
| Card · `unpin(_:)` | 删除卡片行，便签不变 | — |

- **全天规范化：**`hasTime` 为否时，dueAt 存为 `Options.timeZone` 中该日的 00:00；为是时原样保存。
- **updatedAt 的含义：**内容最近一次被修改的时间，也就是列表中显示的"修改时间"。所以删除、恢复、置顶都不改变它，撤销删除后便签回到原位（S1 验收）。
- **模拟写入失败：**`simulateWriteFailure` 开启时，上表所有写方法都不访问数据库，直接抛出 `writeFailed(.simulated)`；迁移、观察和备份不受影响。

## 观察

| 方法 | 内容 | 顺序 |
|---|---|---|
| `NoteRepository.observeActive()` | 未删除的便签，附带"是否存在卡片" | updatedAt 降序，id 降序 |
| `TodoRepository.observeActive()` | 未删除的待办（包括已完成的） | createdAt 降序，id 降序 |
| `StickyCardRepository.observeVisible()` | 所属便签未删除的卡片，附带该便签 | createdAt 升序，id 升序 |

- 返回类型为 `AsyncThrowingStream<[…], any Error>`，内部用 GRDB 的 `ValueObservation` 实现，并去掉重复值。订阅后先推送当前值，之后每次提交且影响到相关表时再推送；读取失败时，流以 `readFailed(原因)` 结束；取消消费的 `Task` 即停止观察。
- 置顶分组和已完成分组的排列由 S1-05/S1-06 决定，阶段 0 的顺序只是为了结果确定。

## 错误分类

```swift
public enum ShikeDataError: Error, Sendable, Equatable {
    case notFound
    case openFailed(DataFailureReason)
    case readFailed(DataFailureReason)
    case writeFailed(DataFailureReason)
    case backupFailed(DataFailureReason)
}
```

| DataFailureReason | 来源 |
|---|---|
| `diskFull` | SQLITE_FULL |
| `readOnly` | SQLITE_READONLY |
| `permissionDenied` | SQLITE_PERM、SQLITE_AUTH；创建或访问目录时的权限错误 |
| `corrupted` | SQLITE_CORRUPT、SQLITE_NOTADB |
| `busy` | SQLITE_BUSY、SQLITE_LOCKED |
| `newerSchema` | `hasBeenSuperseded` 为真 |
| `ioError` | SQLITE_IOERR、SQLITE_CANTOPEN，以及其他文件系统错误 |
| `constraintViolation` | SQLITE_CONSTRAINT（出现即说明程序有缺陷） |
| `invalidLocation` | 数据目录不是绝对路径的文件 URL（如 `-ShikeDataDirectory` 写错） |
| `simulated` | 调试启动参数触发 |
| `unknown(code: Int32)` | 其他 SQLite 主结果码 |

以上按 SQLite 的主结果码分类。App 负责把分类映射成中文文案（app-shell.md）。

## 备份

- 文件名为 `shike-YYYY-MM-DD.sqlite`，日期由公历和 `Options.timeZone` 算出，年月日补零，与系统的区域和日历设置无关。
- 当天的文件已经存在时，返回 `.alreadyExists`，仍然执行轮换。否则先确保 `Backups/` 存在（不存在时先创建），再删除残留的临时文件，用 SQLite 在线备份把数据写入临时文件 `.shike-YYYY-MM-DD.sqlite.partial`；成功后对目标库执行 `PRAGMA journal_mode=DELETE`（在线备份会复制源库的 WAL 页头，不做这一步目标文件仍依赖 WAL），然后原子改名为正式文件名；失败时删除临时文件，并抛出 `backupFailed(原因)`。
- 轮换：只处理文件名符合 `^shike-\d{4}-\d{2}-\d{2}\.sqlite$` 的文件；按文件名中的日期保留最新的 `keep` 份（`keep` 至少为 1），删除其余的；其他文件不动。
- 返回值 `BackupOutcome` 为 `.created(URL, removed: [URL])` 或 `.alreadyExists(URL, removed: [URL])`。
- 备份文件是可以独立打开的单个 SQLite 文件（目标库不使用 WAL）。测试断言方式：把备份文件复制到不含 -wal/-shm 的位置后重新打开，`PRAGMA journal_mode` 应为 `delete`。

## 迁移前备份（ADR-018）

- **触发条件：**`open` 发现库中已经有迁移、同时还有待执行的迁移。新建的空库不做这种备份。
- **命名与位置：**备份写到数据目录下的 `Backups/`（不存在时先创建），文件名为 `shike-before-<第一个待执行迁移的标识>-YYYY-MM-DD.sqlite`；写入方式与每日备份相同（先写临时文件，对目标库执行 `PRAGMA journal_mode=DELETE`，再原子改名）。
- **保留：**这类文件不参与每日轮换，也不会被自动删除；同一天、同一迁移已经有备份时不再重复生成。
- **失败处理：**备份失败时，`open` 抛出 `openFailed(备份失败的原因)`，不执行迁移。用户看到打开失败提示，可以腾出空间后重试。
- **可测试性：**迁移器由内部工厂创建，测试可以在 v1 之后追加测试专用的迁移（例如 `v2-test`），生产代码只注册正式迁移。

## L1 测试清单（ShikeDataTests）

- 空库迁移后，`PRAGMA table_info`、索引和外键与本文件及 04 §5 一致。
- uuid 为小写文本，日期为文本。
- 直接用 SQL 插入违反 due 约束的行时被拒绝；`stickyCard.noteId` 唯一。
- 每个仓储方法都有成功路径和 `notFound` 路径的测试；仓储表中每一行的写入效果和 updatedAt 行为都有测试。
- 开启 `simulateWriteFailure` 后，每个写方法都得到 `writeFailed(.simulated)`，库中数据不变；此时迁移、观察和备份仍然正常。
- 全天规范化；完成待办或修改时间时，snoozedUntil 被清空。
- 便签软删除后，它的卡片从 `observeVisible` 中消失，恢复后重新出现；永久删除时卡片级联删除。
- 观察：订阅后先收到当前值；写入后收到新值；对无关表的写入不产生重复值。
- 打开：
  - 新目录能正常打开。
  - 损坏的文件得到 `openFailed(.corrupted)`，文件内容逐字节不变。
  - 登记了未知迁移标识的库得到 `openFailed(.newerSchema)`，且没有写入。
  - 相对路径的 URL 得到 `openFailed(.invalidLocation)`。
- 迁移前备份：
  - v1 库在追加 `v2-test` 迁移后打开，`Backups/` 中有 `shike-before-v2-test-日期.sqlite`，内容与迁移前一致；新建的空库不生成这种文件。
  - 备份目录不可写时，得到 `openFailed`，库仍然停留在 v1。
- 写入失败：例如以只读方式打开同一文件后写入，得到 `writeFailed(.readOnly)`。
- 备份：
  - 新建；当天已有时跳过。
  - 共 8 份时删除最旧的一份；无关文件保留；残留的临时文件被清理。
  - 备份文件复制到不含 -wal/-shm 的位置后能独立打开，`PRAGMA journal_mode` 为 `delete`，行数与主库一致。
  - 跨日边界：UTC 时间 2026-09-23 16:30，在 Asia/Shanghai 下文件名为 `shike-2026-09-24.sqlite`。
  - `shike-before-*` 文件不参与轮换。
