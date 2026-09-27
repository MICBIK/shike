---
title: 'Story 1.14 迁移前备份'
type: 'feature'
created: '2026-09-27'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/data-layer.md'
  - '{project-root}/_bmad-output/specs/spec-stage-0-foundation/failure-modes.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 阶段 2 起的结构迁移一旦出错，用户数据没有事前快照可回。

**Approach:** `open` 在版本检查之后、迁移之前调用 `preMigrationBackupIfNeeded`（ADR-018，data-layer.md「迁移前备份」）：库中已有迁移且还有待执行迁移时，用与每日备份相同的方式（在线备份写临时文件 + PRAGMA journal_mode=DELETE + 原子改名）在数据目录 Backups/ 下生成 `shike-before-<第一个待执行迁移标识>-YYYY-MM-DD.sqlite`（日期公历+Options.timeZone）。新建空库不做；同一天同一迁移已有备份不重复；该类文件不参与每日轮换。备份失败抛 openFailed(原因)（open 的统一映射），不执行迁移，库停留原版本；App 按"打不开"显示失败提示（1.8）。生产代码仍只注册正式迁移（makeMigrator 默认）。

## Boundaries & Constraints

**Always:** 备份先于迁移；失败不迁移。

**Never:** 不自动删除 shike-before-* 文件；不迁移入测试迁移。

</frozen-after-approval>

## Implementation Notes

- 从 backupFileName 抽出 backupDateString 供两类备份共用；writeOnlineBackup/removeSidecars/removeTemporaryArtifacts 直接复用。
- open 的步骤编号 4.5 插入在 hasBeenSuperseded 之后、migrate 之前；错误经 open 既有 catch 统一映射。
- 验收结果：ShikeDataTests 新增 PreMigrationBackupTests 4 例（v1→v2-test 备份内容一致且迁移完成、空库跳过、同日去重不覆盖、目录只读时 openFailed 且停留 v1），包内 59 测试全绿；App 侧无需改动（1.8 提示循环覆盖 openFailed）；checks.sh 通过。

## Review Triage Log

盲审（Blind Hunter）结论 pass，3 条 low 全部补强：
- [low→已修] preMigrationBackupIfNeeded 与每日备份对齐：进入前先 cleanLeftoverTemporaries（含边车），消除"残留导致 open 持续失败而清理者永不运行"的自愈断链。
- [low→已修] 失败原因断言收窄到 permissionDenied/ioError（failures 表类别），防 mapFailure 回归。
- [low→已修] 备份内容断言补强：独立打开 journal_mode=delete、含 note 且不含 premig_test（证明快照取自迁移前）。
- [false] 触发条件核查：appliedMigrations=已注册∩已应用、migrations 注册序、pending.first 即第一个待执行迁移；fresh 库与全部已应用均精确跳过。
- 已实测：包内 59 测试全绿；App 34 测试全绿；checks.sh 通过。
