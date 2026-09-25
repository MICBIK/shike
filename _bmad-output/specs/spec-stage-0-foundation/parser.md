# ShikeDateParser：契约、迁入与测试（S0-03）

行为规则以 05 为唯一来源。本文只规定 API 形状、实现约束、从旧项目迁入的步骤，以及测试的组织方式。

## 公开 API

```swift
public struct ChineseDateParser: Sendable {
    public init(timeZone: TimeZone = .current)
    public func parse(_ text: String, now: Date) -> DateParseResult?   // 没有识别到时间时返回 nil
}

public struct DateParseResult: Sendable, Equatable {
    public let date: Date               // 全天时为该日 00:00（按 init 的时区）
    public let hasTime: Bool            // 05 §2
    public let matchedRanges: [NSRange] // UTF-16 区间，按位置排序、互不重叠
}

public enum TitleCleaner {
    // 05 §7 的第 1～5 步；ranges 为空时执行第 2～5 步
    public static func clean(_ text: String, removing ranges: [NSRange]) -> String
}
```

标题清理严格按 05 §7 原文的步骤顺序实现。步骤顺序是否要修订（结尾带标点时"提醒我"删不掉的问题），在 Issue #2 中跟踪，于 S2-02 之前决定；修订时，05、用例表和测试在同一次提交中修改。

## 实现约束

- 使用值类型，没有可变状态。内部日历固定为公历，`firstWeekday = 2`（周一），时区取 `init` 传入的值；不读取 `Calendar.current`、`Locale.current` 或 `autoupdatingCurrent`，由 CI 检查。
- 正则表达式预编译为 `static let` 形式的 `NSRegularExpression`（已标注为 Sendable，天然产出 UTF-16 的 `NSRange`）；Swift `Regex` 不能作为 `static` 常量。
- 日期要校验合法性：用 `DateComponents` 构造后，回读年、月、日必须与输入一致，否则不识别。不能依赖 `Calendar` 的宽松进位，旧实现会把"2月30号"进位成 3 月 2 日。
- 建议按内容拆分文件：日期部分、时刻部分、相对时长、歧义规则、时段表、中文数字、标题清理。
- 单次解析耗时须低于 1 毫秒（04 §10），在 S5-05 实测；阶段 0 只要求不在解析时编译正则。

## 从 TZMemo 迁入

来源：`../TZMemo/Packages/TZMemoDateParser/Sources/TZMemoDateParser/`，包括 `TZMemoDateParser.swift`（443 行）和 `ChineseNumber.swift`（34 行）。这是产品负责人自己的旧代码，不是 demo 代码，不需要登记 NOTICE。

步骤：
1. 原样复制到 `Packages/ShikeKit/Sources/ShikeDateParser/`，改名并加文件头，单独提交一次。
2. 改为下表中的新 API。
3. 以 05 §9 的测试驱动，逐条修复。
4. 不迁入 `parser-check` 可执行程序，改用 Swift Testing。旧的断言以 05 为准，与 05 冲突的一律舍弃。

| 旧 | 新 |
|---|---|
| 模块 `TZMemoDateParser` | 模块 `ShikeDateParser` |
| `public final class ChineseDateParser`，`init(calendar: Calendar = .current)`，正则用 `lazy var` | `public struct ChineseDateParser: Sendable`，`init(timeZone:)`，正则用 `static let` |
| `parse(_:now: Date = Date())` | `parse(_:now:)`，`now` 必须传入 |
| 结果含 `hasExplicitTime`、`containsTimeOfDayHint` | 结果含 `hasTime`，另有 `date`、`matchedRanges` |
| 没有标题清理 | `TitleCleaner.clean(_:removing:)` |

需要修正的行为（右列为 05 中的依据）：

| 旧行为 | 05 的规定 | 依据 |
|---|---|---|
| 只有日期时默认为 09:00 | 全天，00:00，`hasTime` 为否 | A01、B01、D01 |
| 只有时段词时不算"有时刻" | 有时段词即 `hasTime` 为是 | A06、G09 |
| 凌晨默认 01:00，早上默认 09:00 | 凌晨 05:00，早上 08:00 | §4.4、A07、G21 |
| 早上/上午 12 点换成 0 点；凌晨 12 点仍为 12 点 | 上午十二点为 12:00；凌晨十二点为 0 点 | H12、H09 |
| 中午的钟点不换算（"中午一点"为 01:00） | 1～5 点加 12 | H01、H02 |
| 午后归入中午 | 午后默认 14:00，1～11 点加 12 | H03 |
| 晚上 1～4 点加 12（即 13～16 点） | 0～4 点和 12 点为次日凌晨 | H04～H06、G07、G08 |
| 夜里等同于晚上，默认 20:00 | 夜里默认 22:00，换算规则同晚上 | §4.4、H07 |
| 半夜的钟点不换算 | 7～11 点加 12；0～6 点和 12 点为次日凌晨 | §4.4、H08 |
| 所有"周X"类都会按时刻顺延一周 | 只有无前缀的"周X"才顺延；全天时，当天不顺延 | D03、D12、D13 |
| 一周的起始随系统设置 | 固定为周一 | D16 |
| 非法日期被宽松进位 | 不识别 | J11 |
| 没有"今早" | 支持 | A09 |
| "三点钟"只高亮"三点" | 高亮"三点钟" | G14 |
| 没有冒号时间、相对时长、下周、周末 | 支持 | I01～I07、C01～C10、E01～E06 |
| 没有歧义规则 | A1～A4 及例外 | J03～J07、K01 |
| 越界的时刻可能被部分匹配 | 越界时不识别 | J08、J09 |
| 区间按"日期、时刻"的顺序追加 | 按在文本中的位置排序 | 05 §2 |
| 支持"当天" | 05 没有列出，移除 | 05 §4.1 |

## 测试组织（ShikeDateParserTests）

- 每个 05 小节对应一个参数化测试，参数是含 05 编号的用例结构，例如 `(id: "A01", input: "今天", now: .t0, expect: .allDay(2026, 9, 23), highlights: ["今天"])`。
- 期望值有以下几种：
  - `.allDay(年, 月, 日)`；
  - `.at(年, 月, 日, 时, 分)`；
  - `.none`（J 组）；
  - 区间列表（L 组）；
  - 清理后的标题（M 组）。
  05 中省略年份的日期按 2026 年处理。
- 把"高亮"列中的子串，从输入开头依次查找并换算成 `NSRange`，与 `matchedRanges` 比较。
- **守护测试：**以 `#filePath` 为起点，找到仓库根目录下的 `docs/05-中文日期解析规格.md`；从 §9 各表中提取每一行的（编号, 输入），与测试数据中的（编号, 输入）做对称差比较，结果必须为空。这样，任何一边增删改用例而另一边没有同步，CI 都会失败，06 §4.2 的"同一次提交同时修改"由此得到机械保证。
- 测试的时区一律为 Asia/Shanghai；基准时间 T0 以及用例中注明的其他基准时间，都用这个时区构造。
