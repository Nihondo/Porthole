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
    let refreshSeconds: TimeInterval
    let isAppGroupAvailable: Bool
    let dominantColor: ClipColor?
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
            refreshSeconds: 1800,
            isAppGroupAvailable: true,
            dominantColor: nil
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
            refreshSeconds: clip?.refreshSeconds ?? 15 * 60,
            isAppGroupAvailable: ClipStore.shared.isAppGroupAvailable,
            dominantColor: clip?.dominantColor
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
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Text(entry.clipName ?? L10n.string("widget.defaultClipName"))
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
            Label("Porthole", systemImage: "widget.large.badge.plus")
                .font(.headline)

            Spacer(minLength: 0)

            Text(entry.clipName ?? L10n.string("widget.noClip"))
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
            return L10n.string("widget.appGroupUnavailable")
        }
        if entry.snapshotURL == nil {
            let key = entry.clipCount == 1 ? "widget.clipReady.one" : "widget.clipReady.other"
            return L10n.format(key, entry.clipCount)
        }
        return L10n.string("widget.openAndCapture")
    }

    private var widgetURL: URL? {
        guard let clipId = entry.clipId else { return nil }
        return URL(string: "porthole://open-source/\(clipId.uuidString)")
    }

    private func loadSnapshotImage() -> NSImage? {
        guard let snapshotURL = entry.snapshotURL else { return nil }
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        return NSImage(contentsOf: snapshotURL)
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
                .containerBackground(for: .widget) {
                    if let color = entry.dominantColor {
                        Color(red: color.red, green: color.green, blue: color.blue)
                    } else {
                        Color(nsColor: .windowBackgroundColor)
                    }
                }
        }
        .configurationDisplayName("widget.configuration.name")
        .description("widget.configuration.description")
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
