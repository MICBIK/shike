---
title: 'Story 1.17 架构交接'
type: 'docs'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 1
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/data-layer.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/stack.md'
  - '{project-root}/docs/04-技术架构.md'
  - '{project-root}/docs/06-开发规范.md'
  - '{project-root}/docs/07-决策记录.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 阶段 0 的实现知识散落在规格伴随文件和实现提交里：docs/04 仍是实现前的设计稿（ShikeData 契约、启动流程、备份细节、调试参数语义与实现有出入），conventions.md 的约定在 docs 中没有落点，CLAUDE.md 的"常用命令"还标注"阶段 0 完成后可用"。接手阶段 1 的人只读 docs/ 无法开工。

**Approach:** ①docs/04 写回实现验证过的契约：模块与目录（实际文件清单）、ShikeData 公开 API（AppDatabase/Options、Domain/Records 分离、三仓储、观察流语义与 GRDB 实现补充、错误分类）、备份与迁移前备份要点、组装点与启动顺序（含测试宿主与提示循环）、调试参数语义（`-Flag=值`、裸旗标判无效）、§7 移植清单保持与 NOTICE 一致；②04 新增 §11"扩展指南"，八项各给步骤与示例位置：新增仓储方法、偏好键、设置分页、界面文案、服务、调试参数、移植文件、数据库迁移；③conventions.md 并入 docs：细则进 06 新 §12"编码细则"，两条重大取舍立 ADR-019（警告即错误只在 CI、经 SHIKE_WARNINGS_AS_ERRORS）与 ADR-020（公开类型与内部 Record 分离）；④核对 06/CLAUDE.md/README/NOTICE 与 CI 实测一致（06 §5 改为三作业与分支保护实况，CLAUDE.md 常用命令去标注并补 xcodebuild/checks.sh）；⑤02 阶段 0 验收第 1 条改为两段式表述，阶段 0 状态保持"进行中"；⑥按 deferred-work.md 的处置修订 app-shell.md 的 Assets.xcassets 行；⑦deferred-work.md 四项挂起事项标记已解决并附证据。

## Boundaries & Constraints

**Always:** 文档中的命令与事实以 CI 实测为准；与实现不符的规格措辞一并修订（newerSchema"未写入"按逻辑内容表述、readFailed 注入机制偏差已在 data-layer.md 落档）；本故事只改文档，不改产品代码。

**Never:** 不把阶段 0 状态改为"已完成"（第 ⑧ 步由人工验收后执行）；不删除规格伴随文件（并入而非替换，往期规格只读原则不适用于本次明确的收尾修订）；不引入新的产品决策（超出既有 ADR 的事实写回）。

</frozen-after-approval>

## Implementation Notes

