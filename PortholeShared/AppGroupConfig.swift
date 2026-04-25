// MARK: - AppGroupConfig.swift
// Shared App Group constants for the app and widget targets.

import Foundation

/// App Group と共有ファイル配置を管理する設定値です。
enum AppGroupConfig {
    static let groupId = "group.com.dmng.porthole"
    static let applicationSupportDirectory = "Library/Application Support/Porthole"
    static let registryFileName = "registry.json"
    static let faviconsDirectoryName = "favicons"
    static let snapshotsDirectoryName = "snapshots"
}

/// App Group の UserDefaults へアクセスするための共有アクセサです。
enum AppGroupDefaults {
    static var shared: UserDefaults? {
        UserDefaults(suiteName: AppGroupConfig.groupId)
    }
}

/// WidgetKit に登録する Widget kind を定義します。
enum PortholeKind {
    static let id = "com.dmng.porthole.widget.webclip"
}
