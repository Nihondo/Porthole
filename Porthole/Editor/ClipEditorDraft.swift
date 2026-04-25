// MARK: - ClipEditorDraft.swift
// Editable draft state for the M3 clip editor.

import CoreGraphics
import Foundation

/// クリップ編集画面で選択できるクリッピング方式です。
enum EditorClipMode: String, CaseIterable, Identifiable {
    case rect
    case selector

    var id: String { rawValue }

    /// 画面表示用の名前です。
    var title: String {
        switch self {
        case .rect:
            return "矩形"
        case .selector:
            return "セレクタ"
        }
    }
}

/// クリップ編集画面で選択できる読み込み元です。
enum EditorSourceKind: String, CaseIterable, Identifiable {
    case remote
    case localHTML

    var id: String { rawValue }

    /// 画面表示用の名前です。
    var title: String {
        switch self {
        case .remote:
            return "URL"
        case .localHTML:
            return "ローカルHTML"
        }
    }
}

/// クリップ編集画面で使う保存前の下書き状態です。
@MainActor
final class ClipEditorDraft: ObservableObject {
    @Published var clipId: UUID?
    @Published var name = ""
    @Published var sourceKind: EditorSourceKind = .remote
    @Published var urlString = ""
    @Published var localHTMLPath = ""
    @Published var localAccessRootPath = ""
    @Published var viewportWidth = 1200.0
    @Published var viewportHeight = 900.0
    @Published var refreshSeconds = 1800.0
    @Published var clipMode: EditorClipMode = .rect
    @Published var clipRect = ClipRect(x: 0, y: 0, width: 338, height: 158)
    @Published var selector = ""
    @Published var validationMessage: String?
    private var localHTMLBookmark: Data?
    private var localAccessRootBookmark: Data?
    private var lastUpdated: Date?

    /// 既存クリップから下書きを読み込みます。
    func load(from clip: Clip?) {
        guard let clip else {
            clipId = nil
            name = ""
            sourceKind = .remote
            urlString = ""
            localHTMLPath = ""
            localAccessRootPath = ""
            localHTMLBookmark = nil
            localAccessRootBookmark = nil
            validationMessage = nil
            return
        }

        clipId = clip.id
        name = clip.name
        loadSource(from: clip.source)
        viewportWidth = clip.renderViewport.width
        viewportHeight = clip.renderViewport.height
        refreshSeconds = clip.refreshSeconds
        clipMode = clip.editorClipMode
        clipRect = clip.rectClip ?? ClipRect(x: 0, y: 0, width: 338, height: 158)
        selector = clip.selectorValue ?? ""
        lastUpdated = clip.lastUpdated
        validationMessage = nil
    }

    /// 下書きから保存可能な Clip を生成します。
    func makeClip() -> Clip? {
        guard let clipId else {
            validationMessage = "クリップが選択されていません"
            return nil
        }
        guard clipMode == .rect || !normalizedSelector.isEmpty else {
            validationMessage = "CSSセレクタを入力してください"
            return nil
        }
        guard let source = makeSource() else { return nil }

        validationMessage = nil
        return Clip(
            id: clipId,
            name: normalizedName,
            source: source,
            clipMode: normalizedClipMode,
            renderViewport: normalizedViewport,
            refreshSeconds: max(30, refreshSeconds),
            lastUpdated: lastUpdated
        )
    }

    /// 入力中のURLをURL型で返します。
    var previewURL: URL? {
        URL(string: urlString)
    }

