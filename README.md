# Tune

> **Tune your screen for the moment. Everything else disappears.**

A small macOS menu-bar utility that quiets the noise on your Mac for a screen-share. You pick a few windows; everything else gets out of the way; the chosen window is staged at a consistent size against a clean background.

This is **v0.1** — a working skeleton implementing the architecture from the design doc at `/Users/reed/.claude/plans/i-have-this-problem-federated-meteor.md`. The happy path works end-to-end; a few pieces are deliberately conservative (see "Known limitations" below).

## What's in the box

- **Window enumeration** — lists all visible windows from other apps (`Sources/Tune/Session/WindowEnumerator.swift`).
- **Accessibility-driven window control** — resizes, repositions, and raises target windows (`Session/AccessibilityWindowController.swift`).
- **Staging overlay** — full-screen window painting the chosen background behind your staged target (`Session/StagingOverlay.swift`).
- **Window suppression** — hides any non-target app that tries to come forward during a session (`Session/WindowSuppressor.swift`).
- **DND integration** — runs user-installed Shortcuts to toggle Do Not Disturb (`Session/FocusManager.swift`).
- **Session orchestration** — entry, mid-session Ctrl+Opt+←/→ cycling, hold-Esc-to-exit (`Session/SessionController.swift`).
- **Global hotkeys** — Ctrl+Opt+T toggles Tune; Ctrl+Opt+←/→ cycles staged windows (`App/HotkeyManager.swift`).
- **Launcher UI** — SwiftUI panel to pick windows, display, background (`Launcher/LauncherView.swift`).

## Build & install

You need Xcode command-line tools. Then:

```sh
cd /Users/reed/Desktop/Sandbox/repos/PresenterMode
./build-app.sh
open ./build/
```

(The repo folder is still named `PresenterMode/` from the project's earlier name — that's intentional for now and doesn't affect the app.)

Drag `Tune.app` to `/Applications`. Launch it once — you'll get an Accessibility prompt. Open System Settings → Privacy & Security → Accessibility and enable Tune. Quit and relaunch the app to pick up the permission.

The app lives in the menu bar (no Dock icon). The icon is a `rectangle.on.rectangle` SF Symbol.

> **Upgrading from a previous build named Presenter Mode?** The bundle identifier changed (`com.reed.PresenterMode` → `com.reed.Tune`), so macOS treats Tune as a brand-new app. Open System Settings → Privacy & Security → Accessibility, remove the old `PresenterMode` entry, then launch the new `Tune.app` and re-grant Accessibility access when prompted.

## Optional: DND integration

macOS doesn't expose Focus modes to third-party apps via any clean public API. To wire DND:

1. Open Shortcuts.app.
2. Create a new shortcut named exactly **`Tune DND On`** that runs the "Set Focus" action with "Do Not Disturb" turned on.
3. Create another named exactly **`Tune DND Off`** that turns it off.

Tune shells out to `shortcuts run "Tune DND On"` on session start and the off-variant on exit. If the shortcuts don't exist, the rest of the app works fine — you'll just miss the automatic DND.

> **Upgrading?** If you previously created `Presenter Mode DND On` / `Presenter Mode DND Off`, rename them to `Tune DND On` / `Tune DND Off` (or recreate them).

## Usage

1. Press **Ctrl+Opt+T** anywhere → launcher opens.
2. Tick 1–4 windows to stage. Choose a display (only asked if you have more than one). Choose a background.
3. Click **Start**.
4. During the session:
   - **Ctrl+Opt+→** — cycle to the next staged window. **Ctrl+Opt+←** — cycle back.
   - **Ctrl+Opt+T** again — end the session.
   - **Hold Esc for 1 second** — exit and restore everything.
   - Clicking the menu bar icon → "End Tune" also works.

## Verification (the smoke test from the plan)

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

These are intentional v0.1 gaps, documented so you know what's not finished rather than what's broken:

1. **System dialogs leak.** Apple-process dialogs (software update, low battery, permission prompts) cannot be suppressed by any third-party app. Pause updates manually before high-stakes demos.
2. **Menu bar / Dock are not actively hidden.** They are hidden naturally when our overlay window is at `.normalWindow+1` level only on screens where it covers the menu bar. To truly autohide them, you'd add `NSApp.presentationOptions = [.autoHideMenuBar, .autoHideDock]` — but this only fires when a window is fullscreen. We don't fullscreen because that would steal the staged window from screen-sharing tools. **Workaround for v0.1**: enable "Automatically hide and show menu bar" and "Automatically hide and show Dock" in System Settings.
3. **Window resolution by bounding box.** `WindowHandle` is resolved by matching AX windows to CG windows on size. If you have two windows of identical size from the same app, the wrong one may be picked. Robust resolution requires private API or a heuristic involving titles; flagged for v0.2.
4. **Hotkeys are hardcoded.** `Fn` is not a valid hotkey modifier per macOS conventions. Customization UI is not built yet — to rebind, edit the `hotkeyManager.register(...)` calls in `App/AppDelegate.swift`.
5. **No state for "currently active staged target" in the UI.** SessionController tracks it internally but the launcher doesn't surface it. v0.2.
6. **No automatic recovery if the chosen window crashes mid-session.** The suppressor stops re-raising it; you exit manually with Esc-hold. v0.2 should detect the missing window and gracefully end the session.

## Project layout

```
Tune/  (repo folder is still PresenterMode/ on disk — see Build & install)
├── Package.swift
├── README.md
├── build-app.sh                  # wraps swift build → Tune.app
├── Resources/
│   └── Info.plist                # LSUIElement, Accessibility usage description
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
