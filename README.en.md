<p align="center">
  <img src="Resources/icon.png" width="128" alt="MomentFlow">
</p>

<h1 align="center">MomentFlow</h1>

<p align="center">A small macOS menu bar recorder: one keypress, and whatever you're watching is saved.</p>

<p align="center">
  <a href="README.md">中文</a> ｜ <a href="README.en.md">English</a>
</p>

---

## What it is

A menu bar app for macOS. While watching a video or listening to music,
press a shortcut and it records the current window — picture and system audio —
into an **mp4** file, saved straight to a folder. No screen recorder window,
no setup dialog.

It has exactly three actions:

| Action | Default shortcut | Description |
| --- | --- | --- |
| Quick record | `⌘⇧R` | Record the current window; press again to stop |
| Capture | `⌥⌘5` | Open a toolbar to pick the whole screen, a window, or a region |
| Mark a moment | `⌥⌘M` | Take a screenshot and jot down a note |

Shortcuts are configurable in Settings and take effect immediately.

## Features

- **Window-only capture**: records that window's own content. The desktop,
  background, and other windows are never included. Even if the window is
  half-covered, the result is complete.
- **Picture and system audio in one file**: both are captured by default,
  or you can record audio only.
- **Flat output**: one recording is one file, ready to drag into your editor.
- **No third-party dependencies**: only system frameworks
  (ScreenCaptureKit, AVFoundation, AppKit, SwiftUI).
- **Save confirmation**: a small card shows the file path after each recording;
  click it to reveal the file in Finder.

## Privacy and security

**No network access at runtime.**

The app makes no network requests. There is no account system, no analytics,
no telemetry, no crash reporting, and no cloud sync. You will not find any
`URLSession` or `Network` calls in the source.

**Recordings stay on your machine.**

The default folder is `~/Desktop/MomentFlow/`, and it can be changed in Settings.
Recordings, screenshots, and notes are never uploaded anywhere.

**The only network activity happens during installation**, when the source is
downloaded from GitHub and compiled. Once installed, the app works offline.

One caveat worth stating plainly: screen recording is a high-privilege
operation. Please judge for yourself whether the content you record and share
is appropriate.

## Requirements

- macOS 14 or later
- Xcode or Xcode Command Line Tools (for building)

**Size**

- Installed app: about **2 MB**
- Source archive on GitHub: about **1 MB**

## Installation

### Option 1: One-line installer

Open **Terminal** and paste this single line:

```bash
curl -fsSL https://raw.githubusercontent.com/Zniiwax/MomentFlow-macOS/main/Scripts/install.sh | bash
```

It checks your system, downloads the source, builds it, installs the app to
`~/Applications`, and launches it.

The first run may need Apple's Command Line Tools (about 1–2 GB). The script
detects that and triggers the installer; click **Install**, wait for it to
finish, then run the command again.

### Option 2: Manual install from the GitHub page

Best if you want to see every step, or if the one-line installer fails.

1. Open the project page: <https://github.com/Zniiwax/MomentFlow-macOS>
2. Click the green **Code** button → **Download ZIP**
3. Double-click the downloaded zip to extract it (usually into `Downloads`)
4. Open **Terminal**
5. Run:

   ```bash
   cd ~/Downloads/MomentFlow-macOS-main && ./Scripts/build_app.sh && open Dist/MomentFlow.app
   ```

   If the extracted folder has a different name, adjust the path.

6. If macOS asks for Command Line Tools, click **Install**, then repeat step 5.

No administrator password is required. The built app is at `Dist/MomentFlow.app`.

### Option 3: Build from source (developers)

```bash
git clone https://github.com/Zniiwax/MomentFlow-macOS.git
cd MomentFlow-macOS
swift build
swift test
./Scripts/build_app.sh
open Dist/MomentFlow.app
```

### Optional: keep permissions across rebuilds

macOS ties the Screen Recording permission to the code signature. With ad-hoc
signing, every rebuild looks like a different app to the system, so previously
granted permission is lost.

If you plan to rebuild frequently, run this once:

```bash
./Scripts/setup_signing.sh
```

It creates a self-signed certificate in your login keychain, trusted only for
code signing. After that, rebuilds keep the permission. To undo:

```bash
security delete-identity -c "MomentFlow Local Signing"
```

## First run

**Step 1 — Open the app**

The installer opens it automatically. Afterwards you can find it in Launchpad
or in `~/Applications`.

It has no Dock icon and no main window. Once opened, a small round icon appears
in the **menu bar at the top right** of the screen.

**Step 2 — Grant Screen Recording**

On first launch a welcome window appears. Click **Grant Screen Recording**,
which opens **System Settings → Privacy & Security → Screen & System Audio Recording**.

Find MomentFlow in the list and turn the switch on.

If it is not in the list, click the **+** button below the list and choose
`~/Applications/MomentFlow.app`.

**Step 3 — Quit and reopen**

This step is required. The Screen Recording permission is only read at process
launch; a running process does not pick up changes.

Quit via the menu bar icon → **Quit**, or press `⌘Q`.

**Step 4 — First recording**

Click the window you want to record so it comes to the front, then press `⌘⇧R`.
The menu bar icon turns into a red dot with a timer. Press again to stop.

**Step 5 — Allow Desktop folder access**

The first save triggers a "wants to access your Desktop folder" prompt. Allow it.
Recordings are saved to `~/Desktop/MomentFlow/` by default.

