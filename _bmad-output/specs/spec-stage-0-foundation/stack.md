# 技术栈、工程配置与 CI

版本和取值核对于 2026-09-25。标注"已实测"的条目，已在 `/tmp` 的探针工程中用 Xcode 27.0 验证过。

## 版本

| 项 | 取值 | 说明 |
|---|---|---|
| 部署目标 | macOS 15.0 | ADR-003 |
| Swift 语言模式 | 6（严格并发检查） | project.yml 中 `SWIFT_VERSION: 6.0`；Package.swift 中 `swiftLanguageModes: [.v6]` |
| `swift-tools-version` | 6.2 | Xcode 26.0 起都能解析；支持 SE-0480 的 `treatAllWarnings` |
| Xcode（CI） | `macos-26` 镜像默认版本，镜像 20260907 为 26.6 | 06 §5；日志中打印 `xcodebuild -version` |
| Xcode（本地） | 27.0（Swift 6.4） | 比 CI 新。不用 CI 工具链中没有的语言特性或 SDK 接口；两边不一致时以 CI 为准 |
| GRDB.swift | 7.11.1，`exact:` | MIT；要求 tools 6.1；7.x 的最新版本 |
| XcodeGen | 2.46.0 | CI 下载 release 中的 `xcodegen.zip`，SHA-256 为 `4d9e34b62172d645eed6457cac13fc222569974098ef4ee9c3368bedf0196806`；project.yml 中设置 `minimumXcodeGenVersion: 2.46.0` |
| 测试框架 | Swift Testing（随工具链） | ADR-012 |
| actions/checkout | v7.0.1，以提交 SHA 锁定：`3d3c42e5aac5ba805825da76410c181273ba90b1` | 其他 action 也一律用 SHA 锁定，并在注释中写明版本号 |

## project.yml 要点

- `name: Shike`；`options`：`deploymentTarget.macOS: "15.0"`、`developmentLanguage: zh-Hans`、`minimumXcodeGenVersion: 2.46.0`、`createIntermediateGroups: true`。
- `packages.ShikeKit.path: Packages/ShikeKit`。App 只依赖 `ShikeData` 和 `ShikeDateParser` 两个产品，不直接依赖 GRDB。
- 工程级 `settings.base`：
  - `CODE_SIGN_IDENTITY: "-"`、`CODE_SIGN_STYLE: Manual`、`DEVELOPMENT_TEAM: ""`，即 ad-hoc 签名，本地与 CI 相同（ADR-011）。
  - `ENABLE_HARDENED_RUNTIME: NO`；不提供 entitlements，即不启用沙盒。
  - `SWIFT_TREAT_WARNINGS_AS_ERRORS: "$(SHIKE_WARNINGS_AS_ERRORS:default=NO)"`（已实测，原因见下节）。
  - `STRING_CATALOG_GENERATE_SYMBOLS: YES`（Xcode 26 引入；已在 Xcode 27 上实测，Xcode 26.6 的支持在首次 CI 运行时确认，不支持时改用 `String(localized: "键")`）、`LOCALIZATION_PREFERS_STRING_CATALOGS: YES`。
- `Shike` 目标：
  - `type: application`；`PRODUCT_NAME: Shike`；`PRODUCT_BUNDLE_IDENTIFIER: io.github.micbik.shike`。
  - `MARKETING_VERSION: 0.0.0`、`CURRENT_PROJECT_VERSION: 1`。
  - `GENERATE_INFOPLIST_FILE: YES`，并设置 `INFOPLIST_KEY_LSUIElement: YES`、`INFOPLIST_KEY_CFBundleDisplayName: 拾刻`、`INFOPLIST_KEY_NSHumanReadableCopyright: "Copyright (C) 2026 Shike contributors"`、`INFOPLIST_KEY_LSApplicationCategoryType: public.app-category.productivity`。
  - `sources` 中除 `Shike` 外，再加上根目录的 `LICENSE`（`buildPhase: resources`），把许可证原文直接打包进 App，不在仓库中另存副本。
