- source_spec: `_bmad-output/implementation-artifacts/spec-1-1-project-skeleton.md`
  summary: 【已解决·1.17】app-shell.md「文件布局」列有 Shike/Resources/Assets.xcassets，但 Epic 1 的 17 个故事没有任何一个负责创建它。
  evidence: 已核实仓库中只有 Resources/Localizable.xcstrings；app-shell.md 该行已修订为"阶段 0 用 SF Symbol，正式图标（阶段 4）再建资产目录"，04 §2 同步。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: 【已解决】推送 stage-0/foundation 后确认 CI 三作业（checks/package-tests/app）首次全绿。
  evidence: 2026-09-26 起 CI 三作业运行；发现并修复 app 作业自 1.12 起的红灯（AboutPageTests @MainActor，Xcode 26/27 隔离检查差异，8471846），见 spec-1-12 台账与 ADR-019。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: 【已解决】CI 的 Xcode 26.6 对字符串目录生成符号的支持性确认。
  evidence: app 作业自 1.8 起在 CI（Xcode 26.6）编译通过，STRING_CATALOG_GENERATE_SYMBOLS=YES 可用，无需回退。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: 【已解决】开启 main 分支保护（要求三项作业通过、仅限 PR 合并）。
  evidence: 2026-09-26 经产品负责人明确授权后用 gh API 设置并验证：contexts checks/package-tests/app（strict）、1 个审查通过且过时审查失效、enforce_admins=false（06 §5 已写回）。
- source_spec: `_bmad-output/implementation-artifacts/spec-1-2-ci-pipeline.md`
  summary: ci.yml 同时触发 push 与 pull_request，同一 PR 的推送会跑两遍完整流水线且 concurrency 组互不取消；可考虑 push 限 main 或按分支名归一 concurrency 组。
  evidence: 1.2 评审发现；双触发是 stack.md「CI 工作流」的既定规定，改动属于规格层决定，留给产品负责人裁量。

## 面板提示条的重试生命周期（S1 写路径故事时处理）

来自 Story 1.10 盲审（2026-09-27）：
1. saveFailed 提示条显示期间观察流又以 readFailed 结束时，report 会覆盖 banner 与 bannerRetry，原写入重试闭包丢失；重新订阅清掉 loadFailed 条后，那次失败的写再无重试入口。
2. saveFailed 提示条在重试成功后无人清除（重试闭包无成功回调；阶段 0 没有写路径）。
S1-10（写路径）实现真实写入重试时一并设计：重试闭包携带完成回调，或提示条带标识按需清除。

## Story 2.8 必须接走的交接（来自 2.6，2026-09-28）

1. **编辑清空=删除（可撤销）**：saveNoteContent 已把 trim 后为空的编辑转 softDelete（03 §5/§7）——撤销提示条与 ⌘Z 须把这条删除通路也纳入栈。
2. **面板收起的保存是 fire-and-forget Task**：App 存活则可靠；收起后立即退出 App 有极小丢失窗口——撤销栈/stop() 设计时一并考虑（stop 前 flush）。
3. **面板提示条的重试生命周期**（1.10 遗留，2.4 已修一半：重试绑定当次输入、成功清条）——与撤销条并存时的互斥/覆盖关系在 2.8 统一设计。
