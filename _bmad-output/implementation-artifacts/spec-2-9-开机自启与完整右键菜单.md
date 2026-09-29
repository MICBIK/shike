---
title: 'Story 2.9 开机自启与完整右键菜单'
type: 'feature'
created: '2026-09-28'
status: 'done'
route: 'oneshot'
review_loop_iteration: 0
context:
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/SPEC.md'
  - '{project-root}/_bmad-output/specs/spec-stage-1-capture/app-shell.md'
---

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** 右键菜单只有阶段 0 的三项（设置…/关于拾刻/退出拾刻），缺"打开拾刻"与"开机自启"；设置-通用只有"呼出时进入"。

**Approach:** 移植 LaunchAtLoginService（源：demo 同名文件，只保留 SMAppService 部分——去掉旧辅助程序迁移与单例）：Status 映射 enabled/requiresApproval/notRegistered，register/unregister/refresh/openSystemSettingsLoginItems，系统访问经注入闭包（L2 替身，不真实调用 SMAppService）。StatusMenu 扩展为 03 §2 的阶段 1 形态：打开拾刻、—、设置…⌘,、开机自启（勾选）、关于拾刻、—、退出拾刻⌘Q。设置-通用分页补开机自启开关（需要批准时显示说明与"打开登录项设置"）。

## Boundaries & Constraints

**Always:** 状态每次从系统读取（不缓存决策）；移植登记三处；勾选态与系统一致；右键菜单与设置开关同一服务。

**Never:** 不做旧辅助程序迁移；状态为 unavailable（notFound）时按未注册处理不报错。

</frozen-after-approval>

## Implementation Notes

- LaunchAtLoginService（移植）：三态映射（enabled/requiresApproval/notRegistered——盲审后删除 demo 遗留的 disabled 死分支）；init 即 refresh（修复陈初值导致的幂等误判）；setEnabled 以 defer refresh 兜底（盲审 high：开发期 register 抛错是常态，失败也刷新到系统实际）；isEnabled 把 requiresApproval 算作启用（注册意向已表达）；系统访问经四个注入闭包，L2 全替身。
- StatusMenu（7 项）：打开拾刻 / sep / 设置…⌘, / 开机自启（勾选态 build 时读）/ 关于拾刻 / sep / 退出拾刻⌘Q；勾选闭包先 refresh 再返回（盲审 high：用户在系统设置关闭后菜单立即反映）。
- 设置-通用：开机自启 Toggle + requiresApproval 说明与"打开登录项设置"；注册/注销失败显示内联错误文案（盲审 medium：try? 静默吞错的修复）；文案 needApproval 回归文案表原文。
- Story 2.10 收口（盲审确认完成）：两种空状态引导句已在 2.6 就位（EmptyStateView + 文案键与 03 §14 逐字一致），时间提示句按 Non-goals 未加。
- 测试：LaunchAtLoginTests 4 个（三态映射、开关双向、幂等、失败上浮）；StatusMenuTests 重写（7 项结构 + 勾选 on/off + 四动作回调）；App 80 全绿、包 76 全绿、checks 通过。

## Review Triage Log

盲审（Blind Hunter）结论 needs-fixes（1 high / 1 medium / 2 low），全部处置：

- [high→已修] 菜单勾选态读 service 缓存而非系统（AC2 字面违约；register 抛错被 try? 吞掉后勾选态卡死）。三处闭环：launchAtLoginEnabled 先 refresh；setEnabled defer refresh（失败也刷新）；修正 service 头注释。
- [medium→已修] setEnabled 失败两处 try? 静默吞掉（service 注释承诺"由调用方提示"落空）。设置页补内联错误文案（settings.launchAtLogin.failed）；菜单侧由 defer refresh 保证状态真实。
- [low→已修] Status.disabled 死分支（demo legacy 遗留）。已删除。
- [low→已修] 需要批准文案与文案表不一致。已改回"需要在系统设置中批准后生效"。
- [info·确认] register/unregister 同步系统调用在 MainActor（demo 相同）；"打开拾刻"实为 toggle（右键时面板通常已收起，与 demo 语义一致）；批准横幅不实时消失（03 §14 未要求，已知限制）；Story 2.10 收口确认。
- 遗留 L3 人工项：注销重登录自动运行；开发期 register 失败的内联提示实测。