## Updating

Run the installer again; it downloads the latest source, rebuilds, and replaces
the installed copy:

```bash
curl -fsSL https://raw.githubusercontent.com/Zniiwax/MomentFlow-macOS/main/Scripts/install.sh | bash
```

If you cloned the repository locally, use:

```bash
./Scripts/update.sh
```

It pulls the latest code, builds, replaces the app in `~/Applications`, and
relaunches it.

> If you have run `./Scripts/setup_signing.sh`, the Screen Recording permission
> survives updates. With ad-hoc signing you will need to grant it again.

## Uninstalling

Use the script:

```bash
./Scripts/uninstall.sh
```

It removes the app and its preferences. **It never deletes your recordings.**

To also remove the local signing certificate:

```bash
./Scripts/uninstall.sh --purge
```

To see what would be removed without doing it:

```bash
./Scripts/uninstall.sh --dry-run
```

One step has to be done by hand: open **System Settings → Privacy & Security →
Screen & System Audio Recording**, select MomentFlow and click the **−** button.

You can also uninstall manually: move `~/Applications/MomentFlow.app` to the
Trash to disable it. Preferences live at
`~/Library/Preferences/local.momentflow.app.plist`.

## Usage

### Quick record

Press `⌘⇧R` to record the largest window of the active app; press again to stop.

"Active" means the app you clicked last, so click the target window first.

### Capture toolbar

Press `⌥⌘5` and a toolbar appears at the bottom of the screen:

- **Screen**: records the display where the mouse is
- **Window**: hover to highlight a window, click to select it
- **Region**: drag to select an area; after releasing you can still resize with
  the handles or move it by dragging inside

Two toggles control what is recorded:

- Picture on → outputs `.mp4`
- Audio only → outputs `.m4a`

Press Return or click **Start Recording**. Press `Esc` to cancel.

### Mark a moment

Press `⌥⌘M` to take a screenshot and open a small note window. Notes save
automatically.

### While recording

The menu bar icon shows a red dot and the elapsed time. The toolbar becomes a
control bar with stop and discard. Quitting during a recording waits for the
file to finish writing before exiting.

### Using the menu bar

You don't have to memorize shortcuts. Click the round icon at the top right of
the screen:

- **Capture…** — opens the toolbar
- **Quick Record / Stop Recording**
- **Mark a Moment**
- **Open Library** — opens the recordings folder in Finder
- **Open Latest Recording** — reveals the most recent file in Finder
- **Settings…** — shortcuts, library location, default capture options
- **Shortcuts…** — the welcome/help window
- **Screen Recording permission status**
- **Quit**

While recording, the icon turns into a red dot with a timer, and the first
menu item shows the elapsed time.

## Output

Default location: `~/Desktop/MomentFlow/`

```
~/Desktop/MomentFlow/
  index.jsonl                              metadata, one record per line
  2026-10-24_104136_Window.mp4             picture + system audio
  2026-10-24_105218_Title.png              screenshot from "Mark a moment"
```

File names are a timestamp plus the window title. Duplicates get `-2`, `-3`
suffixes.

The library location can be changed in Settings.

## Settings

Menu bar icon → **Settings**:

- Shortcuts (click the field, then press the combination you want)
- Library location
- Default capture options (picture / system audio)
- Screen Recording permission status

## Limitations

- **macOS only**, built on ScreenCaptureKit.
- **DRM-protected content cannot be recorded.** Netflix, Apple TV+ and similar
  services produce a black frame. This is an OS-level restriction.
- **No prebuilt binary.** The installer compiles locally. Shipping a
  "download and run" binary requires an Apple Developer certificate and
  notarization.
- **No microphone capture.** Only system audio is recorded.

## FAQ

**Nothing happened after opening it.**

It is a menu bar app with no main window. Look at the **top right** of the
screen for a round icon. If there is none, open Activity Monitor and check
whether MomentFlow is running.

**"Cannot be opened because the developer cannot be verified."**

A locally built copy should not trigger this. If it does, right-click the app
and choose **Open**, or use **Open Anyway** in System Settings → Privacy & Security.

**MomentFlow does not appear in System Settings.**

Click **+** below the list and choose `~/Applications/MomentFlow.app`.
If there is an old, non-working entry, remove it with **−** first.

**It still says there is no permission after I granted it.**

Quit the app and reopen it. The permission is only read at launch.

**The recording is black.**

The content is DRM-protected (Netflix, Apple TV+ and similar). macOS does not
allow recording it.

**The recording does not match what I see.**

Check whether you switched between full screen and windowed mode — the page
layout itself changes. If it persists, please open an issue with your macOS
version and a screenshot.

## Project structure

```
Sources/
  MomentFlowCore/     capture, encoding, storage, coordinate math (no UI, testable)
  MomentFlow/         menu bar app, toolbar, selection overlay, settings
Tests/
  MomentFlowCoreTests/
Scripts/
  install.sh          one-line installer
  build_app.sh        build the .app bundle
  setup_signing.sh    create a local code signing certificate
  GenerateIcon.swift  generate the app and menu bar icons
Resources/
  Info.plist
  AppIcon.icns
  MenuBarIcon.png
```

## Development

```bash
swift build            # compile
swift test             # run unit tests
./Scripts/build_app.sh # build the .app bundle
```

The unit tests cover coordinate conversion, library storage, shortcut parsing,
and window selection.

## License

MIT — see [LICENSE](LICENSE).
