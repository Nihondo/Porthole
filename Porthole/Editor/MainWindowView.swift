// MARK: - MainWindowView.swift
// Clip editor window for managing web clips.

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let portholeIntegerFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 0
    formatter.minimum = 0
    return formatter
}()

/// クリップ管理と App Group 疎通状態を表示する設定画面です。
struct MainWindowView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var draft = ClipEditorDraft()
    @StateObject private var faviconStore = FaviconStore()
    @StateObject private var previewStore = WebClipPreviewStore()

    private var selectedClip: Clip? {
        appState.clips.first { $0.id == appState.selectedClipId } ?? appState.clips.first
    }

    var body: some View {
        NavigationSplitView {
            clipList
        } detail: {
            editorDetail
        }
        .background(PortholeTheme.windowBackground)
        .onAppear {
            appState.loadInitialState()
            loadSelectedClip()
        }
        .onChange(of: appState.selectedClipId) { _, _ in
            loadSelectedClip()
        }
        .onChange(of: appState.clips) { _, _ in
            reloadIfSelectionDisappeared()
        }
    }

    private var clipList: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Porthole")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PortholeTheme.heading)

                Text(clipCountText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(PortholeTheme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            ScrollView {
                if appState.clips.isEmpty {
                    EmptySidebarState()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 24)
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(appState.clips) { clip in
                            ClipSidebarRow(
                                clip: clip,
                                isSelected: clip.id == appState.selectedClipId,
                                favicon: faviconStore.image(for: clip)
                            ) {
                                appState.selectedClipId = clip.id
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    appState.addClip()
                } label: {
                    Label(L10n.string("editor.add"), systemImage: "plus")
                }
                .buttonStyle(.bordered)

                Button {
                    appState.deleteSelectedClip()
                } label: {
                    Label(L10n.string("editor.delete"), systemImage: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(appState.selectedClipId == nil)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .frame(minWidth: 250)
        .background(PortholeTheme.sidebarBackground)
    }

    private var clipCountText: String {
        let key = appState.clips.count == 1 ? "editor.sidebar.count.one" : "editor.sidebar.count.other"
        return L10n.format(key, appState.clips.count)
    }

    @ViewBuilder
    private var editorDetail: some View {
        if selectedClip == nil {
            EmptyDetailView {
                appState.addClip()
            }
            .background(PortholeTheme.windowBackground)
        } else {
            VStack(spacing: 0) {
                editorToolbar

                HSplitView {
                    formPane
                        .frame(minWidth: 330, idealWidth: 380, maxWidth: 460)

                    previewPane
                        .frame(minWidth: 460)
                }
            }
            .background(PortholeTheme.windowBackground)
            .navigationTitle("")
        }
    }

    private var editorToolbar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(selectedClip?.name ?? L10n.string("editor.defaultTitle"))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(PortholeTheme.onAccent)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 7))
                    Text(appState.statusMessage)
                        .lineLimit(1)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(PortholeTheme.onAccent.opacity(0.82))
            }

            Spacer()

            Button {
                loadPreview()
            } label: {
                Label(L10n.string("editor.reload"), systemImage: "arrow.clockwise")
            }
            .buttonStyle(.portholeSecondary)

            Button {
                _ = saveDraft()
            } label: {
                Label(L10n.string("editor.saveSettings"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.portholePrimary)

            Button {
                if saveDraft() {
                    appState.captureSelectedClip()
                }
            } label: {
                Label(L10n.string("editor.refreshClip"), systemImage: "camera.viewfinder")
            }
            .buttonStyle(.portholeSecondary)
            .disabled(appState.isCapturingSnapshot)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .background(PortholeTheme.brandGradient)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(PortholeTheme.onAccent.opacity(0.22))
                .frame(height: 1)
        }
    }

    private var formPane: some View {
        ScrollView {
            VStack(spacing: 14) {
                SettingsCard(title: L10n.string("editor.section.basic"), systemImage: "slider.horizontal.3") {
                    VStack(spacing: 12) {
                        FieldRow(L10n.string("editor.field.name")) {
                            TextField(L10n.string("editor.placeholder.name"), text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                        }

                        FieldRow(L10n.string("editor.field.source")) {
                            LeftAlignedControl {
                                Picker(L10n.string("editor.field.source"), selection: $draft.sourceKind) {
                                    ForEach(EditorSourceKind.allCases) { sourceKind in
                                        Text(sourceKind.title).tag(sourceKind)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }
                        }

                        if draft.sourceKind == .remote {
                            FieldRow(L10n.string("editor.field.url")) {
                                TextField(L10n.string("editor.placeholder.url"), text: $draft.urlString)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    selectLocalHTML()
                                } label: {
                                    Label(L10n.string("editor.selectHTML"), systemImage: "doc.badge.plus")
                                }
                                .buttonStyle(.portholeSecondary)

                                PathValueRow(
                                    title: L10n.string("editor.htmlPath"),
                                    value: draft.localHTMLPath.isEmpty ? L10n.string("editor.notSelected") : draft.localHTMLPath
                                )
                                PathValueRow(
                                    title: L10n.string("editor.accessRootPath"),
                                    value: draft.localAccessRootPath.isEmpty ? L10n.string("editor.notSelected") : draft.localAccessRootPath
                                )
                            }
                        }

                        FieldRow(L10n.string("editor.field.refreshInterval")) {
                            HStack(spacing: 8) {
                                TextField(L10n.string("editor.seconds"), value: $draft.refreshSeconds, formatter: Self.integerFormatter)
                                    .textFieldStyle(.roundedBorder)
                                Text(L10n.string("editor.seconds"))
                                    .font(.caption)
                                    .foregroundStyle(PortholeTheme.muted)
                            }
                        }
                    }
                }

                SettingsCard(title: L10n.string("editor.section.rendering"), systemImage: "display") {
                    HStack(spacing: 10) {
                        MetricField(title: L10n.string("editor.field.viewportWidth"), value: $draft.viewportWidth)
                        MetricField(title: L10n.string("editor.field.viewportHeight"), value: $draft.viewportHeight)
                    }
                }

                SettingsCard(title: L10n.string("editor.section.clipping"), systemImage: "crop") {
                    VStack(spacing: 12) {
                        FieldRow(L10n.string("editor.field.mode")) {
                            LeftAlignedControl {
                                Picker(L10n.string("editor.field.mode"), selection: $draft.clipMode) {
                                    ForEach(EditorClipMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                            }
                        }

                        if draft.clipMode == .selector {
                            FieldRow(L10n.string("editor.field.selector")) {
                                TextField(L10n.string("editor.placeholder.selector"), text: $draft.selector)
                                    .textFieldStyle(.roundedBorder)
                            }
                            HStack {
                                Button {
                                    pickElement()
                                } label: {
                                    Label(L10n.string("editor.selectElement"), systemImage: "scope")
                                }
                                .buttonStyle(.portholeSecondary)
                                .disabled(previewStore.isPickingElement)

                                Spacer()

                                Text(L10n.string("editor.saveFallbackRect"))
                                    .font(.caption2)
                                    .foregroundStyle(PortholeTheme.muted)
                            }
                        }
                    }
                }

                SettingsCard(
                    title: draft.clipMode == .rect
                        ? L10n.string("editor.section.rect")
                        : L10n.string("editor.section.fallbackRect"),
                    systemImage: "rectangle.dashed"
                ) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            MetricField(title: L10n.string("editor.field.rectX"), value: $draft.clipRect.x)
                            MetricField(title: L10n.string("editor.field.rectY"), value: $draft.clipRect.y)
                        }
                        HStack(spacing: 10) {
                            MetricField(title: L10n.string("editor.field.rectWidth"), value: $draft.clipRect.width)
                            MetricField(title: L10n.string("editor.field.rectHeight"), value: $draft.clipRect.height)
                        }
                    }
                }

                if let selectedClip, let lastUpdated = selectedClip.lastUpdated {
                    SettingsCard(title: L10n.string("editor.section.status"), systemImage: "clock") {
                        PathValueRow(
                            title: L10n.string("editor.field.lastCaptured"),
                            value: lastUpdated.formatted(date: .abbreviated, time: .standard)
                        )
                    }
                }

                if let validationMessage = draft.validationMessage {
                    ValidationBanner(message: validationMessage)
                }
            }
            .padding(16)
        }
        .background(PortholeTheme.windowBackground)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.string("editor.preview"))
                        .font(.headline)
                        .foregroundStyle(PortholeTheme.heading)
                    Text("\(Int(viewportSize.width)) × \(Int(viewportSize.height))")
                        .font(.caption)
                        .foregroundStyle(PortholeTheme.muted)
                }

                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    WebClipPreview(store: previewStore)
                        .frame(width: viewportSize.width, height: viewportSize.height)

                    if draft.clipMode == .rect {
                        ClipRectOverlayView(clipRect: $draft.clipRect, viewportSize: viewportSize)
                            .allowsHitTesting(true)
                    } else {
                        selectorOverlay
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: viewportSize.width, height: viewportSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(PortholeTheme.border, lineWidth: 1)
                }
                .shadow(color: PortholeTheme.shadow, radius: 18, y: 8)
                .padding(18)
            }
            .background(PortholeTheme.previewBackground)
        }
        .background(PortholeTheme.previewBackground)
    }

    private var selectorOverlay: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(previewStore.isPickingElement ? PortholeTheme.warning : PortholeTheme.accent, lineWidth: 2)
                .background((previewStore.isPickingElement ? PortholeTheme.warning : PortholeTheme.accent).opacity(0.12))
                .frame(width: draft.clipRect.width, height: draft.clipRect.height)
                .position(
                    x: draft.clipRect.x + draft.clipRect.width / 2,
                    y: draft.clipRect.y + draft.clipRect.height / 2
                )

            if previewStore.isPickingElement {
                Text(L10n.string("editor.clickToSelect"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(PortholeTheme.warning.opacity(0.9))
                    .foregroundStyle(PortholeTheme.onAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .position(x: draft.clipRect.x + 58, y: max(14, draft.clipRect.y - 12))
            }
        }
        .frame(width: viewportSize.width, height: viewportSize.height, alignment: .topLeading)
    }

    private var viewportSize: CGSize {
        CGSize(
            width: max(320, draft.viewportWidth),
            height: max(240, draft.viewportHeight)
        )
    }

    private func loadSelectedClip() {
        draft.load(from: selectedClip)
        loadPreview()
    }

    private func reloadIfSelectionDisappeared() {
        guard let selectedClipId = appState.selectedClipId else {
            loadSelectedClip()
            return
        }
        guard appState.clips.contains(where: { $0.id == selectedClipId }) else {
            loadSelectedClip()
            return
        }
    }

    private func loadPreview() {
        do {
            try previewStore.load(draft.previewSource)
            draft.validationMessage = nil
        } catch {
            draft.validationMessage = error.localizedDescription
        }
    }

    private func saveDraft() -> Bool {
        guard let clip = draft.makeClip() else { return false }
        return appState.saveClip(clip)
    }

    private func pickElement() {
        Task {
            do {
                let selection = try await previewStore.pickElement()
                draft.selector = selection.selector
                draft.clipRect = selection.rect
                draft.clipMode = .selector
                draft.validationMessage = nil
            } catch {
                draft.validationMessage = error.localizedDescription
            }
        }
    }

    private func selectLocalHTML() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.html]
        panel.message = L10n.string("editor.localHTMLPanel.message")
        panel.prompt = L10n.string("editor.localHTMLPanel.prompt")

        guard panel.runModal() == .OK, let htmlURL = panel.url else { return }

        let accessRootURL = htmlURL.deletingLastPathComponent()
        do {
            let htmlBookmark = try LocalHTMLSourceResolver.makeBookmark(for: htmlURL)
            let accessRoot = makeAccessRootBookmark(
                accessRootURL: accessRootURL,
                htmlURL: htmlURL,
                fallbackBookmark: htmlBookmark
            )
            draft.setLocalHTML(
                htmlURL: htmlURL,
                accessRootURL: accessRoot.url,
                htmlBookmark: htmlBookmark,
                accessRootBookmark: accessRoot.bookmark
            )
            draft.validationMessage = nil
            loadPreview()
        } catch {
            draft.validationMessage = error.localizedDescription
        }
    }

    private func makeAccessRootBookmark(
        accessRootURL: URL,
        htmlURL: URL,
        fallbackBookmark: Data
    ) -> (url: URL, bookmark: Data) {
        do {
            return (accessRootURL, try LocalHTMLSourceResolver.makeBookmark(for: accessRootURL))
        } catch {
            return (htmlURL, fallbackBookmark)
        }
    }

    private static let integerFormatter: NumberFormatter = {
        portholeIntegerFormatter
    }()
}

