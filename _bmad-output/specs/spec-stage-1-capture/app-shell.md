# 阶段 1 组件契约：输入、列表与系统服务（S1-01～S1-10）

交互规格以 03 §2～§7、§9、§13、§14 为准。本文规定阶段 1 新增/扩展组件的职责、行为细节、文案与移植清单；阶段 0 已有的契约（`../spec-stage-0-foundation/app-shell.md`）继续生效，与之冲突时以本文为准。

## 文件布局（阶段 1 新增）

| 路径 | 职责 |
|---|---|
| `Shike/Panel/CaptureTextView.swift` | 快速输入框（移植，NSViewRepresentable 包 NSTextView） |
| `Shike/Panel/TypingBuffer.swift` | 呼出后到输入框就绪间的按键缓冲与回放（移植改造） |
| `Shike/Panel/PopoverResizeHandle.swift` | 右下角尺寸把手（移植） |
| `Shike/Panel/NoteListView.swift` | 便签列表：分组、行、原位编辑、右键菜单 |
| `Shike/Panel/TodoListView.swift` | 待办列表：分组、行、勾选、原位编辑、右键菜单 |
| `Shike/Panel/UndoBar.swift` | 底部撤销提示条 |
| `Shike/Services/HotkeyService.swift` | 全局快捷键（移植 KeyboardShortcutService，基于 KeyboardShortcuts） |
| `Shike/Services/LaunchAtLoginService.swift` | 开机自启（移植，基于 SMAppService） |
| `Shike/Support/RelativeTimeFormatter.swift` | 相对修改时间（纯函数，注入 now 与时区） |

## 组件契约

- **PanelModel（扩展）：**
  - `mode` 的呼出决策：`openMode == .last` 用 `panel.lastMode`，`.note`/`.todo` 直接定；任何切换都写 `panel.lastMode`。
  - 草稿：`draftNote`/`draftTodo` 两份，随文字变化写入 `panel.draft.*`（退出拾刻时已在 UserDefaults）；收起面板、切换模式不清空。
  - 提交：`submit()` 按当前模式调用对应 `create`；成功清空输入与该模式草稿、记录"新条目 id"供列表高亮 1 秒；失败保留输入、走既有 `report(_:retry:)` 提示条。
  - 删除撤销栈：软删除前把（uuid、标题摘要、原列表位置所需的排序键）入栈；`undoLastDelete()` 调用 `restore` 并弹出；栈深不限制（会话级，不持久化）。
  - 重试提示条改造：真实写入路径接入后，`bannerRetry` 闭包必须绑定"当时那次失败的输入"，重试成功后清除提示条（解决 deferred-work「面板提示条的重试生命周期」第 1、2 条）。
- **CaptureTextView：**
  - `NSViewRepresentable` 包装 `NSScrollView` 中的 `NSTextView`，自绘占位文字；`hasMarkedText()` 为真时不替换文字、不刷新属性，`doCommandBy` 收到回车且组合中则交给输入法。
  - `⇧↩`：便签模式插入换行，待办模式无作用；`Tab` 上交（PanelModel 切模式）；`Esc` 上交（PopoverController 处理）；`↩` 且非组合态回调 `onSubmit`。
  - 高度：按行高计算，便签上限 6 行、待办 2 行，超出框内滚动；文字变化且非组合态时回调 `onChange(text)`。
  - 焦点：`focusPanel()` 使 `becomeFirstResponder`；占位文案随模式切换。
- **TypingBuffer：**面板未就绪期间安装本地按键监听，缓存可打印字符与回车；输入框就绪后按顺序回放并清空；面板收起即丢弃缓冲。缓冲上限 200 字符，超出丢弃最早的。
- **PopoverController（扩展）：**
  - `Esc`：本地按键监听，顺序"结束编辑（通知列表结束编辑）→ 收起面板"。
  - 尺寸：`panel.size` 读取初始尺寸；把手拖动结束（鼠标抬起）时钳制到 min 300×360 / max 600×1000 且不超所在屏幕可见区域，然后保存。
- **PopoverResizeHandle：**右下角 16×16 触控区，拖动改 `contentSize`；光标 `resizeLeftRight` 旋转 45°（`crosshair` 或方向光标以实测手感为准）；移植来源见 NOTICE。
- **NoteListView：**
  - 分组：「置顶」（`pinnedAt` 非空，按 pinnedAt 降序）+「便签」（updatedAt 降序——观察流已保证）；置顶组为空不显示。
  - 行：内容前 3 行（`lineLimit(3)`）+ RelativeTimeFormatter 的修改时间；单击行进入原位编辑（`TextEditor` 或同款），0.5 秒防抖 + 失焦 + 收起面板三个时机保存，走 `updateContent`。
  - 右键菜单：编辑（进入编辑）、置顶/取消置顶（`setPinned`）、复制内容（`NSPasteboard`）、删除（PanelModel 删除通路）。
- **TodoListView：**
  - 分组：「待办」（completedAt == nil）+「已完成（N）」（默认折叠，点击展开）；空组不显示。
  - 行：圆圈按钮（完成/勾回）+ 标题；勾选先置灰划线，1 秒后再调用 `setCompleted`（期间再点取消，计时器失效）；单击标题原位单行编辑，防抖同便签，走 `updateTitle`。
  - 右键菜单：编辑、删除。
