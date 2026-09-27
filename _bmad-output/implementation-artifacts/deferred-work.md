- source_spec: `_bmad-output/implementation-artifacts/spec-1-1-project-skeleton.md`
  summary: app-shell.md「文件布局」列有 Shike/Resources/Assets.xcassets，但 Epic 1 的 17 个故事没有任何一个负责创建它。
  evidence: 评审发现规格与故事间存在无人认领的文件；阶段 0 中界面图标全部用 SF Symbol，可能并不需要资产目录。处置：在 1.17 收尾写回 docs 时修订 app-shell.md（删除该行或明确归属），不要凭空补建空目录。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: 推送 stage-0/foundation 后确认 CI 三作业（checks/package-tests/app）首次全绿。
  evidence: CI 只能在 GitHub Actions 上运行；通宵模式约定不推送。由产品负责人早晨推送后核对。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: CI 的 Xcode 26.6 若不支持字符串目录生成符号，按 stack.md 回退 `String(localized:)` 并同步 stack.md、conventions.md 与相关验收措辞。
  evidence: 符号生成已在本地 Xcode 27.0 实测；CI 镜像版本支持性只能由首次 CI 运行确认（见 spec-1-2 与 stack.md）。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: CI 首次全绿后、合并阶段 0 之前，由产品负责人开启 main 分支保护（要求三项作业通过、仅限 PR 合并），或明确授权后用 gh 执行。
  evidence: A8 决定与 stack.md「分支保护」：这是对外部服务的设置变更，须产品负责人执行或明确授权。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: ci.yml 同时触发 push 与 pull_request，同一 PR 的推送会跑两遍完整流水线且 concurrency 组互不取消；可考虑 push 限 main 或按分支名归一 concurrency 组。
  evidence: 1.2 评审发现；双触发是 stack.md「CI 工作流」的既定规定，改动属于规格层决定，留给产品负责人裁量。

## 面板提示条的重试生命周期（S1 写路径故事时处理）

来自 Story 1.10 盲审（2026-09-27）：
1. saveFailed 提示条显示期间观察流又以 readFailed 结束时，report 会覆盖 banner 与 bannerRetry，原写入重试闭包丢失；重新订阅清掉 loadFailed 条后，那次失败的写再无重试入口。
2. saveFailed 提示条在重试成功后无人清除（重试闭包无成功回调；阶段 0 没有写路径）。
S1-10（写路径）实现真实写入重试时一并设计：重试闭包携带完成回调，或提示条带标识按需清除。
