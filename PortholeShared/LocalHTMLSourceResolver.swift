// MARK: - LocalHTMLSourceResolver.swift
// Security-scoped bookmark helpers for local HTML clips.

import Foundation

/// ローカルHTMLと読み取り許可ルートの解決結果です。
struct LocalHTMLSource {
    let htmlURL: URL
    let accessRootURL: URL
    let isStale: Bool
}

/// ローカルHTMLの security-scoped resource を保持します。
final class LocalHTMLAccess {
    let source: LocalHTMLSource

    private let didAccessHTML: Bool
    private let didAccessRoot: Bool
    private var hasStoppedAccess = false

    init(source: LocalHTMLSource) {
        self.source = source
        didAccessRoot = source.accessRootURL.startAccessingSecurityScopedResource()
        didAccessHTML = source.htmlURL == source.accessRootURL
            ? false
            : source.htmlURL.startAccessingSecurityScopedResource()
    }

    deinit {
        stopAccessing()
    }

    /// security-scoped resource の利用を終了します。
    func stopAccessing() {
        guard !hasStoppedAccess else { return }
        hasStoppedAccess = true
        if didAccessHTML {
            source.htmlURL.stopAccessingSecurityScopedResource()
        }
        if didAccessRoot {
            source.accessRootURL.stopAccessingSecurityScopedResource()
        }
    }
}

/// ローカルHTMLクリップ用の bookmark 作成・解決を行います。
enum LocalHTMLSourceResolver {
    /// 指定URLの読み取り専用 security-scoped bookmark を作成します。
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// 保存済みbookmarkからHTMLファイルと読み取り許可ルートを解決します。
    static func resolve(htmlBookmark: Data, accessRootBookmark: Data) throws -> LocalHTMLSource {
        var isHTMLStale = false
        var isRootStale = false
        let htmlURL = try URL(
            resolvingBookmarkData: htmlBookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isHTMLStale
        )
        let accessRootURL = try URL(
            resolvingBookmarkData: accessRootBookmark,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isRootStale
        )
        return LocalHTMLSource(
            htmlURL: htmlURL,
            accessRootURL: accessRootURL,
            isStale: isHTMLStale || isRootStale
        )
    }

    /// bookmarkを解決し、security-scoped resource へのアクセスを開始します。
    static func startAccessing(htmlBookmark: Data, accessRootBookmark: Data) throws -> LocalHTMLAccess {
        let source = try resolve(htmlBookmark: htmlBookmark, accessRootBookmark: accessRootBookmark)
        guard !source.isStale else {
            throw LocalHTMLSourceError.staleBookmark
        }
        return LocalHTMLAccess(source: source)
    }
}

/// ローカルHTML bookmark の解決エラーです。
enum LocalHTMLSourceError: LocalizedError {
    case staleBookmark

    var errorDescription: String? {
        switch self {
        case .staleBookmark:
            return L10n.string("error.localHTMLStale")
        }
    }
}
