# 拾刻阶段 0 故事多角色评审报告

- **评审对象**：`_bmad-output/planning-artifacts/epics.md`（Epic 1，Story 1.1～1.17，103 组验收标准）
- **评审方式**：BMAD `bmad-party-mode`，`--mode subagent`、`--non-interactive`，六轮议程（覆盖与追溯 / 验收标准质量 / 粒度与依赖 / 技术风险 / 交接视角 / 验收体验）
- **参与者**：🏗️ Winston（架构）、💻 Amelia（开发 / bmad-build 实现者视角）、📋 John（产品）、🎨 Sally（UX）、🌶️ Boundary（边界猎手）、📏 Level（主张核查，全程逐条对照文件核实）
- **日期**：2026-09-25（供 MICBIK 审阅）
- **纪律**：只读评审，未修改任何现有文件；所有发现均注明依据；无法离线确认的标注"待验证"。

> **处理记录（2026-09-26 追记）**：MICBIK 已裁定第 4 节四项均按推荐处理。已落实到文件：R1～R7 与裁决性建议（S2 兜底闭环、S3-①②③、S7-④、S8-②④、S9、S12-②）写入 epics.md，验收标准组由 103 增至 110；规格连动完成——app-shell.md（AppEnvironment 契约补 `dataDirectory` 入参、L2 清单补 readFailed 用例）、data-layer.md（备份节补 `PRAGMA journal_mode=DELETE`、`Backups/` 不存在时自动创建、L1 清单两处同步）。其余建议项按第 4 节第 4 项的划法留待实现期或 1.17 写回处理。故事确认（bmad-create-epics-and-stories 的 [C]）与改名为 `epics-stage-0.md` 仍由 MICBIK 在技能流程中执行。

---

## 1. 结论

故事集整体质量高：FR 覆盖图属实、"依据"约 90 处引用零虚构、17 个故事依赖方向全部正确、粒度符合 SCOPE STANDARD、硬数字三方一致。但**按现状不应直接确认**：有 7 条必须修改的阻塞项——2 条实现级契约缺口（R1 数据目录无来路、R2 备份 WAL 判据失效）加 5 条"规格明文要求但故事层无落点"的验收缺口（R3～R7）。另有一项验收流程时序问题（02 验收第 1 条在第 ⑥ 步物理上无法实测）需要产品负责人拍板。建议修完 7 条阻塞项和少数"裁决性"建议（Winston 的划法：不写明实现者必然自由发挥的判据）后即可确认，其余建议项可带入实现期处理；修完后 bmad-build 可照故事逐个实现，MICBIK 按 7 条清单加 8 项加测即可独立完成验收。

---

## 2. 必须修改

> 不改就不应确认的问题，按严重程度排序。改法均可直接替换进 epics.md；标注"连动"的还需同步伴随文件（见第 4 节第 5 项）。

### R1 数据目录到 BackupService 没有契约路径（1.13 无法按书面契约实现）

- **位置**：Story 1.13 第 6 组；Story 1.8 第 1 组；FR30
- **问题**：BackupService 的启动行为是 `backupIfNeeded(into: 数据目录/Backups, keep: preferences.backupKeepCount)`，需要数据目录入参；但 AppEnvironment 契约签名是 `init(database:preferences:)`，不含目录，AppDatabase 实例也不暴露打开时的目录。故事链中数据目录止步于 AppDelegate（1.8 确定目录、1.13 要用目录），中间没有传递路径。
- **依据**：app-shell.md「组件契约」BackupService（"start() 在后台执行一次 backupIfNeeded(into: 数据目录/Backups, …)"）与 AppEnvironment（"init(database:preferences:)"）；data-layer.md「AppDatabase」（实例侧无目录属性）；epics.md 1.8 第 1 组（"组装 AppEnvironment（04 §6.1）"，未传目录）、1.13 第 6 组（"BackupService 在后台执行一次备份"，未写目录来路）。
- **建议改法**：
  - 1.8 第 1 组："那么 AppDelegate 依次读取启动参数、打开数据目录中的数据库、组装 AppEnvironment（04 §6.1）" → "那么 AppDelegate 依次读取启动参数、打开数据目录中的数据库、组装 AppEnvironment（architecture-diagrams.md §3），并把数据目录传入 AppEnvironment"
  - 1.13 第 6 组："在创建菜单栏图标之后，BackupService 在后台执行一次备份" → "在创建菜单栏图标之后，由 AppEnvironment 用数据目录和 `backup.keepCount` 创建 BackupService 并调用其 start()，在后台执行一次备份"
- **连动**：app-shell.md「AppEnvironment」契约补数据目录入参（如 `init(database:preferences:backupDirectory:)`），需 MICBIK 确认。
- **提出**：Winston；Level 核实升格为阻塞。

### R2 备份 AC"能打开"拦不住 WAL 头残留

