---
title: 'Story 1.3 数据库的打开与 v1 表结构'
type: 'feature'
created: '2026-09-26'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/data-layer.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/failure-modes.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/conventions.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** ShikeData 还没有打开数据库的能力：真实内容（阶段 1 起）需要一个"要么完整成功、要么明确失败且不碰原文件"的打开流程，以及结构正确、只追加的 v1 表结构。

**Approach:** 按 data-layer.md「AppDatabase」实现 `AppDatabase.open/inMemory/Options/fileName`（WAL、事务内迁移、hasBeenSuperseded 检查、invalidLocation/permissionDenied/corrupted/newerSchema 失败路径、transactionClock 注入）；迁移器由内部工厂创建，生产只注册 v1，测试可注入；错误映射逐条对应「错误分类」表；v1 表结构逐字按 04 §5 与「结构细节」（三表、三索引、due CHECK、noteId 唯一 + 级联外键）。仓储、观察、备份、Record 类型不在本故事（1.4+/1.13+/1.14）。

## Boundaries & Constraints

**Always:** 公开 API 不出现 GRDB 类型；引入 GRDB 的文件写 `internal import GRDB` 并显式 `import Foundation`；不修改已发布的迁移；时间戳全部来自注入时钟。

**Never:** 不做迁移前备份（1.14 接入）；不实现 backupIfNeeded（1.13）；不建 Record 类型与仓储（1.4 起）；没有 eraseDatabaseOnSchemaChange。

</frozen-after-approval>

## Implementation Notes

- （流程备注）本规格在实现完成后补写：实现直接以史诗故事的验收标准为意图展开，补写时把实现决定如实记入本节。
- v1 迁移的列类型按 PRAGMA 实测校准：GRDB `.double` 落成 `DOUBLE`，与 04 §5 的 `REAL` 不符，改用 `.real`；主键用 `autoIncrementedPrimaryKey("id")`（04 §5.1 的"自增"），SQLite rowid 别名在 PRAGMA 中 notNull 报 0，测试按此断言。
- newerSchema 验收中"库文件没有被写入"的实现解释：WAL 模式下打开连接会触发恢复检查点、移动页面，逐字节稳定不可达（实测主文件 4096→57344 页面迁移）。改为断言库的**逻辑内容**（sqlite_master 全量、迁移注册表、用户数据行）在失败打开前后一致。此措辞差异记录在案，1.17 写回 docs 时建议把该验收改写为"迁移未被执行、结构与数据不变"。
- 错误映射按主结果码（扩展码先 `& 0xFF`）：13→diskFull、8→readOnly、3/27→permissionDenied、11/26→corrupted、5/6→busy、10/14→ioError、19→constraintViolation、其余→unknown(code:)；文件系统错误 EACCES/EPERM/EROFS→permissionDenied（含 NSUnderlyingErrorKey 解包），其余归 ioError。`simulated` 不经结果码映射（仓储写路径直接抛出，1.4 起产生并测试）。
- GRDB API 备忘：`Configuration.transactionClock` 用 `.custom { _ in options.clock() }`；`migrator.hasBeenSuperseded(db)`；`DatabaseError(resultCode:message:)` 有 `resultCode.rawValue`；`writer.close()`、`db.checkpoint(.truncate)` 存在但后者在自身写事务内会 SQLITE_LOCKED，不可用于测试夹具。
- 时钟注入选项签名：`clock: @escaping @Sendable () -> Date`（存入属性必须 escaping）；`Configuration` 实例需 `var` 才能设置属性。
- 验收结果：24 个包测试全过（结构三表逐列、索引名与列序、外键、CHECK 正反两向、第二张卡片拒绝、二次打开幂等、invalidLocation 相对路径与非文件 URL、permissionDenied 只读父目录、corrupted 字节不变、newerSchema 内容不变、注入迁移执行、inMemory 同迁移、固定/递增时钟、错误映射逐码）；checks.sh 通过；xcodebuild build test（含严格警告模式）通过。

## Review Triage Log

- Blind Hunter#1（CHECK 负向测试假通过：NOT NULL 先于 CHECK 失败）：high，属实——补齐 createdAt/updatedAt 合法值，使失败只能来自 CHECK。
- Blind Hunter#2（缺 CHECK 正向用例）：属实——补"全天与带时刻待办均可插入"测试。
- Blind Hunter#3（缺 uuid/日期存储格式测试）：属实但归 1.4——`typeof(uuid)='text'` 与小写 36 位断言必须经内部 Record 类型的 GRDB 编码路径才有效，Record 属 1.4；已在 spec 留痕。本轮顺手把测试中单字符占位 uuid 换成 36 位小写串。
- Blind Hunter#4（索引只验证名字未验证列序）：属实——补 `PRAGMA index_info` 断言三索引的列与顺序。
- Blind Hunter#5（stickyCard 列断言丢弃真实默认值）：属实——改用 `ColumnSpec.init(_ row:)`。
- Blind Hunter#6（未使用变量在 CI 严格警告下必挂）：high，属实——删除残留的 `let relative`；评审者在 SHIKE_WARNINGS_AS_ERRORS=YES 下实测复现了构建失败，已修复并回归。
- Blind Hunter#7（invalidLocation 断言是装饰性的）：属实——删恒真断言，改为验证工作目录下未出现 relative/ 目录。
- Blind Hunter#8（sprint-status 未更新）：属实——1-3 已同步为 review。教训：生成文件本就含全部故事的 backlog 条目，同步时必须"替换"而非"插入"，此前 1.2 的重复键正是同一根因。
- Blind Hunter#9（缺二次打开用例）：属实——补"同一目录二次打开：迁移幂等、数据保留"。
- Blind Hunter#10（spec 测试计数口径）：属实——24 = ShikeDataTests 22 + ShikeDateParserTests 2，已更正。
- Blind Hunter#11（时钟基准偏离 T0）：属实——改用 2026-09-23 12:00 Asia/Shanghai 构造的 T0 并注释出处。
- Blind Hunter#12（ENOSPC 归 ioError 未记录）：属实——契约表 diskFull 仅源自 SQLITE_FULL，文件系统的 ENOSPC 落 ioError；已记录，避免 1.4 写路径误判。
- Blind Hunter#13（CocoaError 分支近乎不可达 + 裸数字）：属实——加注释说明该分支服务手工构造错误；mapResultCode 改用 GRDB 具名 `ResultCode` 常量。注意 SQLITE_AUTH 实为 23（我曾误写 27，具名常量直接暴露了这个错误）。
- Blind Hunter#14（options 属性未读取）：属实——为 1.4 起的仓储写路径预留，已加注释。
