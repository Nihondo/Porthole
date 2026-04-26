// MARK: - ClipRectOverlayView.swift
// Draggable and resizable rectangle overlay for clip editing.

import SwiftUI

/// クリップ矩形をドラッグ移動・リサイズできるオーバーレイです。
struct ClipRectOverlayView: View {
    @Binding var clipRect: ClipRect
    let viewportSize: CGSize
    let documentSize: CGSize
    let scrollOffset: CGPoint

    @State private var moveStartRect: ClipRect?
    @State private var resizeStartRect: ClipRect?

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(.blue, lineWidth: 2)
                .background(.blue.opacity(0.12))
                .frame(width: clipRect.width, height: clipRect.height)
                .position(
                    x: visibleX + clipRect.width / 2,
                    y: visibleY + clipRect.height / 2
                )
                .gesture(moveGesture)

            resizeHandle
                .position(x: visibleX + clipRect.width, y: visibleY + clipRect.height)
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
    }

    private var resizeHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.blue)
            .frame(width: 14, height: 14)
            .gesture(resizeGesture)
            .shadow(radius: 1)
    }

    private var moveGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if moveStartRect == nil {
                    moveStartRect = clipRect
                }
                guard let startRect = moveStartRect else { return }
                clipRect = clamp(
                    ClipRect(
                        x: startRect.x + value.translation.width,
                        y: startRect.y + value.translation.height,
                        width: startRect.width,
                        height: startRect.height
                    )
                )
            }
            .onEnded { _ in
                moveStartRect = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if resizeStartRect == nil {
                    resizeStartRect = clipRect
                }
                guard let startRect = resizeStartRect else { return }
                clipRect = clamp(
                    ClipRect(
                        x: startRect.x,
                        y: startRect.y,
                        width: startRect.width + value.translation.width,
                        height: startRect.height + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                resizeStartRect = nil
            }
    }

    private func clamp(_ rect: ClipRect) -> ClipRect {
        let contentSize = CGSize(
            width: max(viewportSize.width, documentSize.width),
            height: max(viewportSize.height, documentSize.height)
        )
        let width = min(max(20, rect.width), contentSize.width)
        let height = min(max(20, rect.height), contentSize.height)
        let x = min(max(0, rect.x), max(0, contentSize.width - width))
        let y = min(max(0, rect.y), max(0, contentSize.height - height))
        return ClipRect(x: x, y: y, width: width, height: height)
    }

    private var visibleX: CGFloat {
        clipRect.x - scrollOffset.x
    }

    private var visibleY: CGFloat {
        clipRect.y - scrollOffset.y
    }
}
