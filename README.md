# ClipFlow

A native macOS clipboard manager. Swift 6 with complete strict concurrency, SwiftUI + AppKit, SwiftData. Fully local — nothing leaves the Mac, and the app has zero third-party dependencies.

Requires macOS 14+ and Xcode 16+.

## Overview

macOS keeps exactly one clipboard entry, so anything you copy over is gone. ClipFlow keeps a searchable history and puts it one keystroke away (`⌘⇧V`), while treating clipboard contents as sensitive data rather than as a convenience cache.

Three constraints shaped the design:

- **Privacy is structural, not a setting.** History never leaves the machine, the storage directory is created with `0700` permissions and flagged `isExcludedFromBackup` so it reaches neither Time Machine nor iCloud, and content marked concealed or transient by other applications is never captured at all.
- **A background agent must be cheap.** The app lives in the menu bar with no Dock presence (`LSUIElement`) and must not cost measurable battery while idle.
- **Keyboard-first.** The common path — open, find, paste — should never need the mouse.

## Technical Approach

**Change detection.** macOS provides no clipboard notification, so detection means polling `NSPasteboard.general.changeCount`. That check is a cheap IPC call that does not read the payload, and the poll rate adapts: 0.25 s during the 15 s after a change, 1.0 s when idle. Data is read only once the counter actually moves.

**Concurrency.** The project builds with `SWIFT_STRICT_CONCURRENCY = complete` under Swift 6, so cross-actor data races are a compile-time error rather than a runtime surprise. Clipboard snapshots cross actor boundaries as `ClipboardCapture`, a `Sendable` value type, and file-backed image storage is isolated inside an `actor`.

**Storage split.** SwiftData holds metadata only; full-size images live on disk with thumbnails generated through ImageIO, which produces previews without fully decoding the source image. Files are deleted alongside their records, and on launch the app reconciles storage against the database to remove orphans left by an unclean shutdown.

**Entry point.** The app starts from `NSApplication` in `main.swift` rather than from a SwiftUI `App`, because a menu-bar agent needs `NSPanel` behaviour and activation-policy control that the SwiftUI lifecycle does not expose.

## Technologies

Swift 6 · SwiftUI · AppKit · SwiftData · Swift Concurrency (actors, strict checking) · ImageIO · Carbon `RegisterEventHotKey` · `SMAppService` · App Sandbox

No package dependencies.

## Architecture

```
Sources/
├── App/                       entry point and composition root
│   ├── main.swift                 NSApplication rather than SwiftUI App
│   ├── AppDelegate.swift          lifecycle, fatal-error UI
│   └── AppEnvironment.swift       dependency injection, settings reactions
├── Models/
│   ├── ClipboardItem.swift        @Model — metadata only
│   ├── ClipboardCapture.swift     Sendable snapshot value type
│   └── Settings.swift             SettingsStore and setting types
├── Services/
│   ├── PasteboardReader.swift     NSPasteboard reads; all privacy policy lives here
│   ├── ClipboardMonitor.swift     adaptive changeCount polling
│   ├── ClipboardStore.swift       SwiftData persistence, deduplication, limits
│   ├── ImageStorage.swift         actor owning image files
│   ├── ThumbnailService.swift     ImageIO previews without full decode
│   ├── SearchService.swift        indexing and ranked search
│   ├── RetentionService.swift     auto-cleanup scheduler
│   ├── HotKeyManager.swift        global hotkey registration
│   ├── PasteWriter.swift          clipboard writes, "Copy as…", auto-paste
│   └── LaunchAtLogin.swift        SMAppService
├── ViewModels/
├── UI/
│   ├── Panel/                     NSPanel with keyboard interception
│   ├── Settings/                  four tabs and the settings window
│   ├── MenuBar/                   NSStatusItem
│   └── Components/                preview cache, shortcut recorder
└── Support/                       logging, paths, hashing, classification, key codes
```

Data lives in `~/Library/Application Support/ClipFlow/` (inside the sandbox container): `ClipFlow.store` for metadata, `Images/` for full-size media, `Thumbnails/` for previews capped at 320 px.

## How to Run

The repository ships sources without an `.xcodeproj`, since there is little value in version-controlling a generated project file. Building takes about five minutes:

1. Xcode → **File → New → Project → macOS → App**. Product Name `ClipFlow`, Interface **SwiftUI**, Language **Swift**, Storage **None**, Testing System **None**.
2. Delete the generated `ClipFlowApp.swift` and `ContentView.swift`.
3. Drag the `Sources` folder into the project (**Copy items if needed**, **Create groups**).
4. Replace the generated `Info.plist` with `Resources/Info.plist`, or copy its keys across — `LSUIElement = YES` is the one that matters. Attach `Resources/ClipFlow.entitlements` under **Signing & Capabilities → App Sandbox**.
5. Build Settings:
   - `SWIFT_VERSION` = 6.0, `SWIFT_STRICT_CONCURRENCY` = complete
   - `MACOSX_DEPLOYMENT_TARGET` = 14.0
   - `GENERATE_INFOPLIST_FILE` = NO
6. ⌘R. The icon appears in the menu bar; there is no Dock entry.

Launch-at-login via `SMAppService` needs a signed build — in an unsigned debug build the toggle reverting to off is expected.

## Keyboard

| Keys | Action |
|---|---|
| ⌘⇧V | open / close history (configurable) |
| ↑ / ↓ | navigate; ⌘↑ / ⌘↓ jump to start / end |
| ↩ | copy to clipboard and close |
| ⌘⌫ | delete item (⌫ alone when search is empty) |
| ⌘Y or Space | preview |
| ⌘P | pin / unpin |
| ⌘K | clear search |
| ⎋ | clear search, then close |

Opening focuses the search field with a row already selected, so `⌘⇧V → ↩` works without intermediate keystrokes.

## Deliberate Non-Goals

- **Rich text, files, colours.** Supported by extending `ItemKind` and `ClipboardCapture.Payload` with new cases; `PasteboardReader` is the only other place that would need touching.
- **Cross-device sync.** It contradicts the privacy model. If it ever ships, it ships end-to-end encrypted and opt-in.
- **A separate Quick Look window.** Preview renders as an in-panel overlay, because a separate window would steal key status and break keyboard navigation.

## Future Improvements

- **OCR over screenshots** using VisionKit, so image entries become text-searchable. The groundwork exists: `searchIndex` is already a separate field that can be populated after the fact.
- **A test suite.** The pure pieces — content classification, search ranking, deduplication, retention policy — are testable without UI and should be covered first.
- **Signed and notarised distribution**, so launch-at-login works from a real build rather than only from Xcode.
- **Richer content types** — RTF and file references, following the extension path described above.
