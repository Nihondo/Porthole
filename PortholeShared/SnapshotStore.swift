// MARK: - SnapshotStore.swift
// Shared snapshot paths used by future capture and widget rendering code.

import CoreGraphics
import Foundation

/// ウィジェットファミリーごとのスナップショット種別です。
enum SnapshotFamily: String, CaseIterable {
    case small
    case medium
    case large

    /// 生成するPNGの論理サイズです。
    var pointSize: CGSize {
        switch self {
        case .small:
            return CGSize(width: 158, height: 158)
        case .medium:
            return CGSize(width: 338, height: 158)
        case .large:
            return CGSize(width: 338, height: 338)
        }
    }
}

/// スナップショットPNGの保存場所を管理します。
struct SnapshotStore {
    static let shared = SnapshotStore()

    private let fileManager = FileManager.default

    /// 指定したクリップとファミリー名に対応するPNGのURLを返します。
    func snapshotURL(for clipId: UUID, familyName: String, createDirectory: Bool = false) -> URL? {
        guard let containerURL = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroupConfig.groupId
        ) else { return nil }

        let directoryURL = containerURL
            .appendingPathComponent(AppGroupConfig.applicationSupportDirectory, isDirectory: true)
            .appendingPathComponent(AppGroupConfig.snapshotsDirectoryName, isDirectory: true)

        if createDirectory {
            try? fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        }

        return directoryURL.appendingPathComponent("\(clipId.uuidString)-\(familyName).png")
    }

    /// 指定したクリップとウィジェットファミリーに対応するPNGのURLを返します。
    func snapshotURL(for clipId: UUID, family: SnapshotFamily, createDirectory: Bool = false) -> URL? {
        snapshotURL(for: clipId, familyName: family.rawValue, createDirectory: createDirectory)
    }
}
