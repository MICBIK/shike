---
title: 'Story 1.1 搭建工程骨架'
type: 'feature'
created: '2026-09-26'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/stack.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 仓库还没有工程与代码骨架：克隆后无法生成工程、构建 App 或运行测试，后续 16 个故事没有统一起点。

**Approach:** 按验收标准搭建：project.yml（XcodeGen 2.46.0）+ Packages/ShikeKit（swift-tools 6.2，GRDB exact 7.11.1，四目标）+ Shike App 骨架（main.swift/AppDelegate、LSUIElement、测试宿主守卫）+ ShikeTests（符号读 `app.name`）+ 根文件核对（LICENSE 逐字、NOTICE 登记 GRDB 7.11.1 与基线 e3c0260、README 实测步骤）。全部 `.swift` 文件带 06 §9 文件头。验收命令：`xcodegen generate`、`swift test --package-path Packages/ShikeKit`、`xcodebuild -scheme Shike build test`，以及 `SHIKE_WARNINGS_AS_ERRORS=YES` 下的严格编译验证。硬约束全部以 context 中 stack.md / conventions.md / app-shell.md 为准（版本逐字、禁止清单、文件布局）。

</frozen-after-approval>

## Implementation Notes

- （规划期判断，已按此实现）SwiftPM 目标不允许零源文件，而 ShikeDateParser/ShikeData 的实体类型分别属于 1.15/1.3。处置：给两个库目标各放一个"契约定死、无行为、后续只扩展不重写"的纯类型——ShikeData 放错误分类 `ShikeDataError`+`DataFailureReason`（data-layer.md §错误分类逐字），ShikeDateParser 放值类型 `DateParseResult`（parser.md §公开 API 逐字）；不实现任何行为逻辑。1.15 实现时确认 DateParseResult 已就位、无需重复定义。
- 生成的字符串符号：Xcode 27 实际生成 `LocalizedStringResource.appName`（点分段转驼峰，挂在 `LocalizedStringResource` 上），取值为 `String(localized: .appName)`。已实测；Xcode 26.6（CI）的支持在 1.2 的首次 CI 运行确认，不支持时回退 `String(localized: "app.name")`。
- project.yml 初版漏了 `SWIFT_VERSION: "6.0"`（stack.md 要求），XcodeGen 缺省按 Swift 5 模式编译，`main.swift` 顶层调 `@MainActor` AppDelegate 报错；补上后构建通过。stack.md 的 project.yml 要点已含此项，是实现时遗漏。
- 警告即错误验证的一个发现：Swift 6.4（Xcode 27）下"actor 隔离"类轻量警告不被 `-warnings-as-errors` 升级（已用 swiftc 手动探针证实），弃用警告正常升级、注入弃用警告后严格构建如期失败。CI 的零警告以升级类警告为准；隔离类警告在 Swift 6 语言模式下多数本就是错误，风险低。
- Package.swift 顶层 `ProcessInfo` 需要 `import Foundation`（清单编译环境默认无 Foundation）。
- 验收全部通过：xcodegen generate、swift test（4 项）、xcodebuild build test（含符号测试）、严格模式包测试、严格模式注入警告失败验证、Info.plist 六项值核对、LICENSE 与 gnu.org 逐字一致（diff）、全部自有 .swift 带 06 §9 文件头、构建后 git status 只含预期源文件。

## Review Triage Log

- Blind Hunter#1（commandLineArguments 对象写法被 XcodeGen 静默丢弃）：medium，属实——已复现；改为布尔写法并在生成的 Shike.xcscheme 的 LaunchAction 块中验证三项参数 isEnabled=NO。初查时误把 TestAction 的空参数块当成 LaunchAction，一度误判布尔写法也失效；探针与最终验证均以 LaunchAction 块为准。
- Blind Hunter#2（Assets.xcassets 无人认领）：属实，属规格与故事间的缺口——已记入 deferred-work.md，留待 1.17 收尾修订 app-shell.md，不补建空目录。
- Blind Hunter#3（README 缺 runFirstLaunch 与 brew 安装命令）：属实——已补两处前提，与 06 §1 原文核对一致。
- Blind Hunter#4（测试中 try? 无注释违反 conventions.md）：属实——已补注释说明为何可忽略。
- Blind Hunter#5（/tmp/shike-tests 父目录残留）：属实——已修复：清理改为连同父目录一并删除（defer 调用）。
- Blind Hunter#6（matchedRanges 文档与测试对契约归属说法相反）：属实——文档改为"解析器产出有序不重叠区间，本类型是被动持有者"。
- Blind Hunter#7（invalidLocation 注释漏"的文件 URL"）：属实——已按 data-layer.md 逐字补齐。
- Blind Hunter#8（GRDB 并发证明只走同步 API）：属实——补 asyncWrite/asyncRead 测试，严格并发下通过。
- Blind Hunter#9（DateParseResultTests 不该用 @testable）：属实——改普通 import（失去 public 时编译失败），并补 date 字段断言。
- Blind Hunter#10（main.swift 多余全局常量 application）：属实——内联 NSApplication.shared，只保留 app-shell.md 规定的 appDelegate 全局常量。
- Blind Hunter#11（AppDelegate 空函数体缺占位说明）：属实——函数体内补"启动流程由 1.7～1.9 补入"注释。
- Blind Hunter#12（NOTICE 基线提交出处不明）：false——`git branch -r --contains e3c0260` 证实该提交在上游 origin/master 可达（上游仓库本地克隆验证），NOTICE 写法正确。
- Blind Hunter#13（sprint-status.yaml 的 project_key: NOKEY）：驳回——这是 sprint_plan.py 在无跟踪系统时的哨兵值（模板同款），不是未替换的占位符；手改会偏离工具输出契约。
