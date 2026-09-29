# Story 4.4 实现规格：自动隐藏（S3-03）

- context: SPEC-stage-3-cards/SPEC.md（CAP-4）；ADR-025 结论 1（唤回=共享轮询）；docs/03 §10.4；NFR25

## 实现

- `Shike/Cards/AutoHideStateMachine.swift`：纯逻辑状态机（visible → fadingOut → hidden → fadingIn → visible），时钟注入（单调秒）、鼠标在位由轮询喂入；输出 targetAlpha/ignoresMouseEvents；busy（编辑/菜单/拖动）强制回显且解除后重置离开计时。
- `CardManager`：共享 30Hz Timer（`.common` 模式，菜单跟踪期间也 tick），ADR-025 选型的 `NSEvent.mouseLocation` 轮询；有开自动隐藏的卡片才启停；显示器级一个监听器（NFR24）。
- `CardController`：tick 推进状态机，状态变化才应用；alpha 动画时长随相位（0.3/0.15s），`Motion.reduce` 直切；拖动经 `setDragging` 置 busy；关闭开关的卡片若停在隐藏态强制回显一次。
- 每卡开关入口：⋯ 按钮升级为真实菜单（自动隐藏 Toggle + 延迟/隐藏后不透明度 Picker 子菜单，macOS 原生勾选态）；写路径走 `Actions.updateOptions` → 仓储 → 观察流回环（轮询启停随 apply 同步）。
- 设置-卡片分页的"新卡默认值"（S3-02）与每卡设置读写同一批 `stickyCard` 列。

## 测试

- `AutoHideStateMachineTests`（7）：离开满 N 秒淡出、淡出走完进隐藏（穿透）、悬停 0.2s 唤回、淡出中途回鼠标、离开计时重置、busy 强制回显+解除重置、每卡参数（1 秒档/60%/0% 完全看不见仍可唤回）。
- 浮点边界教训：3.3−3.0 = 0.2999… < 0.3，断言时刻避开精确相位边界（3.35/3.75）。
- 结果：App 167 测试全绿（+7）。

## Post-story notes

- 菜单打开期间不隐藏（03 §10.4）暂靠 hover/`.common` tick 兜底；4-9 把 ⋯ 菜单重建为原生 NSMenu 时显式接 busy。
- 唤回手感（隐藏中鼠标划过的唤回节奏）列 L3 真机复核（ADR-025 三个 L3 项之一）。
- 编辑中不隐藏的 busy 输入随 S3-06（卡片上编辑）接入。