- **位置**：Story 1.13 第 1 组；data-layer.md「备份」及「L1 测试清单·备份」
- **问题**：SQLite 在线备份按页复制源库页头（头部偏移 18/19 = 2 即 WAL 格式），WAL 源库备份进新建目标后，目标文件头部仍是 WAL，单独打开会再生成 -wal/-shm；GRDB 7.11.1 的 `backup(to:)` 不做任何 journal 处理（Database.swift `backupInternal` 已核对）。现 AC"备份文件可以单独打开（不使用 WAL）"以"能打开"为判据，防不住这种实现；"检查 -wal 文件不存在"也是假绿（干净关闭会删除 -wal）。
- **依据**：data-layer.md"备份文件是可以独立打开的单个 SQLite 文件（目标库不使用 WAL）"；epics.md 1.13 第 1 组；SQLite 官方文档 fileformat2.html、backup_finish.html、wal.html；GRDB 7.11.1 源码（Level 已逐环核实）。
- **建议改法**：1.13 第 1 组"**并且** 备份文件可以单独打开（不使用 WAL），行数与主库一致" → "**并且** 把备份文件复制到不含 -wal/-shm 的目录后重新打开，`PRAGMA journal_mode` 返回 `delete`，行数与主库一致"
- **连动**：data-layer.md「备份」补一句"备份完成后对目标库执行 `PRAGMA journal_mode=DELETE`，再原子改名"；「L1 测试清单」的备份行同步该断言。需 MICBIK 确认。
- **提出**：Amelia（翻源码发现）；Level 核实升格为阻塞。

### R3 卡片仓储的 notFound 路径无验收（直接违反 L1 清单明文）

- **位置**：Story 1.6（第 2、3 组之间）
- **问题**：data-layer.md 要求"每个仓储方法都有成功路径和 `notFound` 路径的测试"，且 1.4（"任何一个修改方法"）、1.5（点名四个方法+"任何修改方法"）都有全称验收；唯独 1.6 只有 `pin` 有 notFound（便签不存在或已软删除），`updateFrame`/`updateOptions`/`unpin` 对不存在卡片的路径没有任何验收标准。
- **依据**：data-layer.md「仓储」"对不存在的记录执行操作时，抛出 notFound"；「L1 测试清单」第 4 条；epics.md 1.4 第 4 组、1.5 第 4 组对照。
- **建议改法**：在 1.6 第 3 组（unpin）之后追加一组：
  "**假如** 一个不存在的卡片 ID **当** 调用 `updateFrame`、`updateOptions` 或 `unpin` **那么** 抛出 `notFound`"
- **提出**：Amelia、John（各自独立发现）；Level 确认（"最硬的一条"）。

### R4 snooze 的写入效果无验收（同上，违反 L1 清单明文）

- **位置**：Story 1.5（第 3 组之后）
- **问题**：data-layer.md 仓储表规定 `snooze(_:until:)` 写入 snoozedUntil，L1 清单要求"仓储表中每一行的写入效果和 updatedAt 行为都有测试"；但 1.5 中 snooze 只出现在两处——第 2 组验"snoozedUntil 被 setDue/setCompleted 清空"、第 3 组顺带"snooze → updatedAt 更新"。"snoozedUntil 存为传入时间"这一写入效果本身没有任何 AC。
- **依据**：data-layer.md「仓储」表 snooze 行、「L1 测试清单」第 4 条；epics.md 1.5 第 2、3 组。
- **建议改法**：追加一组：
  "**假如** 一条待办 **当** 调用 `snooze(_:until:)` **那么** snoozedUntil 存为传入的时间，updatedAt 更新"
- **提出**：Winston；Level 确认。

### R5 "备份不受模拟写入失败影响"无验收落点

- **位置**：Story 1.4 第 7 组；Story 1.13；FR18
- **问题**：FR18 与 data-layer.md「仓储·模拟写入失败」都写"迁移、观察**和备份**不受影响"，但 1.4 第 7 组只写"迁移和观察照常工作"；1.13（备份故事）全文未提模拟写入失败；连 data-layer.md 自己的 L1 清单也只写"此时迁移和观察仍然正常"。缺口在规格测试清单层就存在。
- **依据**：FR18；data-layer.md「仓储·模拟写入失败」与「L1 测试清单」第 5 条；epics.md 1.4 第 7 组。
- **建议改法**：1.4 第 7 组"迁移和观察照常工作" → "迁移、观察和备份照常工作"；并在 1.13 追加一组：
  "**假如** `Options.simulateWriteFailure` 为真 **当** 调用 `backupIfNeeded(into:keep:)` **那么** 备份照常执行并返回 `.created`"
- **连动**：data-layer.md「L1 测试清单」第 5 条补"和备份"。需 MICBIK 确认。
- **提出**：Winston、Amelia（收敛）；Level 确认。

### R6 readFailed 分支没有任何验证归属