private enum PortholeTheme {
    static let accent = Color(nsColor: .controlAccentColor)
    static let accentStrong = Color(nsColor: .selectedContentBackgroundColor)
    static let onAccent = Color(nsColor: .selectedTextColor)
    static let heading = Color(nsColor: .labelColor)
    static let body = Color(nsColor: .labelColor)
    static let muted = Color(nsColor: .secondaryLabelColor)
    static let border = Color(nsColor: .separatorColor)
    static let sidebarBackground = Color(nsColor: .underPageBackgroundColor)
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let cardBackground = Color(nsColor: .controlBackgroundColor)
    static let previewBackground = Color(nsColor: .textBackgroundColor)
    static let warning = Color(nsColor: .systemOrange)
    static let error = Color(nsColor: .systemRed)
    static let shadow = Color(nsColor: .shadowColor).opacity(0.18)

    static let brandGradient = LinearGradient(
        colors: [accent, accentStrong],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

private struct ClipSidebarRow: View {
    let clip: Clip
    let isSelected: Bool
    let favicon: NSImage?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? PortholeTheme.brandGradient : LinearGradient(
                            colors: [PortholeTheme.cardBackground, PortholeTheme.sidebarBackground],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                    if let favicon {
                        Image(nsImage: favicon)
                            .resizable()
                            .interpolation(.high)
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        Image(systemName: clip.sourceSystemImage)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(isSelected ? PortholeTheme.onAccent : PortholeTheme.accent)
                    }
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PortholeTheme.heading)
                        .lineLimit(1)
                    Text(clip.remoteURLLabel)
                        .font(.caption2)
                        .foregroundStyle(PortholeTheme.muted)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? PortholeTheme.cardBackground : Color.clear)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? PortholeTheme.border : .clear, lineWidth: 1)
            }
            .shadow(color: isSelected ? PortholeTheme.shadow : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

private struct EmptySidebarState: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PortholeTheme.accent)
            Text(L10n.string("editor.sidebar.empty.title"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PortholeTheme.heading)
            Text(L10n.string("editor.sidebar.empty.message"))
                .font(.caption)
                .foregroundStyle(PortholeTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(PortholeTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(PortholeTheme.border, lineWidth: 1)
        }
    }
}

