---
title: 'Story 1.4 便签的保存与观察'
type: 'feature'
created: '2026-09-26'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/data-layer.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 界面还不能安全地读写便签：需要仓储层把"新建、修改、置顶、删除、恢复"变成可组合的操作，并用观察流把数据变化推给界面，界面代码从此不碰数据库。

**Approach:** 按 data-layer.md 实现公开模型（Note/Note.ID/NoteListItem）、内部 NoteRecord（静态函数 databaseUUIDEncodingStrategy → 小写文本 uuid）、NoteRepository（六个写方法 + observeActive）与三仓储共用的写路径（performWrite：simulateWriteFailure 短路、transactionDate 时间戳、错误映射为 writeFailed）。观察流以 AsyncThrowingStream 桥接 ValueObservation，去重、先推当前值、失败以 readFailed 结束、取消即停。

## Boundaries & Constraints

**Always:** 公开 API 不出现 GRDB 类型；写方法只抛 ShikeDataError；updatedAt 只随内容变化更新（ADR-017）；时间戳全部取自注入时钟。

**Never:** 不实现待办/卡片仓储（1.5/1.6 沿用 performWrite）；不引入 try? 吞写错误；不给已发布的迁移做任何修改。

</frozen-after-approval>

## Implementation Notes

- 1.3 遗留项落地：uuid 存储格式断言（typeof=text、36 位小写正则）在本故事的 create 测试中实现，经 NoteRecord 的 GRDB 编码路径，符合 L1 清单的本意。
- performWrite 是三个仓储共用的写入口（simulateWriteFailure 与错误映射只写一次）；AppDatabase.options 改为 internal 供其读取；init 改 internal 供只读连接测试构造。
- 观察流的关键实测（GRDB 7.11.1 + Xcode 27）：
  1. `values(in:)` 的异步桥接在观察**失败**时表现为"正常结束"，错误会被吞掉——失败必须经我们自己的桥接层转换为 readFailed；
  2. 被观察的表被删除后（无论外部还是自身连接），观察**静默挂起**：不重取、不报错、不结束。因此桥接层把"活观察结束"一律视为读取通道断开，以 `readFailed(.ioError)` 结束流；
  3. 池观察**感知不到外部连接的提交**（实测外部 INSERT 不触发推送），史诗验收中"第二个连接执行 DROP TABLE 触发 readFailed"的机制在 GRDB 7.11 下无法达成。
- 验收偏差（挂起到 1.17 写回修订）：readFailed 的测试机制从"第二个连接 DROP TABLE"改为"注入的取值失败"（BreakBox 让取值闭包第二次调用起抛错，经一次提交触发重取，流确定性以 readFailed 结束）。契约本身（读取失败 → readFailed）不变且已验证。
- 验收结果：33 个包测试全过（严格警告模式）（严格警告模式），含 create 时间戳/uuid 格式、ADR-017 六方法语义与幂等、软删除后可改、永久删除级联、notFound 六路、观察全生命周期（初始排序/isPinnedToDesktop/推送/消失/无关表不推/取消即停）、readFailed、只读连接 writeFailed(.readOnly)、simulateWriteFailure 六方法短路；checks.sh 与 xcodebuild build test（严格模式）通过。

## Review Triage Log

- Blind Hunter#1（spec 测试计数 35 与实际 33 不符）：属实——已更正（评审后补 1 条边界测试，现为 34）。
- Blind Hunter#2（观察流注释三方口径不一：静默结束/静默挂起/静默停止）：属实——以实测事实统一为"静默挂起（不结束）"；桥接层对"非取消的结束"按通道断开处理（防御性分支），注释已改写。
- Blind Hunter#3（实现新增语义未按规则同步 data-layer.md）：属实——已在 data-layer.md「观察」节补写实现补充（外部连接不感知、表删后挂起、readFailed(.ioError) 收尾、Note.ID init、updateContent 相同内容语义），1.17 写回 docs 时复核。
- Blind Hunter#4（观察流急切启动、未消费路径无测试）：属实——已补注释说明急切启动与 deinit 清理路径；未消费场景的 deinit 时序测试易碎，不补。
- Blind Hunter#5（updateContent 对相同内容也推进 updatedAt 无测试）：属实——补 contractEdgeCases 钉住该行为并在 data-layer.md 写明取舍。
- Blind Hunter#6（边界覆盖缺失：空内容/恢复重现/置顶推送翻转/软删除后永久删除）：属实——均已补测试。
- Blind Hunter#7（readFailed 未断言具体 reason）：属实——断言收紧为 readFailed(.ioError)。
- Blind Hunter#8（重复断言行）：属实——已删。
- Blind Hunter#9（fetchNote 标签误导）：属实——改为 from: database。
- Blind Hunter#10（大量强制解包）：部分采纳——fetchNote 改非可选返回收窄后续面；观察测试初始值下标保留（sawInitial 已先行断言）。
- Blind Hunter#11（表名魔法字符串 + exists 插值）：接收现状——实参全为内部字面量无注入面；1.5/1.6 沿用时如需再抽常量。
- Blind Hunter#12（NoteRecord.note 的 id ?? 0 兜底）：属实——改为 precondition 显式暴露缺陷。
- Blind Hunter#13（负向等待窗口竞态）：属实——窗口 300ms 提到 800ms。
- Blind Hunter#14（Note.ID init 契约外）：属实——已随 #3 写入 data-layer.md 补充。
- 流程备注：冲刺状态同步三次踩中"生成文件含全部故事 backlog 条目，插入造成重复键"的坑（1.2 首踩），已改为原位替换；Mimosa 非阻断提示（动态函数调用）同 1.2，接受。