- **位置**：Story 1.10 第 5 组；Story 1.4 第 5 组；app-shell.md「L2 测试清单」
- **问题**：failure-modes.md"读取或观察失败"行标注测试方式为 L2，但 1.10 的 L2 测试组只枚举 `report(.writeFailed(.diskFull))`；1.4 第 5 组"读取失败时，流以 `readFailed(原因)` 结束"也未给触发手段——这是全篇唯一一组没有任何验证归属的 AC。Level 同时核实：1.10 的"重试会重新订阅"是 PanelModel 层的用户触发，与流内部语义不冲突，`DROP TABLE` 造法可行。
- **依据**：failure-modes.md"读取或观察失败"行；epics.md 1.4 第 5 组、1.10 第 5、6 组；app-shell.md「L2 测试清单」末条。
- **建议改法**：
  - 1.4 第 5 组末补："（测试中在观察进行时用第二个连接对同一库执行 `DROP TABLE note`，流以 `readFailed` 结束）"
  - 1.10 第 6 组追加："；让观察流以 `readFailed(.ioError)` 结束后，出现"读取失败：读写数据文件时出错"和"重试"，点"重试"会重新订阅"
- **连动**：app-shell.md「L2 测试清单」末条同步追加 readFailed 用例。
- **提出**：Amelia、John、Boundary（三方收敛）；Level 确认。

### R7 写失败日志无承接

- **位置**：Story 1.10；Story 1.8（对照）
- **问题**：failure-modes.md「日志」要求"打开**和写入**写到 category `data`"；1.8 只承接了打开失败日志（data）与提示展示（ui），1.13 承接了备份日志（backup），写失败的日志没有任何故事承接；conventions.md「错误」"App 用 ErrorText 把原因映射成文案，**同时写日志**"同样无 AC。
- **依据**：failure-modes.md「日志」；conventions.md「错误」；epics.md 1.8 末组、1.10 全文。
- **建议改法**：在 1.10 末尾追加一组：
  "**假如** `report(.writeFailed(原因), retry:)` 被调用 **那么** 写入日志：category `data`，只记录错误分类和代码，不记录用户内容"
- **提出**：John；Level 确认。

---

## 3. 建议修改

> 不阻塞确认的问题。按故事排列；每条已通过 Level 核查。"连动规格"的条目需 MICBIK 点头后随实现修改。

