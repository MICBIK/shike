# 阶段 4 SPEC 独立盲审（2026-10-03 夜）

> 执行：夜间收尾批卡A ｜ 对象：`_bmad-output/specs/spec-stage-4-朋友内测/SPEC.md`（基线 HEAD `9f868d5`）｜ 性质：**不推翻、只挑错；未改 SPEC 一字**——修订清单留规划会话在产品负责人确认时一并裁定。零代码，本报告与晨报是本卡唯一产物。
> 方法：①逐 CAP（CAP-1～10）对照 docs/02 能力表与验收清单、docs/03 §2/§9/§12/§13/§14/§15/§16.6、docs/04 §1/§4.2/§5.5/§6.1/§6.6/§6.11/§10、docs/06 §8/§10、ADR-032、epics-stage-4（含拍板记录与附录）、audit-可访问性 §B3；②可实现性走查——SPEC/epics 引用的偏好键、接口、文件逐一在代码中核对存在性；③完备性——docs/02 阶段 4 要求 vs SPEC 覆盖、Non-goals 误伤检查。

## 0. 结论

- **P1（阻塞级）：0 项。** 十个 CAP 的能力口径与 docs/02/03/04、ADR-032、epics、audit 未发现实质冲突；决策点均已按"规格阶段写死"要求落死（脚本名、--publish 门闩、sign_update 定位、交互式更新、引导双条件、备份失败态会话内回传、直达导出、保留份数 1–30）。**SPEC 可进入产品负责人确认流程。**
- **P2（建议确认时裁定）：4 项。** 集中在：一处发布脚本核心路径的工程语境错位、epics 侧四处口径漂移未回填（双源矛盾）、一个 companion 契约缺口（菜单栏正式图标）、一处交互口径疑点（手动检查失败静默）。
- **P3（文字/引用/文档同步）：10 项。**
- 可实现性走查全部通过：引用的既有键/接口/文件**全部真实存在**；两处"待新增"（`AppDatabase.open` created 标志、`TrashRepository.purgeExpired`）SPEC 均有准确预判。估算无失真（两处 epics 文件面按 SPEC 口径可各减一个文件，见 §3）。
- Non-goals 无误伤：URL Scheme 与导入向导确实未混入十个 CAP（但建议显式排除，见 P3-5）。

## 1. P2 发现（4 项，建议产品负责人确认 SPEC 时一并裁定）

### P2-1 · sign_update 定位路径的工程语境错位（CAP-2）

- **SPEC 原文**（SPEC.md:48）：「`sign_update` 定位方式定死一种：Sparkle SPM 产物 `.build/artifacts/sparkle/Sparkle/bin/`（脚本先 `swift package resolve` 再定位）」。
- **问题**：`.build/artifacts/` 是 **SPM 独立原型**的布局（ADR-032 的验证原型 SparkleTestApp 自带最小 Package.swift，在 /tmp 下 resolve）。而拾刻是 XcodeGen 工程（ADR-012），Sparkle 2.10 将经 project.yml 作为 App 目标的 SPM 依赖由 **xcodebuild** 解析，产物落在 `DerivedData/<workspace>/SourcePackages/artifacts/sparkle/Sparkle/bin/`，**不会出现** `.build/artifacts/`。「脚本先 `swift package resolve` 再定位」在仓库语境下指代不明：仓库内的本地包 ShikeKit 不依赖 Sparkle（04 §1 依赖规则），对它 resolve 拉不到 Sparkle。
- **影响**：release.sh 的核心步骤之一，照字面实现会在定位 sign_update 时卡住；epics 6.4 风险对策本就说"DerivedData 里路径不稳定 → 规格阶段定死一种"，SPEC 定死的这一种恰好没对准 xcodebuild 工程的实际布局。
- **建议处置**：将该条改为可实现的两选一并写死：①脚本内临时生成最小 manifest（只声明 Sparkle 依赖）做 `swift package resolve`，复刻 ADR-032 原型路径；②`xcodebuild -resolvePackageDependencies` 后从 DerivedData `SourcePackages/artifacts/sparkle/Sparkle/bin/` 定位。实测定一种后更新 SPEC 该行（ADR-032 的 `.build` 路径注明"原型语境"即可，ADR 本身不追加不改）。