- **UndoBar：**有内容时从底部浮出；文案"已删除「摘要」"+ 撤销按钮；5 秒后自动消失；新删除重置计时与内容；点撤销调 `undoLastDelete()`。
- **RelativeTimeFormatter：**输入（date, now, timeZone）→ 刚刚 / N 分钟前 / 今天 HH:mm / 昨天 / M月d日；纯函数、L1 可测；24 小时制（12 小时制是 S5-04）。
- **HotkeyService：**`KeyboardShortcuts.Name("togglePanel")`；默认 `.init("n", modifiers: [.control, .option])`（KeyboardShortcuts 的默认值机制）；`onPress` 回调接 PopoverController.toggle；设置-快捷键分页放 `KeyboardShortcuts.Recorder` + 开关（KeyboardShortcuts.isEnabled）。
- **LaunchAtLoginService：**包装 `SMAppService.mainApp`：`register()`/`unregister()` 抛错上浮提示；`status` 每次实时读取，映射 enabled / requiresApproval / notRegistered；requiresApproval 时设置-通用显示说明 + "打开登录项设置"按钮（`SMAppService.openSystemSettingsLoginItems()`）。
- **SettingsView（扩展）：**通用分页：呼出时进入（三选一）、开机自启（开关+状态说明）；快捷键分页：录制控件。占位机制保留给其余分页。
- **StatusMenu（扩展）：**新增"打开拾刻"（回调打开面板）与"开机自启"（勾选态，点击切换）；顺序按 03 §2（打开拾刻在最上，分隔线，设置…、开机自启、关于拾刻，分隔线，退出拾刻）。

## 阶段 1 文案（新增键，写入 Localizable.xcstrings）

| 键 | 文案 |
|---|---|
| `panel.capture.placeholder.note` | 记点什么…（⇧↩ 换行） |
| `panel.capture.placeholder.todo` | 要做什么？ |
| `panel.empty.note.guide` | 在上方输入，回车保存 |
| `panel.empty.todo.guide` | 输入要做的事，回车保存 |
| `menu.open` | 打开拾刻 |
| `menu.launchAtLogin` | 开机自启 |
| `list.group.pinned` | 置顶 |
| `list.group.notes` | 便签 |
| `list.group.todos` | 待办 |
| `list.group.completed` | 已完成（%lld） |
| `list.menu.edit` / `list.menu.pin` / `list.menu.unpin` / `list.menu.copy` / `list.menu.delete` | 编辑 / 置顶 / 取消置顶 / 复制内容 / 删除 |
| `undoBar.deleted` | 已删除「%@」 |
| `undoBar.undo` | 撤销 |
| `settings.general.openMode` / `.last` / `.note` / `.todo` | 呼出时进入 / 上次的模式 / 总是便签 / 总是待办 |
| `settings.general.launchAtLogin` | 开机自启 |
| `settings.launchAtLogin.needApproval` | 需要在系统设置中批准后生效 |
| `settings.launchAtLogin.openSettings` | 打开登录项设置 |
| `settings.shortcuts.title` | 呼出 / 收起面板 |
| `time.justNow` / `time.minutesAgo` / `time.todayAt` / `time.yesterday` / `time.date` | 刚刚 / %lld 分钟前 / 今天 %@ / 昨天 / %-m月%-d日 |

## 移植清单（阶段 1）

来源 `../TZMemo/demo/reminders-menubar/`，基线 `e3c0260`（NOTICE 已记）。每个文件按 06 §9 处理并登记 NOTICE 与 04 §7：

| 拾刻文件 | demo 来源 | 主要修改 |
|---|---|---|
| `Panel/CaptureTextView.swift` | `Views/Helpers/RmbHighlightedTextField.swift`、`PlaceholderNSTextView.swift`、`FocusDirection.swift` | 去掉自动补全与 EventKit 相关；Tab/Esc 改为上交回调；高度上限改为 03 §4（便签 6 行/待办 2 行） |
| `Panel/TypingBuffer.swift` | `Services/NewReminderTypingCoordinator.swift` 及 `Views/ContentView.swift` 的按键监听部分 | 拆成独立类型；去掉 EventKit 数据模型；缓冲上限 200 字符 |
| `Panel/PopoverResizeHandle.swift` | `Views/Helpers/PopoverResizeHandleView.swift`、`Extensions/NSCursor+Extensions.swift` | 通过回调改尺寸（不做全局单例）；钳制参数注入 |
| `Services/HotkeyService.swift` | `Services/KeyboardShortcutService.swift` | 默认开启；快捷键名换为 togglePanel；去掉旧辅助逻辑 |
| `Services/LaunchAtLoginService.swift` | `Services/LaunchAtLoginService.swift` | 只保留 SMAppService 部分，去掉旧辅助程序迁移 |

## 测试清单

- **L1（能纯则纯）：**RelativeTimeFormatter（固定 now：刚刚边界、60 分钟、跨天、跨年）；TypingBuffer 缓冲/回放/上限/丢弃（事件注入抽象）；草稿模式决策（openMode×lastMode 的纯函数）；PanelModel 提交与撤销栈（内存库 + 独立 UserDefaults 组装）。
- **L2：**Preferences 五个新键默认值与读写；PopoverController 尺寸钳制（纯函数部分）；SettingsTab 分页状态变化；HotkeyService 组装（不真注册的封装逻辑）；LaunchAtLoginService 状态映射（注入协议替身）；PanelModel 真实提交链路（create 成功清空草稿、失败保留并报告）与删除→撤销链路（restore 后观察流回推）。
- **L3（人工，02 验收清单）：**快捷键计时、输入法组合、呼出即打字、⇧↩、Esc 草稿、删除撤销、尺寸记忆、开机自启注销重登、退出重开数据、自用一周。