- **S1（1.1）**：为方案补一条 AC："Shike 方案的 test 已注入环境变量 `SHIKE_TEST_HOST=1`"（工程骨架要点 L232 本有此要求，但 1.1 的 AC 未验证）；并注明"AppDelegate 保持最小实现，不碰文件系统与 UserDefaults"——否则 1.2～1.7 期间 CI 的 `xcodebuild test` 真实启动 AppDelegate 存在提前接线风险。〔依据：stack.md「project.yml 要点」schemes；epics.md「工程骨架」段。提出：Boundary、Level〕
- **S2（1.2）**：兜底 AC 的同步清单补漏——"并同步修改 stack.md 和 conventions.md" → "并同步修改 stack.md、conventions.md，以及 NFR9 与 1.1 第 4 条验收标准的措辞"（否则兜底触发后 CI 全绿而 NFR9/1.1 永久无法满足）；自检补两条：为每条规则另配一个**合法样例**确认不误报（含 `internal import GRDB`、注释含 import 字样），自检不通过时 checks 失败并指出规则名；脚本支持指定目标目录，自检样例构造在临时目录。〔依据：NFR9、1.1 第 4 组、conventions.md「检查项」。提出：Winston、Boundary；Level 裁定保留自检并补全〕
- **S3（1.3）**：五处措辞——①错误码映射"例如 SQLITE_FULL 为 diskFull…"改为穷举："分类与 data-layer.md「错误分类」表一一对应，每种 DataFailureReason 都有映射测试"（busy、ioError、constraintViolation 目前零落点）；②补 newerSchema 夹具造法："夹具由内部工厂注册 v1+`v2-test` 建库，再用只注册 v1 的生产迁移器打开（不要改 user_version，GRDB 的检查读 grdb_migrations 表）"；③补可变时钟断言："注入每次调用返回不同时间的时钟时，同一次 create 写入的 createdAt 与 updatedAt 相同，两次 create 的时间不同"（验证 transactionDate 的事务级固定语义）；④"代码中没有 `eraseDatabaseOnSchemaChange`"改为"不使用 `eraseDatabaseOnSchemaChange`（由 checks 检查项 4 守护，测试不要在源码中引用该字符串）"——否则断言用的测试源码会自举触发 checks 报警；⑤"数据目录无法创建，或者没有访问权限 → permissionDenied"拆为两条：权限原因 → permissionDenied，其余文件系统错误按分类表 → ioError。另注明"`backupIfNeeded` 延至 1.13，本故事只交付 open/inMemory/Options"。〔依据：data-layer.md「错误分类」、grdb_migrations 语义（Level 已核对 GRDB 源码）、conventions.md 检查项 4、FR22。提出：Winston、Amelia、Boundary、Level〕
- **S4（1.4）**：①"写入无关的表时不推送重复的值"拆成两条并给正向断言模式："无关表写入不触发推送；对 note 表做结果不变的写入（如 `UPDATE note SET content = content`）后不推送重复值，且其后的真实写入正常推送"——负向断言易假绿，"无效写入后紧跟真实写入"可同时验证去重与订阅活性；②readOnly 测试补造法注记："以只读方式打开指对库文件设置只读权限（目录须保持可写，否则得到 ioError）"。〔依据：data-layer.md「观察」（GRDB 的 `removeDuplicates()` 是显式 opt-in，Level 已核对源码）、「L1 测试清单」。提出：Amelia、Level〕
- **S5（1.6）**：`observeVisible()` 补去重判据（同 S4-①模式）。〔提出：Amelia〕
- **S6（1.7）**：补护栏："AppDelegate 保持 1.1 的最小实现，本故事不把 AppEnvironment 接入启动流程（接入在 1.8）"；并注明"AppEnvironment 本故事只交付三仓储与 Preferences，PanelModel、BackupService 分别由 1.9、1.13 接入"（app-shell 的 AppEnvironment 契约是终态描述，照抄会引用不存在的类型）。〔依据：FR Coverage Map FR30 行、app-shell.md。提出：Boundary、Amelia〕
- **S7（1.8）**：①启动顺序锚补 architecture-diagrams.md §3（04 §6.1 无"读取启动参数"步，且把主菜单和图标并为一步，逐步拆分只在 §3；可保留 04 §6.1 作为写回落点）；②第 3 组补重试再失败分支："重试再次失败时重新显示同一提示（同一时刻只有一个提示实例）"；③测试宿主组补可观察出口："AppDelegate 以可读方式暴露已跳过（如 category `app` 写一条日志），供测试断言"；④全文六处"（验收第 N 条）"统一改为"（02 验收第 N 条）"——1.11 第 5 个 AC 块末尾恰有"（验收第 5 条）"，字面像自引用。〔依据：architecture-diagrams.md §3、04 §6.1、FR20、failure-modes.md。提出：Winston、Boundary、Amelia、John、Level〕
- **S8（1.9）**：①补契约断言："移植代码保持 `behavior = .transient`、`animates = false`"（现 AC 只验监听兜底，不设 transient 也能通过全部 AC）；②补激活兜底句（照 1.11 条件式）："实测在其他 App 前台时面板未能成为关键窗口的，补充回退调用（如 `orderFrontRegardless()`）"；③补三条实测判据："面板背景在 macOS 15 为旧版弹出材质、macOS 26 及以上为 Liquid Glass，均视为符合（UX-DR2）""面板打开时点击其他菜单栏图标（如 Wi-Fi），面板收起""从其他 App 处于前台时点击图标，面板弹出且成为关键窗口""关闭后间隔明显超过防抖窗口（如 300ms）的单击必须能重新打开"；④注明"右键分派留待 1.11，此前右键不响应"（StatusMenu 类 1.11 才存在，照 app-shell 契约实现会引用不存在的类型）；⑤10 毫秒判定补"判定逻辑用可注入时间（L2 可测），人工以'连续快速点击 5 次不弹回'验证"。〔依据：app-shell.md PopoverController/StatusItemController 契约、UX-DR2、03 §3。提出：Winston、John、Sally、Amelia、Level〕
- **S9（1.10）**：①第 2 组补人工路径与状语："**当** 打开面板（阶段 0 无输入界面，可用 `-ShikeDataDirectory` 指向临时目录、以 sqlite3 手工插入一行后重启）"；②第 4 组标注"L2 验证"（"当调用 report(…)"是代码动作，阶段 0 界面没有任何写路径，人工无法触发；真实 App 中即使接通 `-ShikeSimulateWriteFailure` 也不会出现提示条）。〔依据：FR25、06 §11、conventions.md「偏好设置与调试启动参数」。提出：Sally、Level〕
- **S10（1.11）**：第 2 组"实测不在最前面时，补充调用 `orderFrontRegardless()`"是实现指令，移入依据（app-shell.md 已有同文）；AC 保留结果断言"设置窗口显示在最前面并成为关键窗口"（判据：先让其他 App 占前台再打开）。〔依据：app-shell.md SettingsWindowController。提出：Amelia、Sally；Level 确认〕
- **S11（1.12）**：LICENSE 运行时缺失分支需落字取舍（二选一）："LICENSE 资源读取失败时显示明确错误文案，不静默显示空窗口"，或明示"运行时缺失不处理，由 L2 的'包中有 LICENSE 且不为空'把关"——按 NFR4"不用 try? 丢弃失败"的精神建议前者。〔依据：NFR4、1.12 第 4 组。提出：Boundary〕
- **S12（1.13）**：①第 7 组收敛为 02 验收第 7 条字面："数据目录的 `Backups/` 中有当天的备份"（"能打开、数据与主库一致"已由第 1 组 L1 承担，人工无法徒手核对行数，且超出 02 清单字面）；②跨天验证手段落字："跨天触发收敛为可直调方法（订阅 NSCalendarDayChanged 仅转发），L2 直接调用验证再次备份；注入分布式通知若实测可行可替代"——不落实则本条无验证归属（若注入实测不可行且不改直调，升级为阻塞）；③补边界："文件名匹配正则但日期非法（如 shike-2026-13-99.sqlite）的文件视为无关文件不动；`keep` 小于 1 时按 1 处理"；④注明"BackupService 由 AppEnvironment 组装（见 R1）"。〔依据：02 验收清单、data-layer.md「备份」、app-shell.md BackupService。提出：John、Amelia、Boundary；Level 裁定〕
- **S13（1.14）**：补一行点名边界："新建的空库直接注入 `v2-test`（v1 与 `v2-test` 同批执行）时，不生成迁移前备份"——按 FR23 触发条件逻辑可推出"不备份"，但无任何 AC 或 L1 清单点名列出，实现与测试都可能漏掉。〔依据：FR23、data-layer.md「迁移前备份·触发条件」。提出：Boundary；Level 裁定〕
- **S14（1.15）**：①迁入提交补澄清："该单独提交供分支内 PR 评审比对原样基线；按 06 §6 squash 合并后不要求在 main 历史保留"；②注明 `../TZMemo/…` 是一次性迁入步骤、在本机执行、不进 CI。〔依据：06 §6、parser.md。提出：Boundary；Level 裁定"非真矛盾、措辞澄清即可"〕
- **S15（1.16）**：①守护测试补失败语义："向上回溯直到找到含 docs/05 的目录（设上限，如 10 级）；找不到 docs/05、或从 §9 提取不到任何行时，测试失败并打印已搜索路径，不得跳过"；②J 组归因放宽："J 组全部返回 nil，原因见 05 §9.10 说明列（§6 歧义规则、§3 合法性、§8 暂不支持等）"——现文"按 §6 的规则"过宽（J01/J02 属 §2、J10 属 §8、J11 属 §3、J12 属 §4.2）。〔依据：1.16 第 1、4 组、parser.md「守护测试」、05 §9.10。提出：Boundary、Amelia；Level 裁定〕
- **S16（1.17 与实施说明）**：①1.17 增加一条演练式 AC："**假如** 一位未参与阶段 0 的负责人 **当** 照'扩展指南'实际演练一项（如新增一个偏好键或一处文案）**那么** 能按步骤完成且测试通过"——把"指南正确"从声明变成实测；②AC1 的写回清单点名"11 种错误文案表、观察排序与去重语义"；③实施说明"阶段 1 依赖的契约"补列两个扩展点：Localizable.xcstrings 文案机制（S1-10 直接要用）、1.11 的设置分页注册表（S1-08/S1-09 要用）；④（可选）实施说明加一句"阶段 0 实现期间以 `_bmad-output/specs/` 规格为准（1.17 才写回 docs）"。〔依据：SPEC CAP-13、1.17 各组、conventions.md「文案」、app-shell.md SettingsTab。提出：John、Level〕
- **S17（伴随文件连动清单，需 MICBIK 确认后随实现修改）**：data-layer.md——「观察」表"是否存在卡片"统一为"是否已钉到桌面（即是否存在卡片记录）"（与 FR13/NoteListItem 字段对齐）；「L1 测试清单」readOnly 行补测试造法（同 S4-②）。app-shell.md——「阶段 0 文案」表补全六个设置分页键名（如 `settings.tab.general / shortcuts / reminders / cards / data / about`，现为首尾省略式）；PanelView 行补"红色""左侧"两词（1.10 AC 与 03 §14 有"红色"，03 §3 有"左侧"，契约行信息量偏低）；文件布局表 `Assets.xcassets` 标注"阶段 4（正式图标）时创建"或移除（阶段 0 全用 SF Symbol，留着与 NFR13"只创建用到的目录"相抵）。epics.md——UX-DR1 出处补注 app-shell.md（"辅助功能描述"的真实出处，03 无此内容）；UX-DR6 出处补注 failure-modes.md 与 app-shell 文案表（03 无"读取失败"字样）。〔提出：Sally、Winston、Level；Level 逐条核实为建议级〕
- **S18（流程与工具，非故事文本）**：①bmad-build.toml 的 persistent_facts 补一句"实现规格正文只写对伴随文件的引用与增量描述"，防止实现规格整段抄录超 token 预算（1.1/1.2/1.3/1.4/1.8/1.11 均为大故事，Level 实测 1.2 文本最大）；②验收走查附安全守则（见第 6 节第 5 条）。〔提出：Amelia、Level、Boundary〕