- 04 写回（提交 `文档提交` 见 git log）：§2 目录按实际文件改写（App 六文件、Settings 六文件、ShikeData 根文件 + Domain/Records/Repositories、解析器四文件；Resources 只有 Localizable.xcstrings，正式图标阶段 4 再建资产目录）；§4.2 重写为验证契约（open 六步、Options 三字段、Domain/Records 分离与 uuid 静态函数、三仓储与 notFound、三个观察流与排序、GRDB 7.11 两条实现补充、ShikeDataError/DataFailureReason 全量、classification 日志）；§4.3 组件表对齐实际（LaunchOptions、DatabaseOpenFailureAlert、MainMenu.make、LicenseWindowController 等）并写入日志 category 与隐私规则；§6.1 启动顺序按实现写死（SHIKE_TEST_HOST → LaunchOptions → 数据目录 → 打开循环 → 组装 → 主菜单/设置/右键/图标/面板 → start() × 2）并补 Swift 6 撤销选择器须 @objc 协议重命名；§6.6 补齐备份实现要点（journal_mode=DELETE、侧车清理、临时文件原子改名、轮换正则、迁移前备份命名/去重/失败路径）与调试参数两写法语义；§6.9 标注已实现（460×320、show(tab:)、onViewLicense、占位阶段号）并留"前置失败补 orderFrontRegardless"的人工验收指引；§8 并发模型补显式 @MainActor/默认隔离不启用/Task 取消/NSRegularExpression 静态化/assumeIsolated 限定；§5.1 补迁移命名与两类测试；§9 测试覆盖更新为 125/75/34 基线；新增 §11 扩展指南八节。
- 06：§5 重写（三作业、concurrency 取消、XcodeGen SHA 校验、Xcode 26/27 差异实例与"以 CI 为准"、分支保护实况）；§4.2 补 T0/内存库/临时磁盘库/L2 组装规则；§11 补参数写法与临时目录告诫；新增 §12 编码细则（12.1 组装、12.2 并发指针、12.3 错误、12.4 偏好与调试参数、12.5 移植补充、12.6 禁止清单速查）——conventions.md 的检查项细则并入 §5 checks 条目，文案规则并入 04 §11.4。
- 07：ADR-019（命令行直传 SWIFT_TREAT_WARNINGS_AS_ERRORS 与 GRDB 冲突已实测；环境变量方案；Xcode 26/27 隔离检查差异教训）、ADR-020（internal import 下公开类型无法遵循 GRDB 协议已实测；Domain/Records 分离；uuid 编码必须静态函数，静态属性被静默忽略退回 BLOB）。
- CLAUDE.md："常用命令（阶段 0 完成后可用）"→"常用命令"，补 checks.sh 与 xcodebuild test（注明本地可省略警告环境变量）。README/NOTICE 核对：README 四条命令与 CI 一致；NOTICE 三行移植登记与 04 §7 一致（盲审指出 PopoverController 的来源在 04 §7 少列一个文件，已补齐），GRDB 7.11.1 exact 与 Package.resolved 一致——README 未改动。
- 02：阶段 0 验收第 1 条改两段式（合并前以 stage-0/foundation 三项全绿 + 分支保护为准；合并后由 main 首次 CI 复核）；阶段 0 状态保持"进行中"。
- 规格修订：app-shell.md 文件布局的 Assets.xcassets 行按 deferred-work 处置修订；data-layer.md 的观察补充与"未写入"措辞已在 1.4 盲审轮落档，本轮复核无需再改。
- deferred-work.md：四项标记【已解决】并附证据（CI 首绿+红灯修复、字符串目录符号 CI 支持确认、分支保护实况、Assets 行修订）；ci.yml 双触发裁量项保持开放（规格层决定，留给产品负责人）。
- 本故事无产品代码改动；测试基线不变（包 75、App 34）；checks.sh 通过。盲审复核了基线数字（实际运行两套测试）与 docs/05 的 125 行用例数，均为真。

## Review Triage Log

盲审（Blind Hunter）第 1 轮结论 needs-fixes（1 high / 1 medium / 5 low / 2 false），全部处置如下：

- [high→已修] 04 §4.2 备份签名写成旧契约措辞 `backupIfNeeded(into:keep:)`，实现为 `to:keep:`（Backup.swift:17；spec-1-13 已更正过，写回时带回了旧措辞）。已改为 `to:keep:`，app-shell.md 的 `into:` 一并更正并注明修订。
- [medium→已修] 06 §12.4 锚点 `#55-偏好设置-userdefaults` 断链（GitHub slugger 剥全角括号不补连字符，实际锚点为 `#55-偏好设置userdefaults`）。已更正。
- [low→已修] 04 §11.4 示例归因错误：`banner.saveFailed` 的消费点在 PanelModel.swift，Banner.swift 只用 `.bannerRetry`。示例已改为"PanelModel.swift（经 Banner.swift 展示）"，并补回 conventions 原文的"面向用户的"限定词。
- [low→已修] 04 §2 的 `scripts/` 注释"发布脚本（阶段 4）"与新增内容矛盾（checks.sh 是阶段 0 的 CI 合规脚本）。已改为"合规检查脚本（checks.sh，CI 与本地共用）；发布脚本（阶段 4）"。
- [low→已修] 04 §4.2 "`create` 与 `pin` 返回新建的模型"对 pin 不完全成立（已钉出时返回现有卡片、不改动，StickyCardRepository.swift:17-41）。已补幂等分支。
- [low→已修] 06 §12 引言病句（"以这里为准之一"、自指）。已改为"作为 06 的一部分生效；与 06 其他章节重复的部分以本节为准，与规格 conventions.md 冲突时以本文为准"。
- [low→已修] NOTICE 与 04 §7 的 PopoverController 来源文件数不一致（NOTICE 多列 `Comparable+Extensions.swift`（constrainedTo））。04 §7 已补齐，两处一致；Implementation Notes 的表述随之更正。
- [false] "§4.2 池观察感知不到其他连接的提交"无源——实有据：spec-1-4 台账记录了实测（外部 INSERT 不触发推送）。
- [false] "§11.3 占位阶段号归零"措辞不准——实现是 `placeholderStage` 置 nil，语义等价，保留原表述。
- 评审过程：只读评审；评审者复跑两套测试（75/34 全绿）、逐一核验 15 个锚点、06 §12 与 conventions.md 逐条对照无遗漏、ADR-019/020 与 stack.md"已实测"条目吻合。
- [后续基线变更] 全量代码评审修复解析器缺陷后新增 1 个回归测试，包测试基线 75→76（04 §9 已同步）。
