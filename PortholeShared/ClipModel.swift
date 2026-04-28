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
    /// ページ読み込み完了後、撮影開始までの待機秒数です。
    var captureDelaySeconds: TimeInterval
    var lastUpdated: Date?
    var dominantColor: ClipColor?

    init(
        id: UUID,
        name: String,
        source: Source,
        clipMode: ClipMode,
        renderViewport: CGSize,
        refreshSeconds: TimeInterval,
        captureDelaySeconds: TimeInterval = 0,
        lastUpdated: Date? = nil,
        dominantColor: ClipColor? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.clipMode = clipMode
        self.renderViewport = renderViewport
        self.refreshSeconds = refreshSeconds
        self.captureDelaySeconds = captureDelaySeconds
        self.lastUpdated = lastUpdated
        self.dominantColor = dominantColor
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        source = try c.decode(Source.self, forKey: .source)
        clipMode = try c.decode(ClipMode.self, forKey: .clipMode)
        renderViewport = try c.decode(CGSize.self, forKey: .renderViewport)
        refreshSeconds = try c.decode(TimeInterval.self, forKey: .refreshSeconds)
        captureDelaySeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .captureDelaySeconds) ?? 0
        lastUpdated = try c.decodeIfPresent(Date.self, forKey: .lastUpdated)
        dominantColor = try c.decodeIfPresent(ClipColor.self, forKey: .dominantColor)
    }

    /// 初期表示と疎通確認に使う最小サンプルを作成します。
    static func makeSampleClip() -> Clip {
        Clip(
            id: UUID(uuidString: "4F4D7F6E-9F3D-4C24-8AC6-B03DB8C01A01") ?? UUID(),
            name: "Apple Japan",
            source: .remote(URL(string: "https://www.apple.com/jp/")!),
            clipMode: .rect(ClipRect(x: 0, y: 0, width: 338, height: 158)),
            renderViewport: CGSize(width: 1200, height: 900),
            refreshSeconds: 1800
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
            refreshSeconds: 1800
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

/// スナップショットから抽出したウィジェット背景用の代表色です。
struct ClipColor: Codable, Hashable {
    var red: Double
    var green: Double
    var blue: Double
}