### P2-2 · epics-stage-4 四处口径漂移未回填（SPEC 已定死、epics 仍是旧口径，双源矛盾）

SPEC 在 epics 拍板（2026-10-04）之后产出，改了四处口径且均为**改进**，但 epics 正文未同步；而 SPEC 头部又声明「故事的**文件面预估**与风险台账以 epics 为准，本 SPEC 管能力口径与验收标准」——冲突恰有多处在文件面里。bmad-build 汇总上下文时会**同时加载 SPEC 与 epics**（06 §8"实现时加载规格"条），实现者将看到两个矛盾口径。

| # | SPEC 已定死 | epics 仍是 |
|---|---|---|
| a | 自动检查更新开关绑定 Sparkle 自持键，**不新增 App 侧镜像键**（SPEC.md:72、Constraints:143） | 6.3 AC2：「偏好键建议 `updates.autoCheck`，写入 04 §5.5」（epics:112）；6.3 文件面含 `Preferences.swift`（epics:120） |
| b | 新热键由 KeyboardShortcuts 以 `newNote`/`newTodo` 自持，**Preferences 不新增镜像键**（SPEC.md:62、143） | 6.2 文件面：「`Services/Preferences.swift`（`hotkey.newNote`、`hotkey.newTodo`，键值格式规格阶段定）」（epics:95） |
| c | 备份失败态**会话内内存回传、不持久化、不新增偏好键**（SPEC.md:109） | 6.8 文件面：「`Preferences.swift`（如需持久化失败态，键规格阶段定）」（epics:226） |
| d | 脚本名 `scripts/release.sh`（docs/06 §10 与 docs/04 §6.11 既有口径），SPEC.md:45 已显式声明修正 | 6.4 AC1 仍写 `scripts/package.sh`（epics:136），SPEC 的"修正"声明无人执行 |

- **建议处置**：规划会话确认 SPEC 时对 epics 做一次**只改字、不动 AC 结构**的回填：上述四处各加一句"以 SPEC-stage-4 为准"（或直接改正文），并把 6.2/6.3/6.8 文件面中的 `Preferences.swift` 按新口径删除（各减一文件）。CAP-2（SPEC.md:45）那种"以本 SPEC 为准修正"的显式顺位声明，建议补到前三处。

### P2-3 · 菜单栏正式图标：docs/03 承诺阶段 4 交付，SPEC 与 epics 均未接（companion 契约缺口）

- **对照源**：docs/03 §2「正式图标在阶段 4 设计」（03:24）；docs/03 §15「菜单栏图标 `note.text`（阶段 4 换成正式图标）」（03:275）。
- **问题**：SPEC 的 companions 保全校验含 docs/03，但十故事里没有任何一处接"图标设计/更换"；epics 十故事同样没有；docs/02 阶段 4 能力表 S4-00～S4-09 也没有对应编号。三方各缺一角：docs/03 说阶段 4 做，02/epics/SPEC 都没安排。
- **影响**：若验收或内测朋友按 docs/03 对照，会得出"阶段 4 漏交付"；反之若实施者读到 docs/03 顺手换图标，又是阶段内加范围。
- **建议处置**：确认时二选一并落字：①并入现有故事（工作量小，可挂 CAP-3 设置窗口收尾或 CAP-5 README 截图前，因图标会出现在截图中）；②Non-goals 显式排除「菜单栏正式图标，推迟阶段 5」，同时把 docs/03 两处括号改为「阶段 5」。**不裁定比选错更糟**——这是唯一一处 companion 承诺了阶段 4 却无人认领的交付物。

### P2-4 · 手动"检查更新"失败也静默只写日志，口径存疑（CAP-4）

