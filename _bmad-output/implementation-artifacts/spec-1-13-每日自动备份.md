---
title: 'Story 1.13 每日自动备份'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/data-layer.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/app-shell.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/failure-modes.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 数据没有任何备份，磁盘或文件损坏时无法找回；备份还必须不拖慢启动、不打扰用户。

**Approach:** ShikeData 新增 `AppDatabase.backupIfNeeded(to:keep:)`（data-layer.md「备份」）：目录不存在先创建；清理 `*.partial` 残留；当天文件已存在返回 `.alreadyExists`（仍轮换）；否则 SQLite 在线备份写入 `.shike-YYYY-MM-DD.sqlite.partial`，对目标库执行 `PRAGMA journal_mode=DELETE`，原子改名 `shike-YYYY-MM-DD.sqlite`，返回 `.created(URL, removed:)`；文件名日期按公历+`Options.timeZone`（en_US_POSIX，与区域无关）；轮换只处理 `^shike-\d{4}-\d{2}-\d{2}\.sqlite$`，按文件名日期保留最新 `keep`（≥1）份；失败删临时文件抛 `backupFailed(原因)`。`simulateWriteFailure` 不影响备份。App 层 `BackupService`：AppEnvironment 用数据目录与 `backup.keepCount` 创建；`start()` 后台执行一次并订阅 NSCalendarDayChanged（订阅仅转发到可直调的 backupNow），结果/失败只写日志 category backup；AppDelegate 在创建图标之后调用 start()；测试宿主不备份。

## Boundaries & Constraints

**Always:** 启动不等待备份完成；L1/L2 测试断言备份文件可独立打开（journal_mode=delete、行数一致）。

**Never:** 不打扰用户（无界面提示）；不打包/上传备份。

</frozen-after-approval>

## Implementation Notes

- 在线备份采用 GRDB 文档模式：后台线程内 `writer.read { source in targetQueue.write { source.backup(to: dest) } }`（跨连接持有两侧；一次离线任务在后台线程阻塞可接受，避免嵌套 async 桥接死锁）。PRAGMA 用 fetchOne 消费返回行。
- BackupOutcome 携带 removed: [URL]（本次轮换删除的文件），日志只记结果与文件名，不记内容。
- 验收结果：ShikeDataTests 新增 BackupTests 8 例（新建/跳过/轮换/跨日时区/残留清理/只读目录失败/simulate 不影响/独立打开 journal_mode=delete 行数一致）；ShikeTests BackupServiceTests 2 例（runBackup 产出当日备份、keepCount 来自偏好并轮换）。全套 41 测试通过；checks.sh 通过。

## Review Triage Log

（待盲审后填写）