- `ShikeTests` 目标：`type: bundle.unit-test`；依赖 `Shike`；`TEST_HOST: $(BUILT_PRODUCTS_DIR)/Shike.app/Contents/MacOS/Shike`、`BUNDLE_LOADER: $(TEST_HOST)`；`GENERATE_INFOPLIST_FILE: YES`。
- `schemes.Shike`：
  - build 包含 `Shike`（all）和 `ShikeTests`（test）；test 目标为 `ShikeTests`。
  - test 的 `environmentVariables` 设置 `SHIKE_TEST_HOST: "1"`（已实测）。
  - run 的 `commandLineArguments` 预置 `-ShikeSimulateDatabaseOpenFailure YES`、`-ShikeSimulateWriteFailure YES`、`-ShikeDataDirectory /tmp/shike-dev`，三项都默认不勾选。
- Info.plist 的自定义键（阶段 4 的 `SUFeedURL`、`SUPublicEDKey`）到时再以局部 Info.plist 文件加入，阶段 0 不建该文件。

## ShikeKit（Package.swift）要点

- 第一行必须是 `// swift-tools-version: 6.2`，06 §9 的文件头紧接其后。
- `platforms: [.macOS(.v15)]`；产品为 `ShikeDateParser`、`ShikeData`；依赖 `.package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")`。
- 目标：
  - `ShikeDateParser`：无依赖。
  - `ShikeData`：依赖 GRDB。
  - `ShikeDateParserTests`：依赖 `ShikeDateParser`。
  - `ShikeDataTests`：依赖 `ShikeData` 和 GRDB，测试中可以直接使用 GRDB 检查库文件。
- 通过环境变量启用严格警告：`SHIKE_WARNINGS_AS_ERRORS=YES` 时，给四个目标加上 `.treatAllWarnings(as: .error)`（已实测；只作用于本包，不影响 GRDB）。
- `Packages/ShikeKit/Package.resolved` 入库（06 §3）。

## 警告即错误：只在 CI 开启

- 不要在 xcodebuild 命令行直接传 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`。它会作用到 GRDB，并报错 `Conflicting options '-warnings-as-errors' and '-suppress-warnings'`（已实测）。
- 正确做法：CI 的作业环境设置 `SHIKE_WARNINGS_AS_ERRORS=YES`，xcodebuild 也传入 `SHIKE_WARNINGS_AS_ERRORS=YES`。工程目标通过 `$(SHIKE_WARNINGS_AS_ERRORS:default=NO)` 读取该值，ShikeKit 通过环境变量读取；GRDB 不受影响。
- 本地默认宽松：更新的 Xcode 可能带来 CI 上没有的新弃用警告，不应因此阻塞本地开发；这类警告在合并前按 CI 的结果处理。

## CI 工作流（`.github/workflows/ci.yml`）

- 触发：`push`（`branches: ['**']`）和 `pull_request`（06 §5）。
- `concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }`；`permissions: contents: read`；每个作业 `timeout-minutes: 30`。
- 作业名固定，分支保护按名称绑定：

| 作业 | 运行器 | 步骤 |
|---|---|---|
| `checks` | ubuntu-latest | 文件头检查；导入边界检查；解析器区域检查（规则见 conventions.md §检查项） |
| `package-tests` | macos-26 | `xcodebuild -version`；设置环境变量 `SHIKE_WARNINGS_AS_ERRORS=YES` 后运行 `swift test --package-path Packages/ShikeKit` |
| `app` | macos-26 | `xcodebuild -version`；下载 XcodeGen 2.46.0 的 zip，用 `shasum -a 256 -c` 校验后解压，运行其中的 `xcodegen/bin/xcodegen generate`；然后运行 `xcodebuild -project Shike.xcodeproj -scheme Shike -destination 'platform=macOS' SHIKE_WARNINGS_AS_ERRORS=YES build test` |

- 缓存（SwiftPM、DerivedData）可以加，不是必需的；加的话以 `Package.resolved` 的哈希作为缓存键。

## 分支保护（CAP-12）

`stage-0/foundation` 上的 CI 首次全部通过后、合并阶段 0 的 PR 之前，给 main 开启保护：要求 `checks`、`package-tests`、`app` 三项通过，要求通过 PR 合并（06 §6，squash 合并）。这样阶段 0 的合并本身也受保护。这是对外部服务的设置变更，由产品负责人执行，或经其明确授权后执行。
