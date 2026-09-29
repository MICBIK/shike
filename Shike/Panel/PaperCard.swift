// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

/// 纸感卡片底座（视觉批次二·方向一，ADR-022）：圆角卡片 + 细描边 + 柔和投影。
/// 便签用左侧装订色条（上下留边、渐变青绿）；待办用通高 3pt 左色边（颜色随状态）。
/// 高亮（新建/定位）铺青绿洗色并加重描边；hover 抬描边与投影；编辑中描边常亮。
struct PaperCard: View {
    var isHighlighted = false
    var isHovered = false
    /// 编辑中：描边青绿常亮，无 hover 效果。
    var isActive = false
    var edge: EdgeStyle = .binding

    enum EdgeStyle {
        /// 便签：装订色条（上下留 10pt）。
        case binding
        /// 待办：通高左色边。
        case leftEdge(Color)
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10)
                .fill(isHighlighted ? Color.accentColor.opacity(0.10) : Color("CardBackground"))
            switch edge {
            case .binding:
                UnevenRoundedRectangle(
                    topLeadingRadius: 0,
                    bottomLeadingRadius: 0,
                    bottomTrailingRadius: 2.5,
                    topTrailingRadius: 2.5
                )
                .fill(
                    LinearGradient(
                        colors: [Color("BindingStrip"), Color.accentColor],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 3)
                .padding(.vertical, 10)
            case .leftEdge(let color):
                color
                    .frame(width: 3)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .shadow(
            color: Color.black.opacity(isHovered && !isHighlighted ? 0.10 : 0.055),
            radius: isHovered ? 5 : 3,
            y: 1.5
        )
        .animation(Motion.gentle(0.12), value: isHovered)
        .animation(Motion.gentle(0.2), value: isHighlighted)
        .allowsHitTesting(false)
    }

    private var borderColor: Color {
        if isHighlighted { return Color.accentColor.opacity(0.45) }
        if isActive { return Color.accentColor.opacity(0.55) }
        if isHovered { return Color.accentColor.opacity(0.30) }
        return Color("CardBorder")
    }
}

/// 分组标签（纸感批次）：小号加重 + 字距 + 浅色计数；逾期组保持红字。
struct GroupHeader: View {
    let title: String
    var count: Int?
    var isOverdue = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(isOverdue ? Color.red : Color.secondary)
            if let count {
                Text("\(count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOverdue ? Color.red.opacity(0.55) : Color.secondary.opacity(0.55))
            }
        }
        .textCase(nil)
    }
}
