# Porthole

Porthole is a macOS menu bar app that captures a region of any web page or local HTML file and displays it as a macOS Notification Center widget.

## Quick Start

1. Launch Porthole. A sample clip is created automatically on first launch.
2. Open **Porthole Settings...** from the menu bar.
3. Select the sample clip (or add a new one with **+**).
4. Set a **Source** URL or choose a **Local HTML** file.
5. Drag the rectangle overlay in the preview to define the region to capture.
6. Click **Save Settings**, then **Refresh Clip** to take the first snapshot.
7. Add a **Web Clip** widget in Notification Center and choose your clip.

## Menu Bar

| Item | Description |
|---|---|
| **Porthole Settings...** | Open the settings window |
| **Refresh Clip** | Capture the selected clip and update widget images |
| **Open at Login** | Toggle the macOS login item |
| **About Porthole...** | Open the standard About panel |
| **Quit** | Quit the app |

## Settings Window

### Clip List (sidebar)
- **+** — Add a new clip
- **−** — Delete the selected clip
- Click a clip to select and edit it

### Basic
| Field | Description |
|---|---|
| **Name** | Display name shown in the widget picker |
| **Source** | `URL` for a remote web page, `Local HTML` for a local file |
| **URL** | Page URL (remote clips only) |
| **Refresh Interval** | How often the clip is automatically re-captured (in seconds) |

### Rendering
| Field | Description |
|---|---|
| **Viewport Width / Height** | Browser viewport size used when rendering the page |
| **Capture Delay** | Seconds to wait after the page finishes loading before taking the snapshot. Use this to skip loading placeholders on pages that render content asynchronously (default: 0) |

### Clipping
| Field | Description |
|---|---|
| **Mode** | `Rectangle` captures a fixed region; `Selector` targets a CSS element |
| **Selector** | CSS selector for the element to capture (Selector mode only) |
| **Fallback Rectangle** | Rectangle used when the selector is not found |

### Rectangle
Drag the overlay in the **Preview** pane to set the capture region, or enter **X / Y / Width / Height** values directly.

### Preview
- **Reload** — Reload the preview web view
- **Select Element** — Click any element in the preview to auto-fill the CSS selector
- **Save Settings** — Save the current clip settings
- **Refresh Clip** — Capture a new snapshot immediately

## Clipping Modes

### Rectangle
Captures the exact pixel region defined by the X / Y / Width / Height fields. Drag the rectangle in the preview to reposition it, or drag the bottom-right handle to resize.

### Selector
Captures the bounding box of the first element that matches the CSS selector. Use **Select Element** to pick an element from the preview. The rectangle is saved as a fallback for when the element is not found.

## Local HTML Files
1. Set **Source** to `Local HTML`.
2. Click **Choose HTML** to select the HTML file via the file picker.
3. Optionally set a **Read Access Root** to allow the page to load relative assets.
4. The file path is stored as a security-scoped bookmark and does not need to be re-selected after relaunching the app.

## Widgets

Add a **Web Clip** widget in Notification Center (macOS Notification Center → Edit Widgets → search "Web Clip").

- **Small / Medium / Large** sizes are all supported.
- Tap the widget configuration to choose which clip to display.
- A remote URL clip opens the source page in the default browser when clicked.
- The widget shows a placeholder when no snapshot has been captured yet.
- The snapshot fills the widget area. Wide or tall clips are center-cropped instead of padded.
- The widget background uses a representative color sampled from the snapshot edges.
- The timeline refreshes at the interval configured for the selected clip.

## Automatic Refresh

- While the app is running, each clip is re-captured at its configured **Refresh Interval**.
- Clips that have not been updated within their interval are re-captured on app launch and after the Mac wakes from sleep.
- Snapshots are not refreshed while the app is not running.

## Notes / Troubleshooting

- **Widget shows placeholder** — Open the app and use **Refresh Clip** to take the first snapshot.
- **Local HTML reference is stale** — The file has moved or the bookmark expired. Re-select the file via **Choose HTML**.
- **Selector not found** — The element was not present when the page loaded. Check the selector, or switch to Rectangle mode.
- **Widget not updating** — macOS may throttle widget refresh. Open the app to trigger a manual capture.
- **Login item requires approval** — macOS 13+ may require confirmation in System Settings → General → Login Items.
