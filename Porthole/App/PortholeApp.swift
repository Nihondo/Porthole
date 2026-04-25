// MARK: - PortholeApp.swift
// Main application entry point for the Porthole menu bar app.

import AppKit
import SwiftUI
import WidgetKit

private enum WindowId {
    static let settings = "settings"
}

/// porthole:// のディープリンクを処理します。
enum URLRouter {
    /// URLを解析し、対応する画面を開きます。
    @MainActor
    static func handleURL(_ url: URL) {
        guard url.scheme == "porthole" else { return }

        switch url.host {
        case "open":
            let clipId = url.pathComponents.dropFirst().first ?? ""
            NSApp.activate(ignoringOtherApps: true)
            AppState.shared.selectedClipId = UUID(uuidString: clipId)
            AppState.shared.isSettingsWindowRequested = true
        default:
            break
        }
    }
}

/// アプリ全体で共有する軽量状態です。
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var clips: [Clip] = []
    @Published var selectedClipId: UUID?
    @Published var statusMessage = "起動中"
    @Published var isSettingsWindowRequested = false
    @Published var isCapturingSnapshot = false

    private let snapshotCapturer = SnapshotCapturer()
    private let refreshScheduler = RefreshScheduler()
    private var captureTask: Task<Void, Never>?
    private var captureID: UUID?
    private var staleRefreshTask: Task<Void, Never>?

    private init() {}

    /// App Group の初期化とサンプルクリップ作成を行います。
    func loadInitialState() {
        do {
            try ClipStore.shared.seedSampleClipIfNeeded()
            clips = try ClipStore.shared.loadClips()
            selectedClipId = selectedClipId ?? clips.first?.id
            statusMessage = ClipStore.shared.isAppGroupAvailable ? "App Group 接続済み" : "App Group 未接続"
            configureRefreshScheduler()
            refreshStaleClips(reason: .launch)
        } catch {
            statusMessage = "初期化エラー: \(error.localizedDescription)"
        }
    }

    /// 選択中のクリップを撮影し、Widget用PNGを更新します。
    func captureSelectedClip() {
        guard !isCapturingSnapshot else { return }
        guard let clip = clips.first(where: { $0.id == selectedClipId }) ?? clips.first else {
            statusMessage = "撮影対象のクリップがありません"
            return
        }

        captureClip(clip, reason: .manual)
    }

    /// システム復帰後に期限切れクリップを再撮影します。
    func refreshAfterSystemWake() {
        refreshStaleClips(reason: .wake)
    }

    private func captureClip(_ clip: Clip, reason: CaptureReason) {
        guard !isCapturingSnapshot else { return }
        isCapturingSnapshot = true
        statusMessage = "\(reason.capturingMessage): \(clip.name)"

        captureTask?.cancel()
        let currentCaptureID = UUID()
        captureID = currentCaptureID
        captureTask = Task {
            defer {
                if captureID == currentCaptureID {
                    isCapturingSnapshot = false
                    captureTask = nil
                    captureID = nil
                    configureRefreshScheduler()
                }
            }
            do {
                let updatedClip = try await snapshotCapturer.captureClip(clip)
                guard !Task.isCancelled else { return }
                updateClip(updatedClip)
                try ClipStore.shared.saveClips(clips)
                statusMessage = "\(reason.completedMessage): \(updatedClip.name)"
            } catch {
                guard !Task.isCancelled else { return }
                statusMessage = "\(reason.errorMessage): \(error.localizedDescription)"
                // refreshSeconds 後まで再試行しないよう lastUpdated を更新する
                var failedClip = clip
                failedClip.lastUpdated = Date()
                updateClip(failedClip)
                try? ClipStore.shared.saveClips(clips)
            }
        }

        Task {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            guard captureID == currentCaptureID else { return }
            captureTask?.cancel()
            snapshotCapturer.cancelCapture()
            statusMessage = "撮影エラー: Timed out while waiting for capture."
            isCapturingSnapshot = false
            captureTask = nil
            captureID = nil
            configureRefreshScheduler()
        }
    }

    /// 新規クリップを作成して選択します。
    func addClip() {
        var clip = Clip.makeNewRemoteClip(index: clips.count + 1)
        clip.name = makeUniqueClipName(baseName: clip.name)
        clips.append(clip)
        selectedClipId = clip.id
        _ = saveClips()
    }

    /// 選択中のクリップを削除します。
    func deleteSelectedClip() {
        guard let selectedClipId else { return }
        clips.removeAll { $0.id == selectedClipId }
        self.selectedClipId = clips.first?.id
        _ = saveClips()
    }

    /// 編集済みクリップを保存します。
    @discardableResult
    func saveClip(_ clip: Clip) -> Bool {
        if clips.contains(where: { $0.id == clip.id }) {
            updateClip(clip)
        } else {
            clips.append(clip)
        }
        selectedClipId = clip.id
        return saveClips()
    }

    @discardableResult
    private func saveClips() -> Bool {
        do {
            try ClipStore.shared.saveClips(clips)
            WidgetCenter.shared.reloadTimelines(ofKind: PortholeKind.id)
            configureRefreshScheduler()
            statusMessage = "保存しました"
            return true
        } catch {
            statusMessage = "保存エラー: \(error.localizedDescription)"
            return false
        }
    }

    private func refreshStaleClips(reason: CaptureReason) {
        guard staleRefreshTask == nil else { return }
        let refreshDate = Date()
        let staleClipIds = clips
            .filter { RefreshScheduler.isRefreshDue($0, at: refreshDate) }
            .map(\.id)
        guard !staleClipIds.isEmpty else {
            configureRefreshScheduler()
            return
        }

        staleRefreshTask = Task {
            defer {
                staleRefreshTask = nil
                configureRefreshScheduler()
            }

            for clipId in staleClipIds {
                guard !Task.isCancelled else { return }
                await waitUntilCaptureIsAvailable()
                guard let clip = clips.first(where: { $0.id == clipId }) else { continue }
                captureClip(clip, reason: reason)
                await waitUntilCaptureIsAvailable()
            }
        }
    }

    private func waitUntilCaptureIsAvailable() async {
        while isCapturingSnapshot {
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    private func configureRefreshScheduler() {
        let currentClips = clips
        Task {
            await refreshScheduler.schedule(clips: currentClips) { [weak self] clipId in
                self?.captureScheduledClip(id: clipId)
            }
        }
    }

    private func captureScheduledClip(id clipId: UUID) {
        guard !isCapturingSnapshot else {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                captureScheduledClip(id: clipId)
            }
            return
        }
        guard let clip = clips.first(where: { $0.id == clipId }) else {
            configureRefreshScheduler()
            return
        }
        captureClip(clip, reason: .scheduled)
    }

    private func updateClip(_ updatedClip: Clip) {
        guard let index = clips.firstIndex(where: { $0.id == updatedClip.id }) else { return }
        clips[index] = updatedClip
    }

    private func makeUniqueClipName(baseName: String) -> String {
        let existingNames = Set(clips.map(\.name))
        guard existingNames.contains(baseName) else { return baseName }

        for index in 2...999 {
            let candidate = "\(baseName) \(index)"
            if !existingNames.contains(candidate) {
                return candidate
            }
        }
        return "\(baseName) \(UUID().uuidString.prefix(4))"
    }
}

