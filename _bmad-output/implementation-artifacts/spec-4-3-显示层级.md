# Story 4.3 实现规格：显示层级（S3-02）

- context: SPEC-stage-3-cards/SPEC.md（CAP-3）；ADR-025 结论 2/3；docs/03 §9（卡片分页）、§10.3；docs/04 §5.5

## 实现

- 层级切换与持久化已随 4-2 落地（卡片操作条层级按钮循环 floating→normal→desktop，`updateOptions` 持久化；`CardTheme.windowLevel` 按 ADR-025 映射，桌面层 `CGWindowLevelKey(rawValue: 2)`）。
- 本故事补齐**设置-卡片分页**（`CardsSettingsView`，占位撤除）：新卡片默认层级/颜色/字号/自动隐藏（开关、延迟 1/3/5/10 秒、隐藏后不透明度 0–60% 步进 10%）/空间（所有空间/仅所在空间）/显示在全屏应用之上。
- `SettingsModel` 8 个存储属性 + didSet 持久化（既有模式： UserDefaults 计算属性不可观测，盲审 3.8-F2）；非法存储值回落文档默认（层级/颜色/字号 rawValue 失败回落、延迟不在档位回落 3 秒、不透明度钳 0–0.6）。
- 卡片消费端经 `Preferences.cardDefaultOptions` 读同一批键（S3-01 pin 已接）。

## 测试

- `CardSettingsTests`（4）：文档默认值核对、修改即持久化且消费端一致、非法存储值回落、不透明度越界钳制。
- `MainMenuTests.placeholderStages` 更新：卡片分页无占位。
- 结果：App 160 测试全绿（+4）。

## Post-story notes

- 空间行为与全屏压盖的"真机表现"仍属 L3（ADR-025 结论 3）；本故事保证设置项与持久化正确。
- `settings.card.hideDelay` 标签用"开始隐藏前等待"（S3-03 自动隐藏接入时与卡片菜单的"延迟"同义）。