- **SPEC 原文**（SPEC.md:74）：「关于页"检查更新"按钮手动触发，走 `checkForUpdates()` 用户意图路径……；无网络/检查失败静默只写日志（`app` category），不打扰」。
- **问题**：该句落在**手动触发**条款内。用户主动点了按钮、检查失败却零反馈，按钮形同坏了——这与"失败不打扰"策略的本意（后台动作不骚扰）不同：手动动作的失败反馈是交互闭环的一半。且 Sparkle 标准用户驱动（SPUStandardUserDriver）对手动检查失败**默认有错误提示**，要"静默"反而需要额外接管压制，实现成本为负收益。epics 6.3 AC3 同口径（epics:113），属同源沿用。
- **建议处置**：改为两分口径——**后台**检查失败：静默只写日志（现状句保留）；**手动**检查失败：给轻量反馈（Sparkle 默认行为即可，无需自定义文案）。产品负责人确认时顺手裁定；若维持原口径也可接受，但建议在 SPEC 内注明"手动失败静默是有意为之"。

## 2. P3 发现（10 项，文字/引用/文档同步类）

| # | 位置 | 问题 | 建议处置 |
|---|---|---|---|
| P3-1 | SPEC.md:71（CAP-4）、epics:111 | 引用「04 §2.3 集成约束：系统集成不进 ShikeKit」——docs/04 **没有 §2.3 小节**；该约束实际在 docs/04 §1「依赖规则」（04:26「AppKit、通知中心、Sparkle 等系统集成只出现在 App 目标中」） | 引用改为「04 §1 依赖规则」 |
| P3-2 | SPEC.md:15（头部） | 映射公式「Story 6.N ⇔ S4-0(N-1) ⇔ CAP-N」与各 CAP 实际标注冲突：CAP-2=S4-03=**6.4**、CAP-3=S4-01=**6.2**、CAP-4=S4-02=**6.3**。公式只对 CAP-1/5/6/7/8/9/10 碰巧或部分成立 | 公式改为「逐条见各 CAP 标注（CAP-N · S4-xx · Story 6.N）」，以标注为准 |
| P3-3 | docs/04 §6.11（04:300）、docs/06 §10（06:157） | 两处均写「EdDSA 私钥**只**保存在开发者的钥匙串中」，与 SPEC「钥匙串**或** `SPARKLE_PRIVATE_KEY_FILE` 文件注入」（ADR-032 实测走的是文件式）不一致；docs/06 §10 发布步骤还写「更新版本号和 **CHANGELOG**」，与 CAP-2「更新说明读仓库根 `RELEASE-NOTES.md`……不依赖阶段 5 才建立的 CHANGELOG」（SPEC.md:49）口径相左 | CAP-2 实施本就要写 docs/06 发布流程小节，届时一并修正；SPEC 修订时给 CAP-2 补一条「同步 docs/04 §6.11 与 docs/06 §10 的私钥注入口径与 release notes 来源」 |
| P3-4 | SPEC.md:90-98（CAP-6） | docs/02 S4-05 全文是「**查看已删除的便签和待办，可恢复、可永久删除**；超过保留期自动清除」——前半已由 S3.5-05 交付，但 CAP-6 没有像 CAP-7 对 S4-06 那样的显式归属标注，逐 CAP 对照 docs/02 时 CAP-6 显得"只接了半条" | CAP-6 补一句「S4-05 的查看/恢复/永久删除已由 S3.5-05 交付（02 阶段 3.5 表），本能力余保留期自动清除」 |
| P3-5 | SPEC.md:147-154（Non-goals） | URL Scheme（S5-08）与导入向导**确实未混入**十个 CAP（核查通过），但 Non-goals 未显式排除二者；第 6 条「阶段 5 范围项」列举（S5-01/02/04/06）也不含刚拍板进阶段 5 的 S5-08——恰是上周还是阶段 4 候补、最容易被误加的两项 | Non-goals 补一行：「URL Scheme（S5-08，已拍板进阶段 5）与导入向导（已拍板增长期再议）不进本阶段」 |
| P3-6 | SPEC.md:113-122（CAP-9）、:94（CAP-6） | 引导窗口与超期清除扫描都要挂启动序列（epics:「启动序列尾部挂载」），但 docs/04 §6.1 启动顺序未列这两个插槽（现列表尾项是「恢复卡片（阶段 3）→ 检查更新（阶段 4）」）；SPEC 只要求 CAP-9 同步 04 §4.2（created 标志），没要求同步 04 §6.1 | SPEC 修订时给 CAP-6/CAP-9 各补「同步 docs/04 §6.1 启动顺序」一句 |
| P3-7 | SPEC.md:116-119（CAP-9） | 可接受边界，建议知情记录：全新安装用户若在引导完成前强退（或首次启动崩溃），下次启动库已非新建、`onboarding.completed` 缺失 → 按写死的双条件**永不再自动弹**。关于页"重新打开引导"是兜底 | 产品负责人确认时知情接受即可；可在台账或引导实现注记一句，不需改口径 |
| P3-8 | SPEC.md:85（CAP-5） | 与 ADR-003 理由 1「macOS 15 起 Gatekeeper 的放行流程是统一的，安装说明只需要写一份」存在措辞张力：CAP-5 要求「15 与 26/27 的放行界面文案/入口不同，截图各配或文字注明」。两者不实质冲突（ADR-003 说的是"流程统一、无需右键豁免"，CAP-5 说的是"界面细节有差异"），但验收抠字眼时会打架 | CAP-5 措辞微调为「放行**流程**按 ADR-003 统一口径，界面**细节**差异以文字注明」，或在 ADR-003 处注明界面细节另见 CAP-5 |
| P3-9 | epics:120（6.3 文件面） | 「04 §11 移植计划已有槽位」引用错位：移植清单实际在 docs/04 **§7** 表内（04:323 `Services/UpdateService` 行）；§11 是扩展指南 | 随 P2-2 回填 epics 时顺手改为「04 §7」 |
| P3-10 | SPEC.md:40（CAP-1）vs ADR-032 后果段 | ADR-032 后果写打包脚本「`zip -ry`（保符号链接）」，SPEC/epics 写「`zip -qry`」。`-q` 仅静默、语义等价，非冲突 | 无需动作；ADR 只追加不修改，备注一句避免实施者对参数起争议 |

