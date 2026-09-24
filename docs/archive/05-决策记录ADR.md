# TZMemo 架构决策记录（ADR）

> 文档编号：05 ｜ 状态：生效中 ｜ 格式：背景 → 决策 → 理由 → 后果
> 原则：决策一经记录不再反复重开；推翻须新增 ADR 并链接旧条目。

## ADR-001 技术栈：原生 Swift/SwiftUI + AppKit（2026-09-23 定稿）

**背景：** 初期目标三端（Win/Android/macOS）同期启动时曾推荐 Flutter；后调整为 Mac 先行，并做了三路深度技术调研（Flutter 桌面生态 / Tauri 2 / 品类先例）。
**决策：** macOS 版使用 Swift 6 + SwiftUI，关键形态用 AppKit（NSStatusItem/NSPopover/NSPanel）。
**理由：** ① 知名 Mac 菜单栏便签应用全部为原生（Tot/Antinote/SideNotes/Dropover 等），无一非原生案例；② Flutter 无 NSPopover 等价物，此形态必须写 Swift 胶水代码，总学习量反而更大，且关键插件停滞（auto_updater 23 个月等）、内存为原生 2 倍（常驻应用硬伤）、无成功先例；③ demo 即 1 万行 Swift 参考实现；④ Tauri 2 桌面成熟但仅当开发者是 Web 前端背景才值得，且移动端缺口仍在。
**后果：** Win/Android 未来走独立 Flutter 栈（ADR-002）；解析规则表需二次实现。

## ADR-002 平台顺序：macOS → iOS → Windows/Android（双栈）

**背景：** 用户判断 Windows 托盘弹层体验上限低于 macOS 菜单栏面板，且产品灵魂在 Mac 形态。
**决策：** Mac 先行；iOS 复用 Swift 业务逻辑；Windows+Android 由未来 Flutter 栈覆盖，时机由 Mac 版反馈决定。
**后果：** 短期放弃非 Mac 用户；同步后端必须选跨平台方案（ADR-003）。

## ADR-003 数据方案：本地 SQLite（GRDB）+ 同步预埋，远期跨平台 BaaS

**背景：** 无开发者账号 → CloudKit/MAS 不可用；曾考虑"桥接 Apple 备忘录"被否（能力受限且与自有客户端冲突）。
**决策：** MVP 本地 GRDB/SQLite；schema 预埋 uuid/updatedAt/软删；未来同步用 LeanCloud/Supabase 类跨平台 BaaS 或自建，按字段 LWW。**不用 CloudKit。**
**后果：** Repository 收敛（MemoStore）是纪律红线；同步立项时业务代码不动。

## ADR-004 提醒实现：本地通知（UNUserNotificationCenter），不桥接 EventKit

**背景：** demo 桥接 Apple Reminders；本项目提醒是待办自身属性。
**决策：** 提醒走本地通知；待办不写入系统提醒事项。
**理由：** 与本地数据自洽；无权限摩擦；跨平台移植时语义不变。
**后果：** 通知权限被拒需 UI 降级（UX §5）。

## ADR-005 分发与更新：GitHub Releases + Sparkle EdDSA + 国内镜像

**决策：** 不上 MAS；macOS Sparkle 2 自签名更新（无需开发者账号），appcast 放 GitHub；Android 应用内查 Releases 下载 APK；更新检查配镜像源。
**后果：** macOS 未签名应用需"右键打开"，必须写安装说明；SmartScreen 警告同理；商业化后再买签名证书。

## ADR-006 便签与待办为两个独立实体

**决策：** note/todo 分表分模型；快速输入栏双模式切换；解析只在待办模式生效。
**理由：** 用户明确要求分开；字段差异大（颜色/置顶 vs 提醒/重复/完成）。
**后果：** 部分代码重复（可接受）；"便签转待办"成为潜在 P2 功能。

## ADR-007 中文日期解析：自研纯函数规则引擎

**决策：** 不引第三方（无成熟 Swift 中文库；chrono-node 是 JS），自研规则引擎；规则表+144 断言作为语言无关资产，供未来 Dart 版移植。
**理由：** 中文日期为刚需（用户确认）；规则可穷举可测试；纯函数无状态，UI 高亮区间直接可用。

## ADR-008 工程化：XcodeGen 管理工程

**决策：** 工程文件由 project.yml 生成（xcodegen generate），pbxproj 不手工维护。
**理由：** AI/CLI 协作下 diff 友好、可复现；避免 pbxproj 合并地狱。
**后果：** 改工程结构必须改 project.yml 并重新生成；README 已写明。

## ADR-009 协作流程：文档先行 + 确认制（2026-09-23，因流程复盘引入）

**背景：** M1 代码在缺少设计/任务文档的情况下先行产出，被产品负责人指出流程缺陷。
**决策：** 每迭代动工前，AI 产出任务清单+设计方案，经确认后实现（章程 §5）；本套 00-07 文档即为流程修正的产物。
**后果：** 迭代节奏变重是可接受代价；M1 已有代码按「补齐文档 → 验收」顺序补办手续。