---

## 4. 需要产品负责人决定的问题

1. **02 验收第 1 条的时序（三方收敛的流程缺陷）**："GitHub 上 main 分支的 CI 显示通过"在第 ⑥ 步（合并前）物理上不可能成立——CI 配置在 `stage-0/foundation` 分支上，main 要到合并后才有第一次 CI（依据：stack.md「分支保护」、02 阶段规则 3 与第 1 条字面互斥，Boundary 判定为"死锁"）。
   - 选项 A：维持 02 原文，验收口径为"分支 CI 全绿 + main 分支保护已开"，第 1 条延至第 ⑧ 步合并后复核打钩。不改任何文件。
   - 选项 B：在 1.17 写回时把 02 第 1 条改为两段式（"合并前：分支 CI 三项全绿；合并后：main 首次 CI 绿"），并在 1.17 的 AC 中点名此项。
   - **讨论倾向**：B（John/Amelia/Boundary 均指向"落字"，B 是唯一不改 02 生效文本的落字路径）。
   - **决定（2026-09-26）：**采用 B；已在 1.17 新增一组验收标准（写回 02 时落字），本阶段不改 02 生效文本。
2. **Backups/ 目录不存在时的行为（唯一的规格留白）**：open 六步骤只创建数据目录本身，备份/迁移前备份两节均未规定 `Backups/` 不存在怎么办。若被用户删除：每日备份失败只写日志（可容忍），但迁移前备份失败会让 open 抛 openFailed——阶段 2 起真实用户可能陷入"重试无效"（有"打开数据目录"人工恢复路径，Level 故判非阻塞，但属 ADR-018 安全契约留白）。
   - 选项 A：备份（含迁移前备份）前确保目录存在，不存在则自动创建（与"数据目录不存在时自动创建"一致）。
   - 选项 B：不存在视为"不可写"同类失败。
   - **讨论倾向**：A（Boundary 提出，Level 核实）。修复需 data-layer.md 一句话 + 1.13/1.14 各一条 AC。
   - **决定（2026-09-26）：**采用 A；data-layer.md 的备份两节已补自动创建，1.13/1.14 各新增一组验收标准。