private enum CaptureReason {
    case launch
    case manual
    case scheduled
    case wake

    var capturingMessage: String {
        switch self {
        case .launch:
            return "起動時更新中"
        case .manual:
            return "撮影中"
        case .scheduled:
            return "定期更新中"
        case .wake:
            return "復帰後更新中"
        }
    }

    var completedMessage: String {
        switch self {
        case .launch:
            return "起動時更新完了"
        case .manual:
            return "撮影完了"
        case .scheduled:
            return "定期更新完了"
        case .wake:
            return "復帰後更新完了"
        }
    }

    var errorMessage: String {
        switch self {
        case .launch:
            return "起動時更新エラー"
        case .manual:
            return "撮影エラー"
        case .scheduled:
            return "定期更新エラー"
        case .wake:
            return "復帰後更新エラー"
        }
    }
}

/// AppKit の起動処理とURLイベントを受け取るデリゲートです。
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppState.shared.refreshAfterSystemWake()
            }
        }
        Task { @MainActor in
            AppState.shared.loadInitialState()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            urls.forEach { URLRouter.handleURL($0) }
        }
    }
}

/// Porthole のメニューバー常駐アプリです。
@main
struct PortholeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(appState)
        } label: {
            Label("Porthole", systemImage: "widget.large.badge.plus")
        }
        .menuBarExtraStyle(.menu)

        Window("Porthole", id: WindowId.settings) {
            MainWindowView()
                .environmentObject(appState)
                .frame(minWidth: 760, minHeight: 460)
                .onAppear {
                    appState.isSettingsWindowRequested = false
                }
        }
        .commandsRemoved()
        .handlesExternalEvents(matching: [])
    }
}

private struct MenuBarContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject private var loginItemManager = LoginItemManager.shared

    var body: some View {
        Button {
            openWindow(id: WindowId.settings)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Porthole 設定...", systemImage: "gearshape")
        }
        Button {
            appState.captureSelectedClip()
        } label: {
            Label("クリップを最新化", systemImage: "arrow.clockwise")
        }
        .disabled(appState.isCapturingSnapshot)
        Divider()
        Toggle(
            "ログイン時にアプリを起動",
            isOn: Binding(
                get: { loginItemManager.isEnabled },
                set: { loginItemManager.setEnabled($0) }
            )
        )
        Divider()
        Button {
            presentAboutPanel()
        } label: {
            Label("Porthole について...", systemImage: "info.circle")
        }
        Divider()
        Button {
            NSApp.terminate(nil)
        } label: {
            Label("終了", systemImage: "power")
        }
        .onAppear {
            loginItemManager.updateStatus()
        }
        .onChange(of: appState.isSettingsWindowRequested) { _, isRequested in
            guard isRequested else { return }
            openWindow(id: WindowId.settings)
        }
    }

    private func presentAboutPanel() {
        let options: [NSApplication.AboutPanelOptionKey: Any] = [
            .credits: makeAboutCredits()
        ]
        NSApp.orderFrontStandardAboutPanel(options: options)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeAboutCredits() -> NSAttributedString {
        let copyright = resolveAboutCopyright()
        let websiteURLString = "https://products.desireforwealth.com/products/porthole"
        let creditsText = "\(copyright)\nWebsite: \(websiteURLString)"
        let attributed = NSMutableAttributedString(string: creditsText)
        let linkRange = (creditsText as NSString).range(of: websiteURLString)
        attributed.addAttribute(.link, value: websiteURLString, range: linkRange)
        return attributed
    }

    private func resolveAboutCopyright() -> String {
        if let value = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
           !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return value
        }
        return "Copyright © 2026 Nihondo"
    }
}
