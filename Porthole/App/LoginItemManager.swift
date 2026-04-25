// MARK: - LoginItemManager.swift
// Manages app registration as a login item.

import Combine
import Foundation
import ServiceManagement

/// ログイン時にアプリを起動する設定を管理します。
@MainActor
final class LoginItemManager: ObservableObject {
    static let shared = LoginItemManager()

    @Published private(set) var isEnabled = false
    @Published private(set) var statusMessage: String?

    private init() {
        updateStatus()
    }

    /// 現在のログイン項目登録状態を読み直します。
    func updateStatus() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        statusMessage = makeStatusMessage(for: status)
    }

    /// ログイン項目への登録状態を切り替えます。
    func setEnabled(_ isEnabled: Bool) {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            updateStatus()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func makeStatusMessage(for status: SMAppService.Status) -> String? {
        switch status {
        case .notRegistered, .enabled:
            return nil
        case .requiresApproval:
            return L10n.string("login.requiresApproval")
        case .notFound:
            return L10n.string("login.notFound")
        @unknown default:
            return nil
        }
    }
}