3. **macOS 15 双系统实测**：Winston 建议在 1.9 写明"在 macOS 15 与 26 上分别人工实测"；John/Level 指出开发机是 macOS 27、CI 是 macos-26，macOS 15 需另找设备。
   - 选项 A：阶段 0 只在开发机 + CI 的系统上实测，macOS 15 依赖 ADR-003 的"自动回退"论证，在验收记录中明示此例外。
   - 选项 B：验收前找一台 macOS 15 设备补测第 3、4 条。
   - **讨论倾向**：A（激活兜底句 AC 已按 1.11 句式补入 S8-②，把风险留到实测现场有预案）。
   - **决定（2026-09-26）：**采用 A；1.9 已补激活兜底句，验收时在记录中明示 macOS 15 例外即可。
4. **建议级修改的执行方式**：全部确认前改完，还是只改"裁决性"条目？
   - **讨论倾向**（Winston 划法，无人反对）：修完第 2 节 7 条阻塞 + 以下裁决性建议后即确认——S2（兜底闭环）、S3-①②③（1.3 映射/夹具/时钟）、S7-④（验收第 N 条）、S8-②④（激活兜底、右键注记）、S9（1.10 两组）、S12-②（dayChanged 手段）；其余 S 条目可带入实现期或随 1.17 写回处理。
   - **决定（2026-09-26）：**按推荐划法执行——阻塞与裁决性建议已落实到 epics.md，其余 S 条目延后。

5. **规格连动的授权**：R1/R2/R5 与 S17 的部分修法需要同步 data-layer.md、app-shell.md（均已定稿并经 MICBIK 确认）。按 data-layer.md 开头"实现时可以做不改变语义的调整，但要同步本文件"与 CAP-13 的写回机制，这些属于规格随故事完善的既定通道，但**需要 MICBIK 明确点头**后再动。
   - **状态（2026-09-26）：**上述修复所需的连动已随四项决定一并完成（app-shell.md 两处、data-layer.md 五处）；超出该范围的其他规格修改仍未动。

---

## 5. 涉及已定决策

**无。** 六轮评审的所有发现均未触碰已冻结事项：17 个故事的划分与顺序、技术选型（XcodeGen、AppKit 生命周期、GRDB 7.11.1 internal import、NSRegularExpression、警告即错误只在 CI、ad-hoc 不沙盒）、第三方许可证暂缓、单实例与 05 §7 顺序不在阶段 0、分支保护时点、bmad-build 团队配置。R1/R2 的"连动规格"修法不改变任何已定选型，只补齐既定契约的实现路径（见第 4 节第 5 项）。边界猎手特别核对过：failure-modes.md 中"同时运行多个实例""写入时被强制退出"两行按已定决策不处理， stories 未越界补测。

---

## 6. 待验证的风险

