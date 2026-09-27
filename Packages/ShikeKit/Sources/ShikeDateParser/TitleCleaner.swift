// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 标题清理（05 §7）：从原文去掉识别到的时间文字，得到干净的待办标题。
public enum TitleCleaner {
    private static let whitespaceRegex = try! NSRegularExpression(pattern: "\\s+")
    private static let trimCharacters = CharacterSet(charactersIn: "，。、,.;；:：!！?？~～ ")

    public static func clean(_ text: String, removing ranges: [NSRange]) -> String {
        // 1. 删除 matchedRanges 中的文字（UTF-16 区间，从后往前删避免位移）
        let nsText = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) where range.location != NSNotFound {
            nsText.deleteCharacters(in: range)
        }
        var result = nsText as String

        // 2. 连续的空白合并为一个空格
        let length = (result as NSString).length
        result = whitespaceRegex.stringByReplacingMatches(
            in: result,
            range: NSRange(location: 0, length: length),
            withTemplate: " "
        )

        // 3. 删除开头的"提醒我""记得"，以及结尾的"提醒我""提醒"
        var changed = true
        while changed {
            changed = false
            for prefix in ["提醒我", "记得"] where result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                changed = true
            }
            for suffix in ["提醒我", "提醒"] where result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                changed = true
            }
        }

        // 4. 删除首尾的空白和标点
        result = result.trimmingCharacters(in: trimCharacters)

        // 5. 结果为空时，改用原文（去掉首尾空白）作为标题
        if result.isEmpty {
            result = text.trimmingCharacters(in: .whitespaces)
        }
        return result
    }
}
