// MARK: - RefreshScheduler.swift
// Schedules periodic snapshot refreshes while the app is running.

import Foundation

/// クリップの更新間隔に基づいて次回撮影を予約します。
actor RefreshScheduler {
    private var refreshTask: Task<Void, Never>?

    /// 現在のクリップ一覧から次回更新を予約します。
    func schedule(
        clips: [Clip],
        onDue: @escaping @MainActor @Sendable (UUID) -> Void
    ) {
        refreshTask?.cancel()
        guard let nextRefresh = Self.findNextRefresh(in: clips, at: Date()) else {
            refreshTask = nil
            return
        }

        refreshTask = Task {
            await Self.sleepUntil(nextRefresh.date)
            guard !Task.isCancelled else { return }
            await onDue(nextRefresh.clipId)
        }
    }

    /// 予約済みの更新を停止します。
    func stop() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    /// 指定クリップが現在時刻で更新期限切れかを返します。
    static func isRefreshDue(_ clip: Clip, at date: Date) -> Bool {
        guard clip.refreshSeconds > 0 else { return false }
        guard let lastUpdated = clip.lastUpdated else { return true }
        return date.timeIntervalSince(lastUpdated) >= clip.refreshSeconds
    }

    private static func findNextRefresh(in clips: [Clip], at date: Date) -> ScheduledRefresh? {
        clips
            .filter { $0.refreshSeconds > 0 }
            .map { clip in
                ScheduledRefresh(
                    clipId: clip.id,
                    date: nextRefreshDate(for: clip, at: date)
                )
            }
            .min { lhs, rhs in lhs.date < rhs.date }
    }

    private static func nextRefreshDate(for clip: Clip, at date: Date) -> Date {
        guard let lastUpdated = clip.lastUpdated else { return date }
        let nextDate = lastUpdated.addingTimeInterval(clip.refreshSeconds)
        return max(nextDate, date)
    }

    private static func sleepUntil(_ date: Date) async {
        let delay = max(0, date.timeIntervalSinceNow)
        guard delay > 0 else { return }
        let nanoseconds = min(delay, 86_400) * 1_000_000_000
        try? await Task.sleep(nanoseconds: UInt64(nanoseconds))
    }
}

private struct ScheduledRefresh {
    let clipId: UUID
    let date: Date
}
