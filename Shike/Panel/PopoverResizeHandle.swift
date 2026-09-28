// Shike（拾刻）
// Copyright (C) 2026 Shike contributors
// SPDX-License-Identifier: GPL-3.0-only
//
// 部分代码源自 Reminders MenuBar（https://github.com/DamascenoRafael/reminders-menubar），
// Copyright (C) Rafael Damasceno and contributors，以 GPL-3.0 授权。
// 修改说明：自 demo 的 PopoverResizeHandleView.swift 与 NSCursor+Extensions.swift 移植；
// 去掉 AppDelegate.shared 全局单例，改经回调读写尺寸；光标用系统 crosshair
// （demo 的图片光标依赖资源目录，拾刻阶段 1 不建 Assets）；帮助气泡省略（2026-09-28）。

import AppKit
import SwiftUI

/// 面板右下角的尺寸把手（03 §3，S1-01）：拖动实时回调建议尺寸，结束时回调 isFinal = true。
/// 尺寸的钳制与持久化由 PopoverController 负责，本视图只报告手势。
struct PopoverResizeHandle: View {
    /// 当前面板尺寸（把手据此累计拖动位移）。
    let currentSize: () -> CGSize
    /// 拖动回调：proposed 为"起始尺寸 + 位移"；isFinal 为 true 表示鼠标已抬起。
    let onResize: (_ proposed: CGSize, _ isFinal: Bool) -> Void

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragStartSize: CGSize?

    private var shouldShowResizeCursor: Bool {
        isHovering || isDragging
    }

    var body: some View {
        ZStack {
            CornerArcGrabber()
                .stroke(Color.secondary.opacity(shouldShowResizeCursor ? 0.85 : 0.35),
                        style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .background(
                    CornerArcGrabber()
                        .stroke(shouldShowResizeCursor ? Color.primary.opacity(0.12) : .clear,
                                style: StrokeStyle(lineWidth: 9.0, lineCap: .round))
                )
                .padding(4)
        }
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .onChange(of: shouldShowResizeCursor) { _, showCursor in
            if showCursor {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        .onDisappear {
            if shouldShowResizeCursor {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if dragStartSize == nil {
                        isDragging = true
                        dragStartSize = currentSize()
                    }
                    guard let startSize = dragStartSize else { return }
                    onResize(
                        CGSize(width: startSize.width + value.translation.width,
                               height: startSize.height + value.translation.height),
                        false
                    )
                }
                .onEnded { value in
                    let startSize = dragStartSize ?? currentSize()
                    onResize(
                        CGSize(width: startSize.width + value.translation.width,
                               height: startSize.height + value.translation.height),
                        true
                    )
                    dragStartSize = nil
                    isDragging = false
                }
        )
    }
}

/// 把手的圆弧形状：右下角一段向内收的四分之一圆（移植自 demo 的 CornerArcGrabber）。
private struct CornerArcGrabber: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()

        let radius = min(rect.width, rect.height)
        let start = CGPoint(x: rect.maxX - radius, y: rect.maxY)
        let end = CGPoint(x: rect.maxX, y: rect.maxY - radius)
        let control = CGPoint(x: rect.maxX, y: rect.maxY)

        path.move(to: start)
        path.addQuadCurve(to: end, control: control)

        return path
    }
}
