// MARK: - ClipModel.swift
// Shared clip model used by the app and widget targets.

import CoreGraphics
import Foundation

/// ウィジェットへ表示するWebクリップの定義です。
struct Clip: Codable, Identifiable, Hashable {
    let id: UUID
    var name: String
    var source: Source
    var clipMode: ClipMode
    var renderViewport: CGSize
    var refreshSeconds: TimeInterval
    var lastUpdated: Date?

    /// 初期表示と疎通確認に使う最小サンプルを作成します。
    static func makeSampleClip() -> Clip {
        Clip(
            id: UUID(uuidString: "4F4D7F6E-9F3D-4C24-8AC6-B03DB8C01A01") ?? UUID(),
            name: "Apple Japan",
            source: .remote(URL(string: "https://www.apple.com/jp/")!),
            clipMode: .rect(ClipRect(x: 0, y: 0, width: 338, height: 158)),
            renderViewport: CGSize(width: 1200, height: 900),
            refreshSeconds: 1800,
            lastUpdated: nil
        )
    }

    /// ユーザーが追加する新規remote URLクリップを作成します。
    static func makeNewRemoteClip(index: Int) -> Clip {
        Clip(
            id: UUID(),
            name: "New Clip \(index)",
            source: .remote(URL(string: "https://www.apple.com/jp/")!),
            clipMode: .rect(ClipRect(x: 0, y: 0, width: 338, height: 158)),
            renderViewport: CGSize(width: 1200, height: 900),
            refreshSeconds: 1800,
            lastUpdated: nil
        )
    }
}

/// クリップの読み込み元を表します。
enum Source: Codable, Hashable {
    case remote(URL)
    case localBookmark(htmlBookmark: Data, accessRootBookmark: Data)
}

/// クリップ領域の指定方法です。
enum ClipMode: Codable, Hashable {
    case rect(ClipRect)
    case selector(String)
    case selectorWithFallbackRect(selector: String, fallbackRect: ClipRect)
}

/// ページ全体を基準にしたクリップ矩形です。
struct ClipRect: Codable, Hashable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat
}