## 3. 可实现性走查（逐项核对代码，全部落实）

### 3.1 引用的既有键/接口/文件 —— 全部真实存在

| SPEC 引用 | 核对结果 |
|---|---|
| `backup.keepCount`（CAP-8） | ✅ `Preferences.Key.backupKeepCount`（Shike/Services/Preferences.swift:17），默认 7（:40） |
| `BackupService.start()` / `backupNow()`（CAP-8） | ✅ Shike/Services/BackupService.swift:30/:52；现无互斥与结果回传——正是 CAP-8 的新增范围，前提成立 |
| `TrashRepository` 与回收站观察流（CAP-6） | ✅ restore×2 / permanentlyDelete×2 / emptyTrash / observeNotes / observeTodos（Repositories/TrashRepository.swift） |
| `PanelModel.OpenMode` 语义（CAP-3/CAP-9） | ✅ enum OpenMode（Panel/PanelModel.swift:23）+ `initialMode(openMode:lastMode:)` + `applyOpenMode()`，参数化为"固定模式呼出"可行 |
| `ExportService` 纯函数+单测（CAP-7） | ✅ Shike/Services/ExportService.swift（markdown/json，:32/:170） |
| KeyboardShortcuts 注册名（CAP-3） | ✅ 现仅 `togglePanel`（HotkeyService.swift:20-22）；新增 `newNote`/`newTodo` Name 可行（库支持多 Name） |
| ADR-021 链路"单动作→多热键"（CAP-3） | ✅ `HotkeyEventTap.install(keyCode:carbonModifiers:onMatch:)` 为单组合结构（HotkeyEventTap.swift:31），`dispatchHotkeyAction()` 单动作（HotkeyService.swift:148）——"整体重验"的判断准确，扩展点清楚 |
| `AppDatabase.open(directory:options:)`（CAP-9） | ✅ 存在（AppDatabase.swift:53）且**确无 created 标志**——SPEC「现接口若无则小改，并同步 docs/04 §4.2」预判属实，改动量小（open 内部区分空库创建路径） |
| `.github/ISSUE_TEMPLATE/` bug/idea 两模板（CAP-10） | ✅ bug-report.yml / idea.yml / config.yml 在库；`version-info` 字段 id 存在且 required；耦合标注已在（config.yml 头注 + bug 文件头注）——CAP-10"模板文件头标注"一项实际**已满足**，实现时只需核对 URL 参数回填效果 |
| `SUPublicEDKey` 经 project.yml 写 Info.plist（CAP-4） | ✅ project.yml 已有 `packages:` 节与 `INFOPLIST_KEY_LSUIElement`（:51）同机制可循 |
| 关于页版本含构建号（CAP-10 预填素材） | ✅ `AboutSettingsView.versionText`（:52）已有同源逻辑 |
| `-ShikeDataDirectory`（CAP-3/CAP-8 数据页显示实际目录） | ✅ LaunchOptions/06 §11 既有 |
| 设置窗口 460pt、data 占位（CAP-3、audit B3） | ✅ SettingsWindowController.swift:18 固定 460×320；SettingsTab `case data` 占位阶段号 4——B3 现状与修复落点属实，加宽即改 contentRect，实现成本低 |
| README 占位（CAP-5） | ✅ 状态行「开发中」（README:5）、安装节「从阶段 4（v0.5）开始提供」（README:22），引用属实 |
| CI 三作业（完成定义） | ✅ ci.yml：checks / package-tests / app |
| `scripts/`、`RELEASE-NOTES.md`、`.github/assets/` | 均不存在=阶段 4 新建物，与 CAP-2/CAP-5 口径一致，非遗漏 |

