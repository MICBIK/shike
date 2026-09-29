// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import Foundation

/// 标题清理（05 §7）：从原文去掉识别到的时间文字，得到干净的待办标题。
public enum TitleCleaner {
    private static let whitespaceRegex = try! NSRegularExpression(pattern: "\\s+")
    private static let trimCharacters = CharacterSet(charactersIn: "，。、,.;；:：!！?？~～ ")

    public static func clean(_ text: String, removing ranges: [NSRange]) -> String {
        // 1. 删除 matchedRanges 中的文字（UTF-16 区间，从后往前删避免位移；
        // 公共 API 对越界区间防御——忽略而不是让 NSMutableString 抛异常，盲审 F3）
        let nsText = NSMutableString(string: text)
        for range in ranges.sorted(by: { $0.location > $1.location })
        where range.location != NSNotFound && NSMaxRange(range) <= nsText.length {
            nsText.deleteCharacters(in: range)
        }
        var result = nsText as String

        // 2. 连续的空白合并为一个空格
        result = collapseWhitespace(result)

        // 3+4. 重复执行"删首尾的提醒词"与"去首尾的空白和标点"，直到结果不再变化
        // （05 §7 修订，Issue #2：结尾标点会挡住提醒词的匹配，单遍执行删不干净）
        repeat {
            var changed = false
            for prefix in ["提醒我", "记得"] where result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count))
                changed = true
            }
            for suffix in ["提醒我", "提醒"] where result.hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                changed = true
            }
            let trimmed = result.trimmingCharacters(in: trimCharacters)
            if trimmed != result {
                result = trimmed
                changed = true
            }
            if !changed { break }
        } while true

        // 6. 结果为空时，改用原文（去掉首尾空白）作为标题
        if result.isEmpty {
            result = text.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    /// 仅空白与标点清理（05 §7 第 2、4 步，无提醒词、无区间删除）：
    /// 识别被取消（✕）的提交走这里——时间词留在标题里，不带 due。
    public static func stripWhitespaceAndPunctuation(_ text: String) -> String {
        var result = collapseWhitespace(text)
        result = result.trimmingCharacters(in: trimCharacters)
        if result.isEmpty {
            result = text.trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    private static func collapseWhitespace(_ text: String) -> String {
        let length = (text as NSString).length
        return whitespaceRegex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: length),
            withTemplate: " "
        )
    }
}
