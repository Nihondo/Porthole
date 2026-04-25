// MARK: - PortholeBundle.swift
// Widget bundle entry point.

import WidgetKit
import SwiftUI

/// Porthole のウィジェットを登録するバンドルです。
@main
struct PortholeBundle: WidgetBundle {
    var body: some Widget {
        PortholeWidget()
    }
}