    /// 入力中のソースをプレビュー用に返します。
    var previewSource: Source? {
        switch sourceKind {
        case .remote:
            guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
                return nil
            }
            return .remote(url)
        case .localHTML:
            guard let localHTMLBookmark, let localAccessRootBookmark else { return nil }
            return .localBookmark(
                htmlBookmark: localHTMLBookmark,
                accessRootBookmark: localAccessRootBookmark
            )
        }
    }

    /// 選択されたローカルHTMLを下書きへ保存します。
    func setLocalHTML(
        htmlURL: URL,
        accessRootURL: URL,
        htmlBookmark: Data,
        accessRootBookmark: Data
    ) {
        sourceKind = .localHTML
        localHTMLPath = htmlURL.path
        localAccessRootPath = accessRootURL.path
        localHTMLBookmark = htmlBookmark
        localAccessRootBookmark = accessRootBookmark
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = htmlURL.deletingPathExtension().lastPathComponent
        }
    }

    private var normalizedName: String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedName.isEmpty ? "Untitled Clip" : trimmedName
    }

    private var normalizedSelector: String {
        selector.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedClipMode: ClipMode {
        switch clipMode {
        case .rect:
            return .rect(normalizedRect)
        case .selector:
            return .selectorWithFallbackRect(selector: normalizedSelector, fallbackRect: normalizedRect)
        }
    }

    private var normalizedViewport: CGSize {
        CGSize(
            width: max(320, viewportWidth.rounded()),
            height: max(240, viewportHeight.rounded())
        )
    }

    private var normalizedRect: ClipRect {
        let maxX = max(0, normalizedViewport.width - 1)
        let maxY = max(0, normalizedViewport.height - 1)
        let x = min(max(0, clipRect.x), maxX)
        let y = min(max(0, clipRect.y), maxY)
        let width = min(max(20, clipRect.width), normalizedViewport.width - x)
        let height = min(max(20, clipRect.height), normalizedViewport.height - y)
        return ClipRect(x: x, y: y, width: width, height: height)
    }

    private func loadSource(from source: Source) {
        switch source {
        case let .remote(url):
            sourceKind = .remote
            urlString = url.absoluteString
            localHTMLPath = ""
            localAccessRootPath = ""
            localHTMLBookmark = nil
            localAccessRootBookmark = nil
        case let .localBookmark(htmlBookmark, accessRootBookmark):
            sourceKind = .localHTML
            urlString = ""
            localHTMLBookmark = htmlBookmark
            localAccessRootBookmark = accessRootBookmark
            if let resolved = try? LocalHTMLSourceResolver.resolve(
                htmlBookmark: htmlBookmark,
                accessRootBookmark: accessRootBookmark
            ) {
                localHTMLPath = resolved.htmlURL.path
                localAccessRootPath = resolved.accessRootURL.path
            } else {
                localHTMLPath = "選択済みHTML"
                localAccessRootPath = "選択済み読み取りルート"
            }
        }
    }

    private func makeSource() -> Source? {
        switch sourceKind {
        case .remote:
            guard let url = URL(string: urlString), url.scheme?.hasPrefix("http") == true else {
                validationMessage = "有効なURLを入力してください"
                return nil
            }
            return .remote(url)
        case .localHTML:
            guard let localHTMLBookmark, let localAccessRootBookmark else {
                validationMessage = "ローカルHTMLファイルを選択してください"
                return nil
            }
            return .localBookmark(
                htmlBookmark: localHTMLBookmark,
                accessRootBookmark: localAccessRootBookmark
            )
        }
    }
}

private extension Clip {
    var remoteURL: URL? {
        guard case let .remote(url) = source else { return nil }
        return url
    }

    var rectClip: ClipRect? {
        switch clipMode {
        case let .rect(rect):
            return rect
        case let .selectorWithFallbackRect(_, fallbackRect):
            return fallbackRect
        case .selector:
            return nil
        }
    }

    var selectorValue: String? {
        switch clipMode {
        case let .selector(selector):
            return selector
        case let .selectorWithFallbackRect(selector, _):
            return selector
        case .rect:
            return nil
        }
    }

    var editorClipMode: EditorClipMode {
        switch clipMode {
        case .rect:
            return .rect
        case .selector, .selectorWithFallbackRect:
            return .selector
        }
    }
}