private struct EmptyDetailView: View {
    let addAction: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "widget.large.badge.plus")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(PortholeTheme.accent)
            Text(L10n.string("editor.emptyDetail.title"))
                .font(.title3.weight(.semibold))
                .foregroundStyle(PortholeTheme.heading)
            Text(L10n.string("editor.emptyDetail.message"))
                .font(.callout)
                .foregroundStyle(PortholeTheme.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button {
                addAction()
            } label: {
                Label(L10n.string("editor.add"), systemImage: "plus")
            }
            .buttonStyle(.portholePrimary)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PortholeTheme.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(PortholeTheme.heading)
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortholeTheme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 12)
                .trim(from: 0, to: 0.5)
                .stroke(PortholeTheme.brandGradient, lineWidth: 3)
                .frame(height: 3)
                .clipped()
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(PortholeTheme.border, lineWidth: 1)
        }
        .shadow(color: PortholeTheme.shadow, radius: 10, y: 3)
    }
}

private struct FieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(PortholeTheme.muted)
            content
        }
    }
}

private struct LeftAlignedControl<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            content
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct MetricField<Value>: View {
    let title: String
    @Binding var value: Value

    var body: some View {
        FieldRow(title) {
            TextField(title, value: $value, formatter: portholeIntegerFormatter)
                .textFieldStyle(.roundedBorder)
        }
    }
}