### 3.2 待新增项核对（SPEC 已预判，无意外）

- `trash.retentionDays`、`onboarding.completed`：代码中不存在，docs/04 §5.5 已登记（04:203 与 Constraints 新增），「已登记沿用/新增」措辞与实况一致。
- `TrashRepository.purgeExpired(before:)`：不存在，SPEC「或同语义」即新增方法；级联删除由表外键保证（04 §5.4 noteId 级联），「便签级联卡片记录」无需新代码。
- `DataSettingsView`、`UpdateService/`、`Onboarding/`、`release.sh`：均不存在，皆为新文件，落点与 epics 文件面一致。

### 3.3 估算复核

epics 各故事文件面与工时估算**无明显失真**。按 SPEC 定死口径可两处缩编：6.2 与 6.8 的文件面中 `Preferences.swift` 可删（hotkey 不落镜像键、备份失败态不持久化，见 P2-2）。B3 修复 0.5h 与 audit 建议一致。

## 4. 完备性

- **docs/02 阶段 4 覆盖**：S4-00～S4-09 十项 ↔ CAP-1～10 一一对应、无遗漏；验收清单 5 条全部进入完成定义（第 1 条→CAP-5、第 2 条→CAP-4、第 3 条→CAP-6、第 4 条→CAP-7、第 5 条→发布窗口后内测）。docs/03 §9 设置表阶段 4 各行、§12 引导、§13 快捷键、§14 备份失败行均已落 CAP。
- **唯一缺口**：菜单栏正式图标（见 P2-3）。
- **Non-goals 检查**：URL Scheme 与导入向导未混入任何 CAP ✅；S5 各项占位策略与 03 §9/SettingsTab 现状一致 ✅；「增量更新/Developer ID/CI 发布/CHANGELOG/清除前提醒」五项排除均与 ADR-032、epics、02 对应 ✅（显式化建议见 P3-5）。
- **决策点落死核查**（对照 epics 遗留的"规格阶段定"项）：脚本名 ✅、release notes 来源 ✅、sign_update 定位 ✅（但语境错位 P2-1）、私钥注入口径 ✅、保留份数范围 1–30 ✅、备份失败态规则 ✅、导出入口形态（直达）✅、引导触发双条件 ✅、截图落点 `.github/assets/` ✅、`--publish` 门闩 ✅——**全部写死，无悬空"规格阶段定"**。

## 5. 环境备注（非 SPEC 问题）

盲审期间注意到仓库根出现未跟踪文件 `shike.sqlite`（含 -wal/-shm）与 `Backups/`——疑似夜间并行卡（卡C 性能补测/卡D AX 采集）的隔离实例把数据目录落在了仓库根。非本卡创建、本卡未触碰；提醒收口人：**明早任何提交切勿 `git add -A`**，并请卡C/卡D 核对各自的 `-ShikeDataDirectory` 参数落点，测后清理。

---

*卡A 完 · 2026-10-03 夜｜盲审人：夜间执行会话｜对照基线：SPEC@9f868d5、docs 全量、epics 拍板版、audit、代码 HEAD 9f868d5*
