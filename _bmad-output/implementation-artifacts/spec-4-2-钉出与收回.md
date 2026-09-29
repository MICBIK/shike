# Story 4.1 实现规格：技术验证——卡片窗口与唤回（S3-00）

- context: SPEC-stage-3-cards/SPEC.md（CAP-1）；ADR-021（TCC 约束）；docs/03 §10.3/§10.4；ADR-025（结论落盘）

## 产出

- 原型：`Prototypes/CardPrototype/main.swift`（swiftc 直编 accessory 进程，不依赖主工程；二进制不入库）。
- 证据（本机 darwin 27，2026-09-29）：四组 EVIDENCE 行 + 全屏截屏目视（floating 压顶 / normal 被遮挡 / desktop 沉底均符合 03 §10.3）。
- 结论文档：docs/07 ADR-025。

## 关键结论（ADR-025 摘要）

1. 唤回 = 共享定时轮询 `NSEvent.mouseLocation`（0.023 µs/读，30Hz≈0.001 ms/s，零权限）；全局 mouseMoved 监听无 TCC 可安装但投递未验证，作为可选补充。
2. 层级三档可设可回读；桌面层 `CGWindowLevelKey(rawValue: 2)`（宏在 Swift 不可见）。
3. 空间标志回读成立；多空间/全屏真实表现列 L3。
4. 编辑焦点 = `NSPanel(.borderless, .nonactivatingPanel)` 子类覆写 `canBecomeKey`（默认 NSPanel canBecomeKey=false；borderless NSWindow makeKey 拿不到 key——isKey=false 实测）；双击+IME 列 L3。
5. 隐藏穿透 = `alphaValue` + `ignoresMouseEvents`。

## Post-story notes

- 原型 run 的 `focus.borderless isKey=false` 是选型转向 NSPanel 的直接证据——这正是"先验证再实现"要抓的坑。
- L3 复核项并入阶段 3 真机验收清单（唤回手感、多空间/全屏矩阵、双击 IME）。

# Story 4.2 实现规格：钉出与收回（S3-01）

- context: SPEC-stage-3-cards/SPEC.md（CAP-2）；scope-boundaries（CardManager/StickyCardPanel）；ADR-025；docs/03 §10.1/§10.2；docs/04 §5.4/§5.5/§6.1

## 实现

- `Shike/Cards/CardTheme.swift`：六色明暗映射、字号三档、层级→NSWindow.Level、空间→collectionBehavior、层级循环顺序；`CardGeometry`（首卡锚点=中央偏上、24pt 错开+回卷、钳制、最小尺寸）；`CardDiff`（create/update/close 纯函数对账）。
- `Shike/Cards/StickyCardPanel.swift`：`StickyCardPanel`（NSPanel 子类，borderless+nonactivatingPanel，canBecomeKey 按编辑态）；`CardContentView`（纸面+滚动正文+hover 顶条：拖动区/层级按钮/⋯占位/✕）；`CardDragBar`（performDrag 原生拖动，松手回调）。
- `Shike/Cards/CardManager.swift`：消费 `observeVisible()`（软删除联动由 SQL 层保证），CardDiff 驱动控制器增改删；`CardController` 持有窗口与 CardModel。
- `AppEnvironment`：钉出=CardGeometry 定位（屏=状态项所在屏）+ `card.default.*` 默认值写库；取消钉住/移动/层级循环四条写路径统一走面板提示条（NFR19，重试闭包复现载荷）；`AppDelegate` 设 screenProvider + terminate 时 stop。
- `PanelModel`：`pinNoteToDesktop`/`unpinNoteFromDesktop` 注入闭包 + `reportCardWriteFailure`；`NoteListView` 行加"钉到桌面/取消钉住"菜单与图钉标记（`isPinnedToDesktop`，pin.fill 青绿）。
- 偏好键 8 个 `card.default.*` 注册（04 §5.5 同步）+ `cardDefaultOptions` 聚合读取。

## 测试

- `CardGeometryTests`（6）：首卡锚点、错开 24pt 与不重叠不偏移、小屏环绕钳制、出界拉回与超大贴屏、最小尺寸、对账四态。
- `PinCardFlowTests`（5）：默认选项入账（黄/浮层/所有空间/不压全屏）、重复钉幂等、取消钉住便签保留、删除/撤销卡片联动、钉不存在便签 notFound 上面板提示条。
- 结果：App 152 测试全绿（新增 11）。

## Post-story notes

- **打磨发现（台账 R1）：**macOS 27 SDK 下 `#expect(double == cgfloat)` 对相同数值判 false（独立 swift 脚本为 true，宏捕获表达式下不可靠）——测试中混型比较一律显式 `Double(...)` 转换；生产代码避免 Double/CGFloat 混比较。
- ⋯ 按钮为结构占位（菜单随 4-9）；字号/颜色映射表先行，设置入口随 4-5。
- 自动隐藏（4-4）未接入：卡片常显；编辑（4-7）未接入：allowsKey 恒 false。