private struct PathValueRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PortholeTheme.muted)
            Text(value)
                .font(.caption)
                .foregroundStyle(PortholeTheme.body)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(PortholeTheme.sidebarBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

private struct ValidationBanner: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(PortholeTheme.error)
            Text(message)
                .font(.caption)
                .foregroundStyle(PortholeTheme.heading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PortholeTheme.error.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(PortholeTheme.error.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct PortholePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PortholeTheme.onAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(PortholeTheme.brandGradient.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: PortholeTheme.shadow.opacity(configuration.isPressed ? 0.5 : 1), radius: 8, y: 3)
    }
}

private struct PortholeSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(PortholeTheme.heading)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(PortholeTheme.cardBackground.opacity(configuration.isPressed ? 0.72 : 0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PortholeTheme.border, lineWidth: 1)
            }
    }
}

private extension ButtonStyle where Self == PortholePrimaryButtonStyle {
    static var portholePrimary: PortholePrimaryButtonStyle { PortholePrimaryButtonStyle() }
}

private extension ButtonStyle where Self == PortholeSecondaryButtonStyle {
    static var portholeSecondary: PortholeSecondaryButtonStyle { PortholeSecondaryButtonStyle() }
}

private extension Clip {
    var remoteURLLabel: String {
        switch source {
        case let .remote(url):
            return url.absoluteString
        case let .localBookmark(htmlBookmark, accessRootBookmark):
            guard let resolved = try? LocalHTMLSourceResolver.resolve(
                htmlBookmark: htmlBookmark,
                accessRootBookmark: accessRootBookmark
            ) else {
                return L10n.string("editor.localHTML.label")
            }
            return resolved.htmlURL.lastPathComponent
        }
    }

    var sourceSystemImage: String {
        switch source {
        case .remote:
            return "globe"
        case .localBookmark:
            return "doc.text"
        }
    }
}
