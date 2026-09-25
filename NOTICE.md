# 致谢与第三方声明

拾刻（Shike）Copyright (C) 2026 Shike contributors，以 GNU General Public License v3.0 only 发布，许可证全文见 [LICENSE](LICENSE)。

## 源自 Reminders MenuBar 的代码

- **项目：**Reminders MenuBar，<https://github.com/DamascenoRafael/reminders-menubar>
- **版权：**Copyright (C) Rafael Damasceno and contributors
- **许可证：**GNU General Public License v3.0

拾刻移植了其中的部分代码并做了修改。每个移植文件的开头都注明了来源和修改说明，并在下表登记，格式为：拾刻文件 ｜ 来源文件 ｜ 修改说明 ｜ 日期。

移植基线为 demo 提交 `e3c0260a8630381224e80f5f0e0c6700f2e417aa`（2026-09-19）。

目前还没有移植任何文件。

## 依赖库

| 名称 | 用途 | 许可证 | 状态 |
|---|---|---|---|
| [GRDB.swift](https://github.com/groue/GRDB.swift) 7.11.1 | SQLite 数据库访问 | MIT | 阶段 0 已引入（`Packages/ShikeKit` 以 `exact: "7.11.1"` 锁定） |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 全局快捷键 | MIT | 计划在阶段 1 引入 |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | 自动更新 | MIT（另含其自带的第三方声明） | 计划在阶段 4 引入 |
