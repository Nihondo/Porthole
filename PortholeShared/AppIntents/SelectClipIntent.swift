// MARK: - SelectClipIntent.swift
// Widget configuration intent for choosing a Porthole clip.

import AppIntents
import Foundation

/// Widget編集画面で選択できるクリップのAppEntityです。
struct ClipEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "intent.clipEntity.type")
    static var defaultQuery = ClipEntityQuery()

    let id: String
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    /// ClipモデルからEntityを作成します。
    init(clip: Clip) {
        id = clip.id.uuidString
        name = clip.name
    }

    /// IDと名前を指定してEntityを作成します。
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// App Group内のregistry.jsonからWidget候補を返すクエリです。
struct ClipEntityQuery: EntityQuery {
    /// 指定IDに対応するクリップ候補を返します。
    func entities(for identifiers: [ClipEntity.ID]) async throws -> [ClipEntity] {
        let identifierSet = Set(identifiers)
        return loadClipEntities().filter { identifierSet.contains($0.id) }
    }

    /// Widget編集画面に表示する推奨候補を返します。
    func suggestedEntities() async throws -> [ClipEntity] {
        loadClipEntities()
    }

    /// 初期選択に使うクリップを返します。
    func defaultResult() async -> ClipEntity? {
        loadClipEntities().first
    }

    private func loadClipEntities() -> [ClipEntity] {
        let clips = (try? ClipStore.shared.loadClips()) ?? []
        return clips.map(ClipEntity.init(clip:))
    }
}

/// Porthole Widgetで表示対象クリップを選ぶ設定Intentです。
struct SelectClipIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "intent.selectClip.title"
    static var description = IntentDescription("intent.selectClip.description")

    @Parameter(title: "intent.clip.parameter")
    var clip: ClipEntity?

    init() {}

    init(clip: ClipEntity?) {
        self.clip = clip
    }
}
