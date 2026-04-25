# Porthole

Porthole is a macOS menu bar app that captures part of any web page or local HTML file and displays it in a macOS widget.

## Current State

Porthole is at the M9 localization and polish stage.

- App target, shared Swift files, and Widget extension are set up.
- App Group: `group.com.dmng.porthole`
- Bundle ID: `com.dmng.porthole.Porthole` / `com.dmng.porthole.Porthole.PortholeWidget`
- The app creates a sample clip on first launch.
- The settings window supports adding, deleting, selecting, editing, and saving clips.
- Editable settings include name, source, viewport, refresh interval, clipping mode, rectangle, and CSS selector.
- Sources can be remote URLs or local HTML files.
- Local HTML files are selected through `NSOpenPanel` and stored as security-scoped bookmarks.
- The embedded `WKWebView` preview supports draggable rectangle clipping and click-to-select CSS selector capture.
- Use **Refresh Clip** from the menu or settings window to capture the selected remote URL / local HTML clip with `WKWebView`.
- The app writes small / medium / large PNG snapshots into the App Group `snapshots/` directory.
- While the app is running, clips refresh on their configured `refreshSeconds` interval.
- Stale clips are refreshed on app launch and after system wake.
- Widgets can choose the clip to display in the widget edit UI.
- The widget displays a PNG snapshot when available and a localized placeholder when not yet captured.
- The widget timeline policy follows the selected clip refresh interval.
- Clicking a remote URL clip widget opens the source URL in the default browser.
- The menu can toggle whether Porthole opens at login.
- User-facing app and widget strings are localized in English and Japanese.

## Menu

- **Porthole Settings...** opens the settings window.
- **Refresh Clip** captures the currently selected saved clip and updates the widget PNGs.
- **Open at Login** toggles the macOS login item.
- **About Porthole...** opens the standard About panel.
- **Quit** terminates the app.

## Build

Use a writable DerivedData path for local verification:

```sh
rtk xcodebuild -project Porthole.xcodeproj -scheme Porthole -destination 'platform=macOS' -derivedDataPath /tmp/PortholeDerived CODE_SIGNING_ALLOWED=NO build
```

For signed local runs with App Group support, create `Configurations/DevelopmentTeam.local.xcconfig` and set your Apple Developer Team ID:

```xcconfig
DEVELOPMENT_TEAM = <YOUR_TEAM_ID>
```

## Limitations

WidgetKit cannot host `WKWebView` inside a widget. Porthole therefore captures PNG snapshots in the main app and the widget renders those images. Snapshots are not refreshed while the main app is not running.

Widget button actions and simulated interactions were removed after M8 to keep the feature set focused. Remote URL widgets open the source URL in the default browser when clicked.