| # | 风险 | 所在故事 | 验证方法 | 建议应对 |
|---|---|---|---|---|
| 1 | Xcode 26.6 是否支持字符串目录生成符号（本地实测用的是 Xcode 27） | 1.1、1.2 | 首次 CI 的 `app` 作业日志（`app.name` 符号测试正好落在该作业） | 1.2 已有兜底 AC；按 S2 补全同步清单后闭环，无需额外动作 |
| 2 | NSPopover 激活/成为关键窗口在 macOS 15 与 26/27 上的行为差异 | 1.9 | 验收第 3、4 条实测；必要时临时打印 `view.window?.isKeyWindow` | S8-② 的激活兜底句把预案写进 AC；双系统范围见第 4 节第 3 项 |
| 3 | WAL 备份执行 `PRAGMA journal_mode=DELETE` 的时序（连接内直改还是改名前改） | 1.13 | L1 备份测试即跑即知（按 R2 新判据断言） | R2 落地后第一次跑测试即消解 |
| 4 | 同进程注入 `NSCalendarDayChanged`（分布式通知）是否可行 | 1.13 | L2 中尝试 `DistributedNotificationCenter.postNotificationName` 注入 | 不可行则按 S12-② 把跨天触发收敛为可直调方法（推荐直接采用直调，绕开验证） |
| 5 | 验收期真实数据目录的开发期残留干扰实测（假红：旧库损坏/非空库看不到空状态；假红：`-ShikeDataDirectory` 残留把备份重定向到 /tmp） | 流程（第 ⑥ 步） | 不适用（操作纪律） | 验收安全守则：①第 3～7 条统一用 `-ShikeDataDirectory` 指向全新目录（勿复用 `/tmp/shike-dev`）；②第 7 条最后在真实目录单独跑；③验证备份用 `sqlite3 -readonly` 只开备份副本；④三个调试参数即用即关（依据：conventions.md「偏好设置与调试启动参数」、06 §11） |
| 6 | 只读写入测试的 WAL 坑（目录只读会得到 ioError 而非 readOnly） | 1.4 | L1 构造用例时即知 | 按 S4-② 注记造法（chmod 库文件而非目录） |
| 7 | 运行中系统时区变化后，跨天备份仍用启动时捕获的时区命名 | 1.13 | L1 用两个时区序列调用 `backupIfNeeded` | 低概率；按 S12-④ 补一句"触发时按当时本地时区计算日期"或不处理（记录即可） |

---

## 7. 已核对、没有问题的方面

- **覆盖与追溯**：FR Coverage Map 与 UX-DR 覆盖说明抽查属实，FR1～FR37 主体全部落到具体 AC（缺口仅有第 2 节所列）；CAP-1～CAP-14 的 success 全部有故事承接；02 验收第 3～7 条与 1.9/1.10/1.11/1.8/1.13 一一对应且"验收第 N 条"编号解析全部正确；data-layer.md L1 清单 12 组、app-shell.md L2 清单 7 组绝大多数有落点；failure-modes.md 16 行（含按已定决策不测的两行）全部核对无悬空。
- **一致性与引用**：Level 机械核对约 90 处"依据"引用，零虚构——章节名、04 §6.9、05 §9.10～§9.13、Issue #1/#2、demo 基线提交 `e3c0260`（已在旧仓库验证存在）、两个 SHA 全值全部真实且用途匹配；伴随文件互引无断链、无循环。
- **数字三方一致**：360×520 / 300×360 / 600×1000、10 毫秒、keep 7、hiddenOpacity 0.0～0.6、T0 = 2026-09-23 12:00 Asia/Shanghai（该日确为周三）、跨日边界换算（UTC 16:30 → shike-2026-09-24）、11 种错误原因、占位阶段号 1/1/2/3/4、索引名三个、数据库与备份文件名——故事/伴随文件/docs 逐字一致。
- **用例计数**：1.15 的 98 例（10+4+10+16+6+10+21+14+7）与 1.16 的 27 例（13+1+5+8）合计 125，与 05 §9 全表实数精确吻合；103 组 AC 计数属实（8/7/9/7/6/6/3/10/7/6/7/4/7/4/4/4/4）。
- **依赖与顺序**：17 个故事两两核查，无一个依赖编号在后的故事；FR33 启动顺序由 1.8/1.9/1.11/1.13 分段拼合后与 architecture-diagrams.md §3 完全一致；1.14 合并后 1.3 的既有 AC 无一被推翻。
- **中间态安全**：1.2～1.7 窗口期 AppDelegate 保持无启动逻辑（宿主启动无副作用）；NOTICE 移植清单与 checks 规则逐提交自洽；1.8 完成时按已交付组件组装可编译（增量组装有 FR Coverage Map 背书，注记见 S6/S7）。
- **粒度**：1.3、1.4、1.8、1.11、1.15 的单目标判定均成立（1.11 三件事共同服务"操作入口齐全"一个用户目标）；各故事合并后 MICBIK 可验证的内容明确（1.8 起第一个可见产物，前五个 PR 由测试证据交付）。
- **技术底座**：GRDB 三个静默失败点（UUID 静态函数、internal import 后 Foundation、Swift Regex 非 Sendable）均为"写法+结果"双重防护且经探针/源码核实；`transactionClock` 与 `hasBeenSuperseded` 的契约语义正确（后者读 grdb_migrations 表，AC 措辞"登记了未知迁移标识"本身没错）；"警告即错误"双通道机制的 GRDB 冲突规避已实测；ShikeDataTests 可直接 `import GRDB` 有 stack.md 明文依据。
- **界面与文案**：阶段 0 全部可见文案（弹窗标题与三按钮、两处空状态、条数占位、提示条、右键菜单、六分页、关于页、许可证窗口）在故事 AC、app-shell 文案表、03 之间逐字一致（含 U+2026 省略号、全角括号、占位符）；法律声明整段三方逐字一致；1.11→1.12 之间关于页暂缺法律声明不构成 GPL 合规问题（阶段 0～3 不发布二进制，06 §10）。
- **流程无主文件清点**：app-shell.md 文件布局表中除 Assets.xcassets（S17 建议标注）外，每个文件都有承接故事；`Log.swift` 由 conventions.md「日志」与 1.8/1.13 隐含承接，归属清晰。

