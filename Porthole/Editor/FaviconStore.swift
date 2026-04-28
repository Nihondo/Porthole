// MARK: - FaviconStore.swift
// Fetches and caches site favicons for the settings sidebar.

import AppKit
import Foundation

/// Webサイトの favicon を App Group 内へキャッシュします。
@MainActor
final class FaviconStore: ObservableObject {
    @Published private var imageCache: [String: NSImage] = [:]

    private var loadingCacheKeys = Set<String>()
    private let fileManager = FileManager.default

    /// 指定クリップのfavicon画像を返し、未取得なら取得を開始します。
    func image(for clip: Clip) -> NSImage? {
        guard case let .remote(url) = clip.source else { return nil }
        guard let faviconURL = makeFaviconURL(from: url) else { return nil }
        let cacheKey = makeCacheKey(from: faviconURL)

        if let image = imageCache[cacheKey] {
            return image
        }
        if let cachedImage = loadCachedImage(for: cacheKey) {
            // ビューアップデート中の @Published 変更を避けるため次サイクルに遅延
            Task { @MainActor in imageCache[cacheKey] = cachedImage }
            return cachedImage
        }
        fetchFavicon(from: faviconURL, cacheKey: cacheKey)
        return nil
    }

    private func fetchFavicon(from faviconURL: URL, cacheKey: String) {
        guard !loadingCacheKeys.contains(cacheKey) else { return }
        loadingCacheKeys.insert(cacheKey)

        Task {
            defer {
                Task { @MainActor in
                    loadingCacheKeys.remove(cacheKey)
                }
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: faviconURL)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode),
                      let image = NSImage(data: data) else {
                    return
                }
                try saveFaviconData(data, cacheKey: cacheKey)
                await MainActor.run {
                    imageCache[cacheKey] = image
                }
            } catch {
                return
            }
        }
    }

    private func makeFaviconURL(from sourceURL: URL) -> URL? {
        guard let scheme = sourceURL.scheme,
              let host = sourceURL.host else { return nil }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.port = sourceURL.port
        components.path = "/favicon.ico"
        return components.url
    }

    private func makeCacheKey(from faviconURL: URL) -> String {
        faviconURL.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? faviconURL.absoluteString
    }

    private func loadCachedImage(for cacheKey: String) -> NSImage? {
        guard let url = faviconURL(for: cacheKey, createDirectory: false) else { return nil }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return NSImage(contentsOf: url)
    }

    private func saveFaviconData(_ data: Data, cacheKey: String) throws {
        guard let url = faviconURL(for: cacheKey, createDirectory: true) else { return }
        try data.write(to: url, options: .atomic)
    }

    private func faviconURL(for cacheKey: String, createDirectory: Bool) -> URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId
        ) else { return nil }

        let directoryURL = containerURL
            .appendingPathComponent(AppGroupConfig.applicationSupportDirectory, isDirectory: true)
            .appendingPathComponent(AppGroupConfig.faviconsDirectoryName, isDirectory: true)

        if createDirectory {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent("\(cacheKey).ico")
    }
}
