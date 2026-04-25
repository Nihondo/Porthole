// MARK: - PortholeWidget.swift
// Widget that renders App Group snapshots created by the main app.

import AppKit
import AppIntents
import SwiftUI
import WidgetKit

/// ウィジェットに表示する最小タイムラインエントリです。
struct PortholeEntry: TimelineEntry {
    let date: Date
    let clipId: UUID?
    let clipName: String?
    let clipCount: Int
    let lastUpdated: Date?
    let snapshotURL: URL?
    let sourceURL: URL?
    let refreshSeconds: TimeInterval
    let isAppGroupAvailable: Bool
}

/// App Group の registry.json を読み込むタイムラインプロバイダです。
struct PortholeTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> PortholeEntry {
        PortholeEntry(
            date: Date(),
            clipId: Clip.makeSampleClip().id,
            clipName: "Apple Japan",
            clipCount: 1,
            lastUpdated: Date(),
            snapshotURL: nil,
            sourceURL: URL(string: "https://www.apple.com/jp/"),
            refreshSeconds: 1800,
            isAppGroupAvailable: true
        )
    }

    func snapshot(for configuration: SelectClipIntent, in context: Context) async -> PortholeEntry {
        makeEntry(configuration: configuration, family: context.family)
    }

    func timeline(for configuration: SelectClipIntent, in context: Context) async -> Timeline<PortholeEntry> {
        let entry = makeEntry(configuration: configuration, family: context.family)
        let nextUpdate = Date().addingTimeInterval(entry.refreshSeconds)
        return Timeline(entries: [entry], policy: .after(nextUpdate))
    }

    private func makeEntry(configuration: SelectClipIntent, family widgetFamily: WidgetFamily) -> PortholeEntry {
        let clips = (try? ClipStore.shared.loadClips()) ?? []
        let selectedClipId = configuration.clip.flatMap { UUID(uuidString: $0.id) }
        let clip = selectedClipId.flatMap { id in
            clips.first { $0.id == id }
        } ?? clips.first
        let snapshotFamily = SnapshotFamily(widgetFamily: widgetFamily)
        let snapshotURL = clip.flatMap {
            SnapshotStore.shared.snapshotURL(for: $0.id, family: snapshotFamily)
        }
        return PortholeEntry(
            date: Date(),
            clipId: clip?.id,
            clipName: clip?.name,
            clipCount: clips.count,
            lastUpdated: clip?.lastUpdated,
            snapshotURL: snapshotURL,
            sourceURL: clip?.remoteSourceURL,
            refreshSeconds: clip?.refreshSeconds ?? 15 * 60,
            isAppGroupAvailable: ClipStore.shared.isAppGroupAvailable
        )
    }
}

/// App Group 疎通状態を表示するウィジェットビューです。
struct PortholeWidgetView: View {
    let entry: PortholeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        contentView
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(widgetURL)
    }

    @ViewBuilder
    private var contentView: some View {
        if let image = loadSnapshotImage() {
            ZStack(alignment: .bottomLeading) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()

                Text(entry.clipName ?? "Web Clip")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        } else {
            placeholderView
        }
    }

    private var placeholderView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Porthole", systemImage: "rectangle.inset.filled")
                .font(.headline)

            Spacer(minLength: 0)

            Text(entry.clipName ?? "No Clip")
                .font(family == .systemSmall ? .subheadline : .title3)
                .fontWeight(.semibold)
                .lineLimit(2)

            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var statusText: String {
        if !entry.isAppGroupAvailable {
            return "App Group unavailable"
        }
        if entry.snapshotURL == nil {
            return "\(entry.clipCount) clip(s) ready"
        }
        return "Open the app and capture"
    }

    private var widgetURL: URL? {
        entry.sourceURL
    }

    private func loadSnapshotImage() -> NSImage? {
        guard let snapshotURL = entry.snapshotURL else { return nil }
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        return NSImage(contentsOf: snapshotURL)
    }
}

private extension Clip {
    var remoteSourceURL: URL? {
        guard case let .remote(url) = source else { return nil }
        return url
    }
}

/// Porthole の最小 Widget 定義です。
struct PortholeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: PortholeKind.id,
            intent: SelectClipIntent.self,
            provider: PortholeTimelineProvider()
        ) { entry in
            PortholeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Web Clip")
        .description("Show a clipped region of any web page.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private extension SnapshotFamily {
    init(widgetFamily: WidgetFamily) {
        switch widgetFamily {
        case .systemSmall:
            self = .small
        case .systemLarge:
            self = .large
        default:
            self = .medium
        }
    }
}