---

## 8. 分歧纪要

各方理由原样保留，未强行调和：

1. **1.2 的检查脚本自检（Winston vs Boundary vs Level）**：Winston 认为自检是 conventions.md「检查项」没有的"契约外加码"，应同步或降级；Boundary 认为自检自身的失败呈现还缺 AC（自检发现规则失效时 checks 必须变红并指出规则名）。Level 裁定：保留自检（与守护测试哲学一致、epics 本就新增契约外细节如 SHA），并补"自检失败即红+指出规则名"的 AC、同步进 conventions。三方立场如上，落法按 Level 案（S2）。
2. **`internal import GRDB` 规则是否放宽（Boundary vs 已定决策）**：Boundary 主张放宽为"禁止裸 import 与 public 级导入"以免误报 private/fileprivate import；Level 裁定不放宽——"只能 internal"是产品负责人的已定决策措辞，规则收窄正是机械守护的目的。Boundary 的务实考量记录在案。
3. **双系统实测（Winston vs John/Level）**：Winston 主张把"macOS 15 与 26 分别人工实测"写进 1.9 的 AC；John/Level 反对（macOS 15 需另找设备，成本落在 MICBIK），主张按 1.11 句式补激活兜底 AC、双系统实测留到验收并记录例外。未完全一致，交第 4 节第 3 项由 MICBIK 决定。
4. **验收第 1 条时序的落点（John/Boundary/Amelia 内部）**：三方一致认定"⑥ 步测不了 main CI"，但落字位置有分歧——改 02 原文（需动 docs，超出本次权限）vs 验收口径宽读 + ⑧ 复核（不动文件）vs 1.17 写回时落字（B 案）。已作为决定项交 MICBIK。
5. **1.15 单独提交与 squash 合并（Boundary vs Level）**：Boundary 认为构成矛盾（squash 后提交切分在 main 消失，"AC 产物必然消失"）；Level 判定非真矛盾（AC 只要求"做出单独提交"的动作，评审发生在 squash 之前的分支/PR 上，且三处原文均未写动机），按措辞澄清处理（S14-①）。Boundary 的观察保留。
6. **10 毫秒防抖（Amelia vs Sally）**：Amelia 主张判定逻辑 L2 化（注入时间）；Sally 反对调大 10ms 阈值（会吞掉"关完立刻想再开"的操作），主张保留 10ms 实现、把体验判据写严（连点 5 次 + 超防抖窗口可重开）。两者兼容，落 AC 时同时采纳（S8-③⑤）；Sally 对"把 300ms 测试数值焊进 AC"持保留意见（写成"如 300ms"的参考值，行为打磨归 S1-01）。
7. **并发双 pin 竞态（Boundary vs Level）**：Boundary 认为应补并发 AC；Level 认为若实现把"查 existence + insert"放进单事务，DatabasePool 写串行化会使第二次 pin 命中幂等分支，不必然竞态，且规格的"幂等"按惯例指顺序重复调用（已有 AC），建议以"pin 在单个事务中完成"一句规格说明消解，比补并发测试便宜。未决，倾向 Level 案（可在实现 1.6 时作为注记）。
8. **（已修正的误报）**：Sally 第 2 轮曾称提示条"红色"无出处、Winston 第 6 轮曾称"UX-DR8 的例如=允许自造文案"，均被 Level 核实纠正——"红色"有 03 §14 与 UX-DR6 明文（残余问题只是未定义色值，建议 systemRed）；文案已被 1.8 的"与 app-shell 文案表一致"锁定，真正的"例如"问题只在 1.3 的错误码映射（R3/S3-①）。按修正后的结论入账。

---

*本报告由 party-mode 六轮讨论汇总而成，讨论过程中未修改任何仓库文件（仅按 BMAD party-memory 机制写入了 `_bmad-output/party-mode/memories/installed/.memlog.md` 与本报告）。*
