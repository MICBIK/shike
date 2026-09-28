# 拾刻 Shike：给 AI 助手的项目说明

macOS 菜单栏便签与待办应用。与产品负责人 MICBIK 用简体中文交流，文档也用简体中文。

## 从哪里开始

- 所有需求、设计和决策以 `docs/` 为准，从 [docs/README.md](docs/README.md) 开始读。
- 当前进度看 [docs/02-阶段路线图.md](docs/02-阶段路线图.md) 顶部的状态表。
- 开发流程使用 BMAD-METHOD，每个阶段的步骤见 [docs/06-开发规范.md §8](docs/06-开发规范.md#8-阶段工作流程)。不确定下一步做什么时，调用 `bmad-help`。
- 阶段规格和故事须经产品负责人确认后，才能开始写代码。

## 硬性约束

- 最低系统 macOS 15；Swift 6 语言模式，严格并发检查；使用 Xcode 26 或更高版本编译（CI 使用 `macos-26` 镜像）。
- 界面代码不直接访问数据库；`Packages/ShikeKit` 中的代码不引入 AppKit 或 SwiftUI（[docs/04 §1](docs/04-技术架构.md#1-总体结构)）。
- 不静默吞掉错误；保存失败时保留用户的输入（ADR-013）。
- 一个行为有多种合理形式时，做成用户可选项并给出默认值，不要写死（产品原则，[docs/01 §4](docs/01-产品定义.md#4-产品原则)）。
- 项目以 GPL-3.0-only 发布：每个源文件都带文件头；移植 [Reminders MenuBar](https://github.com/DamascenoRafael/reminders-menubar) 的代码时，须注明来源和修改说明，并登记到 NOTICE.md（[docs/06 §9](docs/06-开发规范.md#9-gpl-合规)）。
- 依赖一律锁定精确版本；新增依赖的许可证须与 GPL 兼容，并在 docs/07 中记录决策。
- 修改中文日期解析规则时，同时更新 [docs/05](docs/05-中文日期解析规格.md) 的用例表和对应测试。
- "完成"以 CI 和实测为准（[docs/06 §7](docs/06-开发规范.md#7-完成的定义)），不以文档中的声明为准。

## 常用命令

```bash
xcodegen generate                             # 生成 Shike.xcodeproj（不入库）
swift test --package-path Packages/ShikeKit   # 解析与数据层测试（L1）
bash scripts/checks.sh                        # 架构合规检查（与 CI 的 checks 作业同一份脚本）
SHIKE_WARNINGS_AS_ERRORS=YES xcodebuild -project Shike.xcodeproj -scheme Shike \
  -destination 'platform=macOS' test          # App 层测试（L2）；本地可省略环境变量（警告即错误只在 CI 开启，ADR-019）
```
