// MARK: - LocalHTMLSchemeHandler.swift
// porthole-local:// スキームでローカルHTMLリソースを提供し、ルート絶対パスを解決します。

import Foundation
import os.log
import WebKit

private let log = OSLog(subsystem: "com.dmng.porthole", category: "LocalHTMLScheme")

/// カスタムスキーム porthole-local:// でローカルHTMLリソースを提供します。
/// HTML内の /path/to/resource のようなルート絶対パスを accessRootURL に相対的に解決します。
final class LocalHTMLSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "porthole-local"

    /// 現在のセッションの読み取りルートURLです。ロード前に設定してください。
    var accessRootURL: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let accessRootURL else {
            os_log("start: accessRootURL が未設定", log: log, type: .error)
            urlSchemeTask.didFailWithError(LocalHTMLSchemeError.noAccessRoot)
            return
        }
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(LocalHTMLSchemeError.invalidURL)
            return
        }

        let normalizedRoot = normalizedRootPath(of: accessRootURL)
        let rawPath = requestURL.path.hasPrefix("/") ? String(requestURL.path.dropFirst()) : requestURL.path
        let fileURL = accessRootURL.appendingPathComponent(rawPath).resolvingSymlinksInPath()

        guard fileURL.path.hasPrefix(normalizedRoot) else {
            os_log("start: アクセス拒否 fileURL=%{public}@ root=%{public}@", log: log, type: .error, fileURL.path, normalizedRoot)
            urlSchemeTask.didFailWithError(LocalHTMLSchemeError.accessDenied(fileURL.path))
            return
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let response = URLResponse(
                url: requestURL,
                mimeType: Self.mimeType(for: fileURL),
                expectedContentLength: data.count,
                textEncodingName: "utf-8"
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            os_log("start: ファイル読み込み失敗 %{public}@ error=%{public}@", log: log, type: .error, fileURL.path, error.localizedDescription)
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// HTMLファイルURLとアクセスルートからカスタムスキームURLを生成します。
    /// シンボリックリンクを解決してパスを正規化するため、bookmark 解決後の URL にも対応します。
    static func makeSchemeURL(htmlURL: URL, accessRootURL: URL) -> URL? {
        let resolvedHTML = htmlURL.resolvingSymlinksInPath()
        let resolvedRoot = accessRootURL.resolvingSymlinksInPath()
        let rootPath = resolvedRoot.path
        let htmlPath = resolvedHTML.path
        let normalizedRoot = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard htmlPath.hasPrefix(normalizedRoot) else {
            os_log("makeSchemeURL: プレフィックス不一致 html=%{public}@ root=%{public}@", log: log, type: .error, htmlPath, normalizedRoot)
            return nil
        }
        let relative = "/" + String(htmlPath.dropFirst(normalizedRoot.count))
        guard let encoded = relative.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "\(scheme)://localhost\(encoded)")
    }

    private func normalizedRootPath(of url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path
        return path.hasSuffix("/") ? path : path + "/"
    }

    private static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html", "htm": return "text/html"
        case "css":         return "text/css"
        case "js":          return "application/javascript"
        case "mjs":         return "application/javascript"
        case "png":         return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif":         return "image/gif"
        case "svg":         return "image/svg+xml"
        case "webp":        return "image/webp"
        case "woff":        return "font/woff"
        case "woff2":       return "font/woff2"
        case "ttf":         return "font/ttf"
        case "otf":         return "font/otf"
        case "json":        return "application/json"
        case "xml":         return "application/xml"
        case "ico":         return "image/x-icon"
        default:            return "application/octet-stream"
        }
    }
}

enum LocalHTMLSchemeError: LocalizedError {
    case noAccessRoot
    case invalidURL
    case accessDenied(String)

    var errorDescription: String? {
        switch self {
        case .noAccessRoot:
            return L10n.string("error.schemeMissingRoot")
        case .invalidURL:
            return L10n.string("error.schemeInvalidURL")
        case let .accessDenied(path):
            return L10n.format("error.schemeAccessDenied", path)
        }
    }
}
