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
final class WebClipPreviewStore: ObservableObject {
    let webView: WKWebView
    @Published var loadedURL: URL?
    @Published var isPickingElement = false

    private var loadedSourceIdentifier: String?
    private var activeLocalAccess: LocalHTMLAccess?
    private var pickerContinuation: CheckedContinuation<WebElementSelection, Error>?
    private var pickerTimeoutTask: Task<Void, Never>?
    private var pickerMessageHandler: WebClipPickerMessageHandler?
    private let schemeHandler: LocalHTMLSchemeHandler

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let handler = LocalHTMLSchemeHandler()
        configuration.setURLSchemeHandler(handler, forURLScheme: LocalHTMLSchemeHandler.scheme)
        schemeHandler = handler

        webView = WKWebView(frame: .zero, configuration: configuration)
        let pickerHandler = WebClipPickerMessageHandler { [weak self] message in
            self?.handlePickerMessage(message)
        }
        pickerMessageHandler = pickerHandler
        configuration.userContentController.add(pickerHandler, name: "portholePicker")
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
        case let .localBookmark(htmlBookmark, accessRootBookmark):
            let access = try LocalHTMLSourceResolver.startAccessing(
                htmlBookmark: htmlBookmark,
                accessRootBookmark: accessRootBookmark
            )
            let identifier = "local:\(access.source.htmlURL.path):\(access.source.accessRootURL.path)"
            if loadedSourceIdentifier == identifier {
                access.stopAccessing()
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
        }
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
                        x: Math.max(0, rect.x),
                        y: Math.max(0, rect.y),
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
            return "Element picker is already active."
        case .invalidSelection:
            return "Could not read the selected element."
        case let .timeout(operationName):
            return "Timed out while waiting for \(operationName)."
        }
    }
}
