// MARK: - SnapshotCapturer.swift
// Captures clipped WKWebView snapshots and writes widget PNGs.

import AppKit
import CoreImage
import Foundation
import WebKit
import WidgetKit

/// Webページを読み込み、クリップ領域のPNGスナップショットを作成します。
@MainActor
final class SnapshotCapturer {
    private let webView: WKWebView
    private let navigationWaiter: SnapshotNavigationWaiter
    private let hostWindow: NSWindow
    private let schemeHandler: LocalHTMLSchemeHandler

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let handler = LocalHTMLSchemeHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: LocalHTMLSchemeHandler.scheme)
        schemeHandler = handler

        webView = WKWebView(frame: .zero, configuration: configuration)
        navigationWaiter = SnapshotNavigationWaiter()
        webView.navigationDelegate = navigationWaiter

        hostWindow = NSWindow(
            contentRect: CGRect(x: -20_000, y: -20_000, width: 1200, height: 900),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        hostWindow.isReleasedWhenClosed = false
        hostWindow.backgroundColor = .clear
        hostWindow.contentView = NSView(frame: hostWindow.contentRect(forFrameRect: hostWindow.frame))
        hostWindow.contentView?.addSubview(webView)
    }

    /// 実行中の撮影を中断します。
    func cancelCapture() {
        webView.stopLoading()
        navigationWaiter.cancel()
    }

    /// クリップを撮影し、各ウィジェットファミリー用PNGを保存します。
    func captureClip(_ clip: Clip) async throws -> Clip {
        webView.frame = CGRect(origin: .zero, size: clip.renderViewport)
        hostWindow.setContentSize(clip.renderViewport)
        hostWindow.orderBack(nil)
        let localAccess = try await loadSource(clip.source)
        defer {
            localAccess?.stopAccessing()
        }
        try await waitForCompleteDocument()
        try await waitForRenderableContent()

        let snapshotRect = try await resolveSnapshotRect(for: clip.clipMode)
        let scaleFactor = try await loadDevicePixelRatio()
        let image = try await takeSnapshot(rect: snapshotRect, scaleFactor: scaleFactor)
        try saveFamilySnapshots(from: image, clipId: clip.id)

        var updatedClip = clip
        updatedClip.lastUpdated = Date()
        updatedClip.dominantColor = extractDominantColor(from: image)
        WidgetCenter.shared.reloadTimelines(ofKind: PortholeKind.id)
        return updatedClip
    }

    private func loadSource(_ source: Source) async throws -> LocalHTMLAccess? {
        switch source {
        case let .remote(url):
            schemeHandler.accessRootURL = nil
            try await navigationWaiter.load(url, in: webView, timeoutSeconds: 30)
            return nil
        case let .localBookmark(htmlBookmark, accessRootBookmark):
            let access = try LocalHTMLSourceResolver.startAccessing(
                htmlBookmark: htmlBookmark,
                accessRootBookmark: accessRootBookmark
            )
            schemeHandler.accessRootURL = access.source.accessRootURL
            do {
                let htmlData = try Data(contentsOf: access.source.htmlURL)
                let htmlString = String(data: htmlData, encoding: .utf8)
                    ?? String(data: htmlData, encoding: .shiftJIS)
                    ?? String(data: htmlData, encoding: .isoLatin1)
                    ?? ""
                let baseURL = URL(string: "\(LocalHTMLSchemeHandler.scheme)://localhost/")
                try await navigationWaiter.loadHTMLString(
                    htmlString,
                    baseURL: baseURL,
                    in: webView,
                    timeoutSeconds: 30
                )
                return access
            } catch {
                access.stopAccessing()
                throw error
            }
        }
    }

    private func resolveSnapshotRect(for clipMode: ClipMode) async throws -> CGRect {
        switch clipMode {
        case let .rect(rect):
            return clampSnapshotRect(
                CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
            )
        case let .selector(selector):
            return try await resolveSelectorRect(selector)
        case let .selectorWithFallbackRect(selector, fallbackRect):
            return try await resolveSelectorRect(selector, fallbackRect: fallbackRect)
        }
    }

    private func clampSnapshotRect(_ rect: CGRect) -> CGRect {
        let viewport = webView.bounds
        let width = min(max(1, rect.width), max(1, viewport.width))
        let height = min(max(1, rect.height), max(1, viewport.height))
        let x = min(max(0, rect.minX), max(0, viewport.width - width))
        let y = min(max(0, rect.minY), max(0, viewport.height - height))
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func waitForCompleteDocument() async throws {
        for _ in 0..<20 {
            let state = try await evaluateJavaScript(
                "document.readyState",
                timeoutSeconds: 3,
                operationName: "readyState"
            ) as? String
            if state == "complete" { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func waitForRenderableContent() async throws {
        try await waitForFontFaceSet()
        try await waitForImages()
        try await forceLayoutAndPaint()
    }

    private func waitForFontFaceSet() async throws {
        for _ in 0..<20 {
            let status = try await evaluateJavaScript(
                "document.fonts ? document.fonts.status : 'loaded'",
                timeoutSeconds: 2,
                operationName: "fontStatus"
            ) as? String
            if status == "loaded" { return }
            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func waitForImages() async throws {
        let script = """
        (() => {
            const images = Array.from(document.images || []);
            const visibleImages = images.filter((image) => {
                const rect = image.getBoundingClientRect();
                return rect.width > 0 && rect.height > 0;
            });
            const loadedImages = visibleImages.filter((image) => {
                return image.complete && (image.naturalWidth > 0 || image.currentSrc === "" || image.src === "");
            });
            return JSON.stringify({
                visible: visibleImages.length,
                loaded: loadedImages.length
            });
        })();
        """

        for _ in 0..<30 {
            let result = try await evaluateJavaScript(
                script,
                timeoutSeconds: 2,
                operationName: "imageStatus"
            )
            guard let values = try decodeJSONObject(from: result),
                  let visibleCount = loadInteger(from: values, key: "visible"),
                  let loadedCount = loadInteger(from: values, key: "loaded") else {
                return
            }
            if visibleCount == loadedCount { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func forceLayoutAndPaint() async throws {
        let script = """
        (() => {
            document.body?.getBoundingClientRect();
            window.dispatchEvent(new Event("resize"));
            true;
        })();
        """
        _ = try await evaluateJavaScript(script, timeoutSeconds: 2, operationName: "layout")
        webView.needsLayout = true
        webView.layoutSubtreeIfNeeded()
        try await Task.sleep(nanoseconds: 500_000_000)
    }

    private func scrollToDocumentRect(_ rect: ClipRect) async throws {
        let rectJSON = try makeJSONString(["x": Double(rect.x), "y": Double(rect.y)])
        let script = """
        const targetRect = \(rectJSON);
        window.scrollTo(targetRect.x, targetRect.y);
        true;
        """
        _ = try await evaluateJavaScript(script, timeoutSeconds: 5, operationName: "scroll")
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    private func resolveSelectorRect(_ selector: String, fallbackRect: ClipRect? = nil) async throws -> CGRect {
        let selectorJSON = try makeJSONString(selector)
        let script = """
        (() => {
            const selectorValue = \(selectorJSON);
            const element = document.querySelector(selectorValue);
            if (!element) {
                return null;
            }
            element.scrollIntoView({ block: "start", inline: "start" });
            const rect = element.getBoundingClientRect();
            return JSON.stringify({
                x: Math.max(0, rect.x),
                y: Math.max(0, rect.y),
                width: Math.max(1, rect.width),
                height: Math.max(1, rect.height)
            });
        })();
        """
        _ = try await evaluateJavaScript(
            """
            (() => {
                const element = document.querySelector(\(selectorJSON));
                if (!element) return false;
                element.scrollIntoView({ block: "start", inline: "start" });
                return true;
            })();
            """,
            timeoutSeconds: 5,
            operationName: "selectorScroll"
        )
        try await forceLayoutAndPaint()
        let result = try await evaluateJavaScript(script, timeoutSeconds: 5, operationName: "selector")

        if let values = try decodeJSONObject(from: result),
           let width = loadCGFloat(from: values, key: "width"),
           let height = loadCGFloat(from: values, key: "height") {
            let x = loadCGFloat(from: values, key: "x") ?? 0
            let y = loadCGFloat(from: values, key: "y") ?? 0
            return CGRect(x: x, y: y, width: width, height: height)
        }

        if let fallbackRect {
            try await scrollToDocumentRect(fallbackRect)
            return CGRect(x: 0, y: 0, width: fallbackRect.width, height: fallbackRect.height)
        }

        throw SnapshotCaptureError.selectorNotFound(selector)
    }

    private func loadDevicePixelRatio() async throws -> CGFloat {
        let result = try await evaluateJavaScript(
            "window.devicePixelRatio || 1",
            timeoutSeconds: 3,
            operationName: "devicePixelRatio"
        )
        if let number = result as? NSNumber {
            return CGFloat(truncating: number)
        }
        return 1
    }

    private func loadCGFloat(from values: [String: Any], key: String) -> CGFloat? {
        if let number = values[key] as? NSNumber {
            return CGFloat(truncating: number)
        }
        if let value = values[key] as? Double {
            return CGFloat(value)
        }
        return nil
    }

    private func loadInteger(from values: [String: Any], key: String) -> Int? {
        if let number = values[key] as? NSNumber {
            return number.intValue
        }
        if let value = values[key] as? Int {
            return value
        }
        return nil
    }

    private func takeSnapshot(rect: CGRect, scaleFactor: CGFloat) async throws -> NSImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        configuration.snapshotWidth = NSNumber(value: Double(rect.width * scaleFactor))

        return try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let timeoutTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: SnapshotCaptureError.timeout("snapshot"))
            }
            webView.takeSnapshot(with: configuration) { image, error in
                guard !didResume else { return }
                didResume = true
                timeoutTask.cancel()
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let image else {
                    continuation.resume(throwing: SnapshotCaptureError.emptySnapshot)
                    return
                }
                continuation.resume(returning: image)
            }
        }
    }

    /// 画像全体の平均色をドミナントカラーとして抽出します。
    private func extractDominantColor(from image: NSImage) -> ClipColor? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ciImage = CIImage(cgImage: cgImage)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: ciImage,
            kCIInputExtentKey: CIVector(cgRect: ciImage.extent)
        ]), let outputImage = filter.outputImage else { return nil }

        var bitmap = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        context.render(
            outputImage,
            toBitmap: &bitmap,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return ClipColor(
            red: Double(bitmap[0]) / 255.0,
            green: Double(bitmap[1]) / 255.0,
            blue: Double(bitmap[2]) / 255.0
        )
    }

    private func saveFamilySnapshots(from image: NSImage, clipId: UUID) throws {
        for family in SnapshotFamily.allCases {
            let resizedImage = image.resized(to: family.pointSize)
            guard let data = resizedImage.pngData else {
                throw SnapshotCaptureError.pngEncodingFailed
            }
            guard let url = SnapshotStore.shared.snapshotURL(
                for: clipId,
                family: family,
                createDirectory: true
            ) else {
                throw SnapshotCaptureError.appGroupUnavailable
            }
            try data.write(to: url, options: .atomic)
        }
    }

    private func evaluateJavaScript(
        _ script: String,
        timeoutSeconds: TimeInterval,
        operationName: String
    ) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            var didResume = false
            let timeoutTask = Task { @MainActor in
                let nanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard !didResume else { return }
                didResume = true
                continuation.resume(throwing: SnapshotCaptureError.timeout(operationName))
            }
            webView.evaluateJavaScript(script) { result, error in
                guard !didResume else { return }
                didResume = true
                timeoutTask.cancel()
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private func makeJSONString(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard let string = String(data: data, encoding: .utf8) else {
            throw SnapshotCaptureError.jsonEncodingFailed
        }
        return string
    }

    private func decodeJSONObject(from value: Any?) throws -> [String: Any]? {
        guard let string = value as? String,
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}

@MainActor
private final class SnapshotNavigationWaiter: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeoutTask: Task<Void, Never>?
    private weak var loadingWebView: WKWebView?

    /// URLを読み込み、ナビゲーション完了まで待機します。
    func load(_ url: URL, in webView: WKWebView, timeoutSeconds: TimeInterval) async throws {
        try await withCheckedThrowingContinuation { continuation in
            prepareNavigation(
                continuation: continuation,
                webView: webView,
                timeoutSeconds: timeoutSeconds
            )
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
            webView.load(request)
        }
    }

    /// ローカルHTMLを読み込み、ナビゲーション完了まで待機します。
    func loadFile(
        _ htmlURL: URL,
        accessRootURL: URL,
        in webView: WKWebView,
        timeoutSeconds: TimeInterval
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            prepareNavigation(
                continuation: continuation,
                webView: webView,
                timeoutSeconds: timeoutSeconds
            )
            webView.loadFileURL(htmlURL, allowingReadAccessTo: accessRootURL)
        }
    }

    /// HTML文字列を指定のbaseURLでロードし、ナビゲーション完了まで待機します。
    func loadHTMLString(
        _ htmlString: String,
        baseURL: URL?,
        in webView: WKWebView,
        timeoutSeconds: TimeInterval
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            prepareNavigation(
                continuation: continuation,
                webView: webView,
                timeoutSeconds: timeoutSeconds
            )
            webView.loadHTMLString(htmlString, baseURL: baseURL)
        }
    }

    /// 待機中のナビゲーションをキャンセルします。
    func cancel() {
        timeoutTask?.cancel()
        resumeIfNeeded(with: .failure(SnapshotCaptureError.cancelledNavigation))
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resumeIfNeeded(with: .success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        resumeIfNeeded(with: .failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        resumeIfNeeded(with: .failure(error))
    }

    private func prepareNavigation(
        continuation: CheckedContinuation<Void, Error>,
        webView: WKWebView,
        timeoutSeconds: TimeInterval
    ) {
        resumeIfNeeded(with: .failure(SnapshotCaptureError.cancelledNavigation))
        self.continuation = continuation
        self.loadingWebView = webView
        timeoutTask = Task { @MainActor in
            let nanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            webView.stopLoading()
            self.resumeIfNeeded(with: .failure(SnapshotCaptureError.timeout("navigation")))
        }
    }

    private func resumeIfNeeded(with result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        loadingWebView = nil
        continuation.resume(with: result)
    }
}

private extension NSImage {
    var pngData: Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }

    func resized(to targetSize: CGSize) -> NSImage {
        let image = NSImage(size: targetSize)
        image.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(origin: .zero, size: targetSize).fill()

        let drawRect = makeAspectFillRect(sourceSize: size, targetSize: targetSize)
        draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        return image
    }

    private func makeAspectFillRect(sourceSize: CGSize, targetSize: CGSize) -> CGRect {
        let widthScale = targetSize.width / max(sourceSize.width, 1)
        let heightScale = targetSize.height / max(sourceSize.height, 1)
        let scale = max(widthScale, heightScale)
        let scaledSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: (targetSize.width - scaledSize.width) / 2,
            y: (targetSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

/// スナップショット撮影時に発生するエラーです。
enum SnapshotCaptureError: LocalizedError {
    case appGroupUnavailable
    case cancelledNavigation
    case emptySnapshot
    case jsonEncodingFailed
    case pngEncodingFailed
    case selectorNotFound(String)
    case timeout(String)
    case unsupportedSource

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return L10n.string("error.appGroupUnavailable")
        case .cancelledNavigation:
            return L10n.string("error.navigationCancelled")
        case .emptySnapshot:
            return L10n.string("error.emptySnapshot")
        case .jsonEncodingFailed:
            return L10n.string("error.javascriptInputEncoding")
        case .pngEncodingFailed:
            return L10n.string("error.pngEncoding")
        case let .selectorNotFound(selector):
            return L10n.format("error.selectorNotFound", selector)
        case let .timeout(operationName):
            return L10n.format("error.timeout", operationName)
        case .unsupportedSource:
            return L10n.string("error.unsupportedSource")
        }
    }
}
