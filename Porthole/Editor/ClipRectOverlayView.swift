// MARK: - ClipRectOverlayView.swift
// Draggable and resizable rectangle overlay for clip editing.

import SwiftUI

/// クリップ矩形をドラッグ移動・リサイズできるオーバーレイです。
struct ClipRectOverlayView: View {
    @Binding var clipRect: ClipRect
    let viewportSize: CGSize
    let documentSize: CGSize
    let scrollOffset: CGPoint

    @State private var moveStart: OverlayDragStart?
    @State private var resizeStart: ResizeDragStart?

    private static let coordinateSpaceName = "clipRectOverlay"

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
        .coordinateSpace(name: Self.coordinateSpaceName)
    }

    private var resizeHandle: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(.blue)
            .frame(width: 14, height: 14)
            .gesture(resizeGesture)
            .shadow(radius: 1)
    }

    private var moveGesture: some Gesture {
        DragGesture(coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if moveStart == nil {
                    moveStart = OverlayDragStart(rect: clipRect, location: value.location)
                }
                guard let moveStart else { return }
                let delta = CGSize(
                    width: value.location.x - moveStart.location.x,
                    height: value.location.y - moveStart.location.y
                )
                clipRect = clamp(
                    ClipRect(
                        x: moveStart.rect.x + delta.width,
                        y: moveStart.rect.y + delta.height,
                        width: moveStart.rect.width,
                        height: moveStart.rect.height
                    )
                )
            }
            .onEnded { _ in
                moveStart = nil
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(coordinateSpace: .named(Self.coordinateSpaceName))
            .onChanged { value in
                if resizeStart == nil {
                    let handleCenter = CGPoint(
                        x: visibleX + clipRect.width,
                        y: visibleY + clipRect.height
                    )
                    resizeStart = ResizeDragStart(
                        rect: clipRect,
                        handleOffset: CGSize(
                            width: value.location.x - handleCenter.x,
                            height: value.location.y - handleCenter.y
                        ),
                        scrollOffset: scrollOffset
                    )
                }
                guard let resizeStart else { return }
                let handleCenter = CGPoint(
                    x: value.location.x - resizeStart.handleOffset.width,
                    y: value.location.y - resizeStart.handleOffset.height
                )
                let documentHandle = CGPoint(
                    x: handleCenter.x + resizeStart.scrollOffset.x,
                    y: handleCenter.y + resizeStart.scrollOffset.y
                )
                clipRect = clamp(
                    ClipRect(
                        x: resizeStart.rect.x,
                        y: resizeStart.rect.y,
                        width: documentHandle.x - resizeStart.rect.x,
                        height: documentHandle.y - resizeStart.rect.y
                    )
                )
            }
            .onEnded { _ in
                resizeStart = nil
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

private struct OverlayDragStart {
    let rect: ClipRect
    let location: CGPoint
}

private struct ResizeDragStart {
    let rect: ClipRect
    let handleOffset: CGSize
    let scrollOffset: CGPoint
}
