// MARK: - Localization.swift
// Shared localization helpers for app and widget targets.

import Foundation

/// アプリ本体とWidgetで共通利用するローカライズ文字列アクセサです。
enum L10n {
    /// 指定キーに対応する現在ロケールの文字列を返します。
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .main, comment: "")
    }

    /// 指定キーの書式文字列へ値を埋め込んだ文字列を返します。
    static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: string(key), locale: Locale.current, arguments: arguments)
    }
}
