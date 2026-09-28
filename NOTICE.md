# 致谢与第三方声明

拾刻（Shike）Copyright (C) 2026 Shike contributors，以 GNU General Public License v3.0 only 发布，许可证全文见 [LICENSE](LICENSE)。

## 源自 Reminders MenuBar 的代码

- **项目：**Reminders MenuBar，<https://github.com/DamascenoRafael/reminders-menubar>
- **版权：**Copyright (C) Rafael Damasceno and contributors
- **许可证：**GNU General Public License v3.0

拾刻移植了其中的部分代码并做了修改。每个移植文件的开头都注明了来源和修改说明，并在下表登记，格式为：拾刻文件 ｜ 来源文件 ｜ 修改说明 ｜ 日期。

移植基线为 demo 提交 `e3c0260a8630381224e80f5f0e0c6700f2e417aa`（2026-09-19）。

| 拾刻文件 | 来源文件 | 修改说明 | 日期 |
|---|---|---|---|
| `Shike/MenuBar/StatusItemController.swift` | `demo/reminders-menubar/reminders-menubar/AppDelegate.swift`（configureMenuBarButton、handleStatusBarButtonAction、showRightClickMenu） | 拆成独立控制器；去掉计数/预览、隐藏图标逻辑与单例；图标固定为模板图像 `note.text`；右键菜单经 menuProvider 临时挂载 | 2026-09-27 |
| `Shike/MenuBar/StatusMenu.swift` | `demo/reminders-menubar/reminders-menubar/Services/RightClickMenuHelper.swift` | 菜单项换成拾刻的三项（设置…、关于拾刻、退出拾刻）；去掉单例与重载数据、检查更新等更新相关菜单项；动作经闭包回调 AppDelegate | 2026-09-27 |
| `Shike/MenuBar/PopoverController.swift` | `demo/reminders-menubar/reminders-menubar/AppDelegate.swift`（togglePopover、外部点击监听、didClose/didShow 兜底）、`MainPopoverSizing.swift`、`Extensions/Comparable+Extensions.swift`（constrainedTo） | 拆成独立控制器；去掉 EventKit 授权与单例；尺寸改为 03 §3 的 360×520（最小 300×360、最大 600×1000）；`activate(ignoringOtherApps:)` 改为 `activate()`；S1-01 增加尺寸把手回调、Esc 监听与持久化接线 | 2026-09-27 |
| `Shike/Panel/PopoverResizeHandle.swift` | `demo/reminders-menubar/reminders-menubar/Views/Helpers/PopoverResizeHandleView.swift`、`Extensions/NSCursor+Extensions.swift` | 去掉 AppDelegate.shared 单例，改经回调读写尺寸；光标用系统 crosshair（无图片资源）；帮助气泡省略 | 2026-09-28 |
| `Shike/Services/HotkeyService.swift` | `demo/reminders-menubar/reminders-menubar/Services/KeyboardShortcutService.swift` | 去掉单例，偏好与启用开关经注入的 Preferences 与闭包完成（L2 可用替身）；快捷键名换为 togglePanel，默认 ⌃⌥N 且默认开启 | 2026-09-28 |
| `Shike/Panel/CaptureTextView.swift` | `demo/reminders-menubar/reminders-menubar/Views/Helpers/RmbHighlightedTextField.swift`、`Views/Helpers/PlaceholderNSTextView.swift`、`Views/Helpers/FocusDirection.swift` | 去掉自动补全与高亮（S2-01 再接入）；Tab 改为 onTab 回调切模式；回车决策提为纯函数 newlineDecision 并在输入法组合态交还输入法；行数上限改为 03 §4（便签 6、待办 2） | 2026-09-28 |
| `Shike/Panel/TypingBuffer.swift` | `demo/reminders-menubar/reminders-menubar/Services/NewReminderTypingCoordinator.swift`、`Views/ContentView.swift`（按键监听与 isTextInputEvent 部分） | 去单例与 EventKit 条件；截获条件经注入的 shouldInterceptKeys 判定"呼出空窗"（输入框未就绪且焦点不在其它键窗）；缓冲上限 200（丢弃最早）；isTypingEvent 纯函数（裸回车入缓冲，回放按"裸回车=提交"） | 2026-09-28 |

## 依赖库

| 名称 | 用途 | 许可证 | 状态 |
|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) 7.11.1 | SQLite 数据库访问 | MIT | 阶段 0 已引入（`Packages/ShikeKit` 以 `exact: "7.11.1"` 锁定） |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) 3.1.0 | 全局快捷键 | MIT | 阶段 1 已引入（App 目标以 `exactVersion: 3.1.0` 锁定） |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 自动更新 | MIT（另含其自带的第三方声明） | 计划在阶段 4 引入 |
