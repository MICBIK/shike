// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 本文件自拾刻前项目 TZMemo 的 TZMemoDateParser 原样迁入（Story 1.15，2026-09-27），
// 随后的行为修正以 05 §9 用例驱动，见后续提交。

import Foundation

/// 中文数字/阿拉伯数字混合解析（如「二十三」「十五」「两」「8」「12」）。
enum ChineseNumber {
    private static let digitMap: [Character: Int] = [
        "零": 0, "〇": 0,
        "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
    ]

    static func parse(_ text: some StringProtocol) -> Int? {
        var total = 0
        var current = 0
        var sawDigit = false

        for character in text {
            if let digit = character.wholeNumberValue, (0...9).contains(digit) {
                current = current * 10 + digit
                sawDigit = true
            } else if let digit = digitMap[character] {
                current = current * 10 + digit
                sawDigit = true
            } else if character == "十" {
                if current == 0 { current = 1 }
                total += current * 10
                current = 0
                sawDigit = true
            } else {
                return nil
            }
        }
        return sawDigit ? total + current : nil
    }
}
