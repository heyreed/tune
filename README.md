<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
    <img src="docs/logo.png" alt="Tune" width="128" height="128">
  </picture>
</p>

# Tune

> **Tune your screen for the moment. Everything else disappears.**

A small macOS menu-bar utility that quiets the noise on your Mac for a screen-share. You pick a few windows; everything else gets out of the way; the chosen window is staged at a consistent size against a clean background.

This is **v0.2.0** — the happy path works end-to-end. A few pieces are deliberately conservative; see "Known limitations" below.

## What's in the box

- **Window enumeration** — lists all visible windows from other apps (`Sources/Tune/Session/WindowEnumerator.swift`).
- **Accessibility-driven window control** — resizes, repositions, and raises target windows (`Sources/Tune/Session/AccessibilityWindowController.swift`).
- **Staging overlay** — full-screen window painting the chosen background behind your staged target (`Sources/Tune/Session/StagingOverlay.swift`).
- **Window suppression** — hides any non-target app that tries to come forward during a session (`Sources/Tune/Session/WindowSuppressor.swift`).
- **DND integration** — runs user-installed Shortcuts to toggle Do Not Disturb (`Sources/Tune/Session/FocusManager.swift`).
- **Session orchestration** — entry, mid-session Ctrl+Opt+←/→ cycling, hold-Esc-to-exit (`Sources/Tune/Session/SessionController.swift`).
- **Global hotkeys** — Ctrl+Opt+T toggles Tune; Ctrl+Opt+←/→ cycles staged windows (`Sources/Tune/App/HotkeyManager.swift`).
- **Launcher UI** — SwiftUI panel to pick windows, display, background (`Sources/Tune/Launcher/LauncherView.swift`).

## Requirements

- macOS 13 (Ventura) or later
- Xcode command-line tools (`xcode-select --install`)
- Swift 5.9+ (bundled with recent Xcode)

## Build & install

From the root of the cloned repo:

```sh
./build-app.sh
open ./build/
```

Drag `Tune.app` to `/Applications`. Launch it once — you'll get an Accessibility prompt. Open **System Settings → Privacy & Security → Accessibility** and enable Tune. Quit and relaunch the app to pick up the permission.

The app lives in the menu bar (no Dock icon). The menu-bar glyph and the Finder/Dock icon both use the Tune mark (see `docs/logo.png`); the menu-bar version is rendered as a template image so it picks up your menu bar's foreground color automatically.

> **Note:** The repo folder is named `PresenterMode/` from the project's earlier name. That's cosmetic — the Swift package, binary, and app bundle are all `Tune`.

## Optional: DND integration

macOS doesn't expose Focus modes to third-party apps via any clean public API. To wire DND:

1. Open Shortcuts.app.
2. Create a new shortcut named exactly **`Tune DND On`** that runs the "Set Focus" action with "Do Not Disturb" turned on.
3. Create another named exactly **`Tune DND Off`** that turns it off.

Tune shells out to `shortcuts run "Tune DND On"` on session start and the off-variant on exit. If the shortcuts don't exist, the rest of the app works fine — you'll just miss the automatic DND.

## Usage

1. Press **Ctrl+Opt+T** anywhere → launcher opens.
2. Tick 1–4 windows to stage. Choose a display (only asked if you have more than one). Choose a background.
3. Click **Start**.
4. During the session:
   - **Ctrl+Opt+→** — cycle to the next staged window. **Ctrl+Opt+←** — cycle back.
   - **Ctrl+Opt+T** again — end the session.
   - **Hold Esc for 1 second** — exit and restore everything.
   - Clicking the menu bar icon → "End Tune" also works.

You can also open the launcher from the menu bar icon via **Tune Windows…**.

## Smoke test

1. Open Firefox with one tab on `localhost:3000`. Open Figma with a mockup, hide its UI (`Cmd+\\`).
2. Trigger the hotkey. Launcher appears. Select both windows, pick the main display, pick the blurred-wallpaper background. Hit Start.
3. Confirm:
   - Both target windows are resized to ~80% of the screen.
   - Background fills the rest of the display; menu bar and Dock are gone.
   - DND is on (Control Center icon) — only if you wired up the Shortcuts.
4. From inside Firefox, **Ctrl+Opt+→** → Figma comes forward, Firefox goes behind.
5. Force a leak attempt: send yourself an iMessage → no banner appears (if DND is on). Open Slack from Spotlight → Slack window is hidden behind the staged window.
6. **Hold Esc for 1 second** → windows restored, background gone, menu bar back, DND off.
7. Re-enter Tune. Quit Firefox while staged. The app should fall back gracefully (the suppressor stops re-raising the missing window; you can exit with Esc-hold).

## Known limitations

These are intentional gaps, documented so you know what's not finished rather than what's broken:

1. **System dialogs leak.** Apple-process dialogs (software update, low battery, permission prompts) cannot be suppressed by any third-party app. Pause updates manually before high-stakes demos.
2. **Menu bar / Dock are not actively hidden.** They are hidden naturally when our overlay window covers the menu bar. To truly autohide them, you'd add `NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]` — but this only fires when a window is fullscreen. We don't fullscreen because that would steal the staged window from screen-sharing tools. **Workaround:** enable "Automatically hide and show menu bar" and "Automatically hide and show Dock" in System Settings.
3. **Window resolution by bounding box.** `WindowHandle` is resolved by matching AX windows to CG windows on size. If you have two windows of identical size from the same app, the wrong one may be picked. Robust resolution requires private API or a heuristic involving titles.
4. **Hotkeys are hardcoded.** `Fn` is not a valid hotkey modifier per macOS conventions. Customization UI is not built yet — to rebind, edit the `hotkeyManager.register(...)` calls in `Sources/Tune/App/AppDelegate.swift`.
5. **No state for "currently active staged target" in the UI.** SessionController tracks it internally but the launcher doesn't surface it.
6. **No automatic recovery if the chosen window crashes mid-session.** The suppressor stops re-raising it; you exit manually with Esc-hold.

## Project layout

```
PresenterMode/                       # repo folder name (see "Build & install")
├── Package.swift
├── README.md
├── build-app.sh                     # wraps swift build → build/Tune.app
├── Resources/
│   └── Info.plist                   # LSUIElement, Accessibility usage description
└── Sources/Tune/
    ├── App/
    │   ├── main.swift
    │   ├── AppDelegate.swift
    │   ├── HotkeyManager.swift
    │   └── StatusItemController.swift
    ├── Launcher/
    │   ├── LauncherView.swift
    │   ├── LauncherWindowController.swift
    │   └── WindowPickerViewModel.swift
    ├── Session/
    │   ├── AccessibilityWindowController.swift
    │   ├── FocusManager.swift
    │   ├── SessionController.swift
    │   ├── StagingOverlay.swift
    │   ├── WindowEnumerator.swift
    │   └── WindowSuppressor.swift
    ├── Permissions/
    │   └── AccessibilityGate.swift
    └── Support/
        └── BackgroundPreset.swift
```
