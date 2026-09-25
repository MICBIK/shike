---
title: 'Story 1.2 建立 CI 流水线'
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

**Problem:** 完成与否目前只能靠本地判断；"完成 = CI 通过"（ADR-014）还没有裁决机器，main 也还没有准入门槛。

**Approach:** 建 `.github/workflows/ci.yml`（checks/package-tests/app 三作业，SHA 锁定 action，concurrency/permissions/timeout，XcodeGen 下载校验，SHIKE_WARNINGS_AS_ERRORS=YES）+ `scripts/checks.sh`（conventions.md 四类检查，本地可跑，每条规则带违规样例自检，checks 作业先跑自检）。推送触发 CI、首次全绿、生成符号在 CI Xcode 26.6 的确认与（如需）回退、main 分支保护——都发生在推送之后，本故事完成以上文件的实现与本地验证。

## Boundaries & Constraints

**Always:** actions 以提交 SHA 锁定并在注释写版本（checkout v7.0.1 = `3d3c42e5…`）；XcodeGen 2.46.0 zip 校验 SHA-256 `4d9e34b6…` 后才解压；macOS 作业打印 `xcodebuild -version`；警告即错误经由 `SHIKE_WARNINGS_AS_ERRORS` 环境变量 + 同名 xcodebuild 设置；检查脚本本地与 CI 同一份。

**Never:** 不在 xcodebuild 命令行直接传 `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`；本故事不推送、不开分支保护（挂起到产品负责人早晨处理）；不缓存（可选项，跳过）。

</frozen-after-approval>

## Implementation Notes

- （规划期判断）检查脚本放 `scripts/checks.sh`：04 §2 把 scripts/ 标注为"发布脚本（阶段 4）"，但 conventions.md 要求检查脚本本地可跑、与 CI 同一份，仓库需要一个固定位置；1.17 写回 docs 时把 04 §2 的 scripts/ 注释改为"CI 检查与发布脚本"。
- 本地已验证：`checks.sh --self-check`（4 条规则在违规样例上全部失败）与 `checks.sh`（仓库零违规）双向通过；ci.yml YAML 解析正常；app 作业的 XcodeGen 步骤（下载 2.46.0 zip → SHA-256 校验 OK → 解压 → `./xcodegen/bin/xcodegen --version`）在 /tmp 按同款命令实测通过。
- 脚本开发中自曝并修复两处 bug：移植文件规则的搜索串让 checks.sh 自我命中（已显式排除自身）；Foundation 过滤的 `grep -v` 缺 `-E` 导致误报（补上）。
- 挂起（推送后才能确认，留产品负责人早晨）：推送 stage-0/foundation 触发三作业全绿；CI Xcode 26.6 上符号测试通过与否（不支持则按 stack.md 回退 `String(localized:)` 并同步 stack.md/conventions.md/NFR9 与 1.1 验收措辞）；首次全绿后开启 main 分支保护（产品负责人执行或明确授权）。

## Review Triage Log

- Blind Hunter#1（sprint-status.yaml 出现重复键 1-2，生效值被覆盖为 backlog）：high，属实——是本流程编辑造成的；已删除旧条目，PyYAML 复核解析为 in-progress、无重复键。
- Blind Hunter#2（spec-1-1 status done 与 sprint review 矛盾）：false——两个载体语义不同：规格 status=done 指实现与评审完毕；sprint 的 review 指"等待 ⑤ 代码评审与 ⑥ 人工验收"（sprint-status 模板的工作流注释明确写了 Dev moves story to review, then runs code-review），二者按设计就是先后关系。
- Blind Hunter#3（导入边界正则的访问级别修饰写法漏匹配）：high，属实——`[[:space:]]+` 只写在 private 分支导致 `public/internal/fileprivate import` 全部漏检；已改写为 `((internal|public|fileprivate|private)[[:space:]]+)?` 并在自检样例中覆盖。
- Blind Hunter#4（自检粒度到类别不到规则，死规则不可见）：high，属实——自检改为逐样例断言"样例被对应规则命中"，11 个样例逐一断言。
- Blind Hunter#5（自检缺正向对照样例）：属实——沙盒加入合规 Clean.swift，断言其不被任何规则报出。
- Blind Hunter#6（移植样例因 NOTICE.md 缺失而以错误原因失败并泄漏 stderr）：属实——沙盒现在预置不含登记的 NOTICE.md，样例因"未登记"命中。
- Blind Hunter#7（NOTICE 校验用 basename 子串，弱于约定的路径登记）：属实——改为按仓库相对路径 `grep -qF` 定长串匹配。
- Blind Hunter#8（检查根缺失时静默通过）：属实——真实检查前 require_roots 校验四个目录与 NOTICE.md 存在，缺失即违规。
- Blind Hunter#9（扫描口径不一致：.build 未排除/导入规则窄于约定）：属实——移植与禁用项扫描统一为四个检查根并排除 /.build/；ShikeKit 框架禁用规则改为扫整个 Packages/ShikeKit（同样排除 .build）。
- Blind Hunter#10（push+pull_request 双触发重复消耗 macOS 作业）：属实但属 stack.md 既定策略——改动等于修改规格，已记入 deferred-work.md 供产品负责人裁量，本轮不改。
- Blind Hunter#11（挂起事项未集中到 deferred-work.md）：属实——三项推送后卡点与本条评审提出的双触发问题均已补记；1.1 的 /tmp 清理实际已修复，是 spec-1-1 裁定日志"（defer）"措辞误导，已改为"已修复"。
- Blind Hunter#12（README 未提及 checks.sh）：属实——README 构建一节补充本地运行方式。
- Blind Hunter#13（未知参数被静默忽略）：属实——main 改为 case 分派，未知参数打印用法并 exit 2。
- 补充（自检复跑时新发现）：真实检查中 VIOLATIONS 计数失效——`VIOLATIONS=0 run_all_checks` 前缀赋值把函数内累加隔离进临时作用域，导致报了违规仍退出 0；已改为独立赋值语句。同轮发现 Foundation 排除过滤器作用在带 path 前缀的输出上而模式 `^` 锚定、永远滤不掉——改为不带锚定的过滤模式。两处均已修复并回归验证。
- 备注：Mimosa 对 checks.sh 的"命令注入"提示（非阻断）来自脚本内部的动态函数调用/动态 grep 模式，入参全部为脚本内字面量，无外部输入，接受不改。
