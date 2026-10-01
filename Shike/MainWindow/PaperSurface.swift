// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only

import SwiftUI

extension View {
    /// 主窗口内容区的纸感底（S3.5 集成统一）：纸青渐变垫厚材质，
    /// 同 PanelView 的纸面（PaperTop/PaperMid/PaperBottom 双外观资产）。
    /// 便签/待办/回收站三个分区统一调用，左栏切换入口时背景不跳变。
    func paperSurface() -> some View {
        background(Self.paperGradient.opacity(0.94))
            .background(.thickMaterial)
    }

    /// 纸感渐变：上青下白（同 PanelView.paperGradient）。
    private static var paperGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color("PaperTop"),
                Color("PaperMid"),
                Color("PaperBottom"),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}
