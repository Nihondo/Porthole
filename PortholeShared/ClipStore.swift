// MARK: - ClipStore.swift
// JSON registry storage shared through the App Group container.

import Foundation

/// クリップ定義を App Group 内の registry.json に保存します。
struct ClipStore {
    static let shared = ClipStore()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let fileManager = FileManager.default

    init() {
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    /// App Group コンテナが利用できる場合に true を返します。
    var isAppGroupAvailable: Bool {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId) != nil
    }

    /// registry.json からクリップ一覧を読み込みます。
    func loadClips() throws -> [Clip] {
        guard let url = registryFileURL(createDirectory: false) else {
            throw ClipStoreError.appGroupUnavailable
        }
        guard fileManager.fileExists(atPath: url.path) else {
            return []
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode([Clip].self, from: data)
    }

    /// 指定IDに一致するクリップを読み込みます。
    func loadClip(id: UUID?) -> Clip? {
        guard let id else { return nil }
        return (try? loadClips())?.first { $0.id == id }
    }

    /// クリップ一覧を registry.json へアトミックに保存します。
    func saveClips(_ clips: [Clip]) throws {
        guard let url = registryFileURL(createDirectory: true) else {
            throw ClipStoreError.appGroupUnavailable
        }
        let data = try encoder.encode(clips)
        try data.write(to: url, options: .atomic)
    }

    /// registry.json が空のときにサンプルクリップを作成します。
    func seedSampleClipIfNeeded() throws {
        let clips = try loadClips()
        guard clips.isEmpty else { return }
        try saveClips([Clip.makeSampleClip()])
    }

    /// App Group 内の registry.json の場所を返します。
    func registryFileURL(createDirectory: Bool = false) -> URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId
        ) else { return nil }

        let directoryURL = containerURL.appendingPathComponent(
            AppGroupConfig.applicationSupportDirectory,
            isDirectory: true
        )
        if createDirectory {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }
        return directoryURL.appendingPathComponent(AppGroupConfig.registryFileName)
    }
}

/// ClipStore の永続化エラーです。
enum ClipStoreError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            return L10n.string("error.appGroupUnavailable")
        }
    }
}
