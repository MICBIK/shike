# 拾刻 Shike

macOS 菜单栏便签与待办：随手呼出，几秒记下；便签能钉在桌面上随时看，待办能用中文说时间、到点提醒。

> **状态：**开发中，当前处于阶段 0（地基），还没有可以下载的版本。

## 计划中的功能

- 快捷键呼出，3 秒内记下一条便签或待办
- 识别中文时间：输入"周五下午三点交报告"，一句话就建好提醒
- 便签钉到桌面：可以置顶、自动隐藏、鼠标靠近再浮现，每种表现方式都可以自己选
- 数据只存在本机：没有账号，没有遥测，每天自动备份

完整规划见 [阶段路线图](docs/02-阶段路线图.md)。

## 系统要求

macOS 15 或更高。

## 安装

从阶段 4（v0.5）开始提供安装包和安装说明。

## 从源码构建

需要 macOS 15 及以上的 Mac：
1. 安装 [Xcode 26 或更高版本](https://developer.apple.com/xcode/)，首次安装后在终端执行一次 `xcodebuild -runFirstLaunch`（否则命令行构建会报 CoreSimulator 相关错误）；
2. 用 Homebrew 安装 XcodeGen：`brew install xcodegen`。

然后：

```bash
git clone https://github.com/MICBIK/shike.git
cd shike
xcodegen generate                        # 从 project.yml 生成 Shike.xcodeproj
swift test --package-path Packages/ShikeKit   # 运行数据层与解析器包的测试
xcodebuild -project Shike.xcodeproj -scheme Shike \
  -destination 'platform=macOS' build test    # 构建 App 并运行 App 层测试
open Shike.xcodeproj                     # 或直接用 Xcode 打开开发
```

生成工程后重新打开 Xcode 即可获得最新工程；生成的 `Shike.xcodeproj` 与构建产物不入库。

提交前可以在本地跑一次架构合规检查（与 CI 的 `checks` 作业同一份脚本）：

```bash
bash scripts/checks.sh              # 文件头、导入边界、解析器区域、禁用项
```

详细说明见 [开发规范](docs/06-开发规范.md)。

## 文档

所有文档从 [docs/README.md](docs/README.md) 开始阅读。

## 许可证与致谢

拾刻以 [GPL-3.0](LICENSE) 发布。部分代码源自 [Reminders MenuBar](https://github.com/DamascenoRafael/reminders-menubar)（Rafael Damasceno，GPL-3.0），详见 [NOTICE.md](NOTICE.md)。
