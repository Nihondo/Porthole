// MARK: - WebClipPreview.swift
// WKWebView preview used by the clip editor.

import SwiftUI
import WebKit

/// WebView内で選択された要素の情報です。
struct WebElementSelection {
    let selector: String
    let rect: ClipRect
}

/// クリップ編集用のプレビューWebViewを管理します。
@MainActor
final class WebClipPreviewStore: NSObject, ObservableObject, WKNavigationDelegate {
    let webView: WKWebView
    @Published var loadedURL: URL?
    @Published var isPickingElement = false
    @Published var scrollOffset = CGPoint.zero
    @Published var documentSize = CGSize.zero

    private var loadedSourceIdentifier: String?
    private var activeLocalAccess: LocalHTMLAccess?
    private var pickerContinuation: CheckedContinuation<WebElementSelection, Error>?
    private var pickerTimeoutTask: Task<Void, Never>?
    private var pickerMessageHandler: WebClipPickerMessageHandler?
    private var metricsMessageHandler: WebClipMetricsMessageHandler?
    private let schemeHandler: LocalHTMLSchemeHandler

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let handler = LocalHTMLSchemeHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: LocalHTMLSchemeHandler.scheme)
        schemeHandler = handler

        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        let pickerHandler = WebClipPickerMessageHandler { [weak self] message in
            self?.handlePickerMessage(message)
        }
        let metricsHandler = WebClipMetricsMessageHandler { [weak self] message in
            self?.handleMetricsMessage(message)
        }
        pickerMessageHandler = pickerHandler
        metricsMessageHandler = metricsHandler
        configuration.userContentController.add(pickerHandler, name: "portholePicker")
        configuration.userContentController.add(metricsHandler, name: "portholeMetrics")
        configuration.userContentController.addUserScript(Self.makeMetricsUserScript())
        webView.navigationDelegate = self
        refreshScrollMetrics()
    }

    deinit {
        activeLocalAccess?.stopAccessing()
    }

    /// 指定ソースをプレビューへ読み込みます。
    func load(_ source: Source?) throws {
        guard let source else { return }

        switch source {
        case let .remote(url):
            let identifier = "remote:\(url.absoluteString)"
            guard loadedSourceIdentifier != identifier else { return }
            activeLocalAccess?.stopAccessing()
            activeLocalAccess = nil
            loadedSourceIdentifier = identifier
            loadedURL = url
            webView.load(URLRequest(url: url))
            refreshScrollMetrics()
        case let .localBookmark(htmlBookmark, accessRootBookmark):
            let access = try LocalHTMLSourceResolver.startAccessing(
                htmlBookmark: htmlBookmark,
                accessRootBookmark: accessRootBookmark
            )
            let identifier = "local:\(access.source.htmlURL.path):\(access.source.accessRootURL.path)"
            if loadedSourceIdentifier == identifier {
                access.stopAccessing()
                refreshScrollMetrics()
                return
            }
            let htmlData = try Data(contentsOf: access.source.htmlURL)
            let htmlString = String(data: htmlData, encoding: .utf8)
                ?? String(data: htmlData, encoding: .shiftJIS)
                ?? String(data: htmlData, encoding: .isoLatin1)
                ?? ""
            activeLocalAccess?.stopAccessing()
            activeLocalAccess = access
            loadedSourceIdentifier = identifier
            loadedURL = access.source.htmlURL
            schemeHandler.accessRootURL = access.source.accessRootURL
            let baseURL = URL(string: "\(LocalHTMLSchemeHandler.scheme)://localhost/")
            webView.loadHTMLString(htmlString, baseURL: baseURL)
            refreshScrollMetrics()
        }
    }

    /// WebViewのスクロール位置と本文サイズをSwiftUI側へ同期します。
    func refreshScrollMetrics() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let result = try? await evaluateJavaScript(
                Self.metricsScript,
                timeoutSeconds: 2,
                operationName: "scroll metrics"
            ) else {
                applyFallbackScrollMetrics()
                return
            }
            applyScrollMetrics(from: result)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshScrollMetrics()
    }

    /// WebView内でクリックした要素のCSSセレクタを取得します。
    func pickElement() async throws -> WebElementSelection {
        guard !isPickingElement else {
            throw WebClipPreviewError.alreadyPicking
        }
        isPickingElement = true
        defer { isPickingElement = false }

        let script = """
        (() => {
            const old = document.getElementById("__porthole_picker_overlay");
            if (old) old.remove();
            if (typeof window.__portholePickerCleanup === "function") {
                window.__portholePickerCleanup();
            }

            const overlay = document.createElement("div");
            overlay.id = "__porthole_picker_overlay";
            overlay.style.position = "fixed";
            overlay.style.pointerEvents = "none";
            overlay.style.zIndex = "2147483647";
            overlay.style.border = "2px solid #0A84FF";
            overlay.style.background = "rgba(10, 132, 255, 0.14)";
            overlay.style.boxSizing = "border-box";
            document.documentElement.appendChild(overlay);

            function cssEscape(value) {
                if (window.CSS && CSS.escape) return CSS.escape(value);
                return String(value).replace(/[^a-zA-Z0-9_-]/g, "\\\\$&");
            }

            function selectorFor(element) {
                if (!element || element.nodeType !== Node.ELEMENT_NODE) return "";
                if (element.id) return "#" + cssEscape(element.id);
                const parts = [];
                let current = element;
                while (current && current.nodeType === Node.ELEMENT_NODE && current !== document.documentElement) {
                    let part = current.localName.toLowerCase();
                    if (current.classList && current.classList.length > 0) {
                        part += "." + Array.from(current.classList).slice(0, 2).map(cssEscape).join(".");
                    }
                    const parent = current.parentElement;
                    if (parent) {
                        const siblings = Array.from(parent.children).filter((child) => child.localName === current.localName);
                        if (siblings.length > 1) {
                            part += `:nth-of-type(${siblings.indexOf(current) + 1})`;
                        }
                    }
                    parts.unshift(part);
                    if (parts.length >= 5) break;
                    current = parent;
                }
                return parts.join(" > ");
            }

            function updateOverlay(element) {
                const rect = element.getBoundingClientRect();
                overlay.style.left = rect.left + "px";
                overlay.style.top = rect.top + "px";
                overlay.style.width = rect.width + "px";
                overlay.style.height = rect.height + "px";
            }

            function cleanup() {
                document.removeEventListener("mousemove", onMove, true);
                document.removeEventListener("click", onClick, true);
                overlay.remove();
                if (window.__portholePickerCleanup === cleanup) {
                    delete window.__portholePickerCleanup;
                }
            }

            function onMove(event) {
                const element = document.elementFromPoint(event.clientX, event.clientY);
                if (element && element !== overlay) updateOverlay(element);
            }

            function onClick(event) {
                event.preventDefault();
                event.stopPropagation();
                const element = document.elementFromPoint(event.clientX, event.clientY);
                if (!element || element === overlay) return;
                const rect = element.getBoundingClientRect();
                const result = {
                    selector: selectorFor(element),
                    rect: {
                        x: Math.max(0, rect.x + window.scrollX),
                        y: Math.max(0, rect.y + window.scrollY),
                        width: Math.max(1, rect.width),
                        height: Math.max(1, rect.height)
                    }
                };
                cleanup();
                window.webkit.messageHandlers.portholePicker.postMessage(JSON.stringify(result));
            }

            window.__portholePickerCleanup = cleanup;
            document.addEventListener("mousemove", onMove, true);
            document.addEventListener("click", onClick, true);
            return "installed";
        })();
        """

        let installResult = try await evaluateJavaScript(script, timeoutSeconds: 5, operationName: "element picker install")
        guard installResult as? String == "installed" else {
            throw WebClipPreviewError.invalidSelection
        }
        return try await waitForPickerSelection(timeoutSeconds: 60)
    }

    private func waitForPickerSelection(timeoutSeconds: TimeInterval) async throws -> WebElementSelection {
        try await withCheckedThrowingContinuation { continuation in
            pickerContinuation = continuation
            pickerTimeoutTask = Task { @MainActor in
                let nanoseconds = UInt64(timeoutSeconds * 1_000_000_000)
                try? await Task.sleep(nanoseconds: nanoseconds)
                guard pickerContinuation != nil else { return }
                _ = try? await evaluateJavaScript(
                    """
                    (() => {
                        if (typeof window.__portholePickerCleanup === "function") {
                            window.__portholePickerCleanup();
                        }
                        return "cancelled";
                    })();
                    """,
                    timeoutSeconds: 2,
                    operationName: "element picker cleanup"
                )
                finishPicker(with: .failure(WebClipPreviewError.timeout("element picker")))
            }
        }
    }

    private func handlePickerMessage(_ message: WKScriptMessage) {
        guard message.name == "portholePicker",
              let result = message.body as? String else {
            finishPicker(with: .failure(WebClipPreviewError.invalidSelection))
            return
        }

        guard let values = try? decodeJSONObject(from: result),
              let selector = values["selector"] as? String,
              let rectValues = values["rect"] as? [String: Any],
              let rect = makeClipRect(from: rectValues) else {
            finishPicker(with: .failure(WebClipPreviewError.invalidSelection))
            return
        }
        finishPicker(with: .success(WebElementSelection(selector: selector, rect: rect)))
    }

    private func finishPicker(with result: Result<WebElementSelection, Error>) {
        guard let continuation = pickerContinuation else { return }
        pickerContinuation = nil
        pickerTimeoutTask?.cancel()
        pickerTimeoutTask = nil
        continuation.resume(with: result)
    }

    private func handleMetricsMessage(_ message: WKScriptMessage) {
        guard message.name == "portholeMetrics" else { return }
        applyScrollMetrics(from: message.body)
    }

    private func applyScrollMetrics(from value: Any?) {
        guard let values = try? decodeJSONObject(from: value) else {
            applyFallbackScrollMetrics()
            return
        }
        let x = loadCGFloat(from: values, key: "x") ?? 0
        let y = loadCGFloat(from: values, key: "y") ?? 0
        let width = loadCGFloat(from: values, key: "width") ?? webView.bounds.width
        let height = loadCGFloat(from: values, key: "height") ?? webView.bounds.height
        scrollOffset = CGPoint(x: x, y: y)
        documentSize = CGSize(
            width: max(webView.bounds.width, width),
            height: max(webView.bounds.height, height)
        )
    }

    private func applyFallbackScrollMetrics() {
        scrollOffset = .zero
        documentSize = webView.bounds.size
    }

    private func decodeJSONObject(from value: Any?) throws -> [String: Any]? {
        guard let string = value as? String,
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any]
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
                continuation.resume(throwing: WebClipPreviewError.timeout(operationName))
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

    private func makeClipRect(from values: [String: Any]) -> ClipRect? {
        guard let x = loadCGFloat(from: values, key: "x"),
              let y = loadCGFloat(from: values, key: "y"),
              let width = loadCGFloat(from: values, key: "width"),
              let height = loadCGFloat(from: values, key: "height") else {
            return nil
        }
        return ClipRect(x: x, y: y, width: width, height: height)
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

    private static var metricsScript: String {
        """
        (() => {
            const root = document.documentElement;
            const body = document.body;
            return JSON.stringify({
                x: window.scrollX || root.scrollLeft || 0,
                y: window.scrollY || root.scrollTop || 0,
                width: Math.max(window.innerWidth || 0, root.scrollWidth || 0, body ? body.scrollWidth : 0),
                height: Math.max(window.innerHeight || 0, root.scrollHeight || 0, body ? body.scrollHeight : 0)
            });
        })();
        """
    }

    private static func makeMetricsUserScript() -> WKUserScript {
        WKUserScript(
            source: """
            (() => {
                if (window.__portholeMetricsInstalled) return;
                window.__portholeMetricsInstalled = true;

                function reportMetrics() {
                    const root = document.documentElement;
                    const body = document.body;
                    const result = {
                        x: window.scrollX || root.scrollLeft || 0,
                        y: window.scrollY || root.scrollTop || 0,
                        width: Math.max(window.innerWidth || 0, root.scrollWidth || 0, body ? body.scrollWidth : 0),
                        height: Math.max(window.innerHeight || 0, root.scrollHeight || 0, body ? body.scrollHeight : 0)
                    };
                    window.webkit.messageHandlers.portholeMetrics.postMessage(JSON.stringify(result));
                }

                window.addEventListener("scroll", reportMetrics, { passive: true });
                window.addEventListener("resize", reportMetrics, { passive: true });
                requestAnimationFrame(reportMetrics);
                setTimeout(reportMetrics, 250);
                setTimeout(reportMetrics, 1000);
            })();
            """,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
    }
}

/// WebViewから要素選択結果を受け取るメッセージハンドラです。
private final class WebClipPickerMessageHandler: NSObject, WKScriptMessageHandler {
    private let handleMessage: @MainActor (WKScriptMessage) -> Void

    init(handleMessage: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.handleMessage = handleMessage
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            handleMessage(message)
        }
    }
}

/// WebViewからスクロール位置と本文サイズを受け取るメッセージハンドラです。
private final class WebClipMetricsMessageHandler: NSObject, WKScriptMessageHandler {
    private let handleMessage: @MainActor (WKScriptMessage) -> Void

    init(handleMessage: @escaping @MainActor (WKScriptMessage) -> Void) {
        self.handleMessage = handleMessage
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        Task { @MainActor in
            handleMessage(message)
        }
    }
}

/// SwiftUI内にWKWebViewを埋め込むRepresentableです。
struct WebClipPreview: NSViewRepresentable {
    @ObservedObject var store: WebClipPreviewStore

    func makeNSView(context: Context) -> WKWebView {
        store.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// プレビュー要素選択時のエラーです。
enum WebClipPreviewError: LocalizedError {
    case alreadyPicking
    case invalidSelection
    case timeout(String)

    var errorDescription: String? {
        switch self {
        case .alreadyPicking:
            return L10n.string("error.pickerActive")
        case .invalidSelection:
            return L10n.string("error.pickerSelectionUnreadable")
        case let .timeout(operationName):
            return L10n.format("error.timeout", operationName)
        }
    }
}
