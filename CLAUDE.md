# Porthole Development Notes

Porthole is a macOS menu bar app that captures web clip snapshots in the main app and displays them through a WidgetKit extension.

## Current State

The project is after M8 action removal:

- `Porthole` app target
- `PortholeShared` shared Swift files compiled into app and widget targets
- `PortholeWidgetExtension` widget target
- App Group: `group.com.dmng.porthole`
- URL scheme: `porthole://`
- The app seeds a sample remote clip on first launch.
- The settings window supports adding, deleting, selecting, editing, and saving multiple clips.
- Editable fields include name, source, render viewport, refresh interval, rectangular clip coordinates, and CSS selector.
- Sources can be remote URLs or local HTML files selected through `NSOpenPanel`.
- Local HTML clips store security-scoped bookmarks for the HTML file and read-access root.
- The editor embeds a `WKWebView` preview with a draggable/resizable rectangle overlay and a click-to-select element picker.
- Selector clips are saved as `.selectorWithFallbackRect`, preserving the current rectangle as fallback.
- The settings window and menu bar include "Capture Now".
- `SnapshotCapturer` loads remote clips with `URLRequest` and local HTML clips with `WKWebView.loadFileURL(_:allowingReadAccessTo:)`, captures the configured rect, writes small / medium / large PNGs, updates `lastUpdated`, and reloads widget timelines.
- `RefreshScheduler` schedules the next due clip from `lastUpdated + refreshSeconds` while the app is running.
- The app captures stale clips on launch and after `NSWorkspace.didWakeNotification`.
- `SelectClipIntent` and `ClipEntity` expose `ClipStore` clips to WidgetKit configuration.
- The widget uses `AppIntentConfiguration`, renders the selected clip's family-specific PNG, and falls back to the first clip when no selection is configured.
- The widget timeline policy uses the selected clip's `refreshSeconds`.
- The widget click URL is the remote clip's source URL, so clicking a remote clip opens it in the default browser.
- Widget button actions and App Intent request queues were removed because they made the feature too complex.

## Build

Use a writable DerivedData path when building from sandboxed agents:

```sh
rtk xcodebuild -project Porthole.xcodeproj -scheme Porthole -destination 'platform=macOS' -derivedDataPath /tmp/PortholeDerived CODE_SIGNING_ALLOWED=NO build
```

For signed local runs, create `Configurations/DevelopmentTeam.local.xcconfig` with:

```xcconfig
DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
```

## Next Milestone

M9 should add localization and polish:

- Fill in Japanese/English localization coverage.
- Improve empty states and error messages.
- Review README and user-facing behavior for the first usable release.
