# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Hot Corners — a tiny macOS menu bar utility (no Dock icon, `LSUIElement`). Push the
cursor into a screen corner and it launches a user-chosen app. Native AppKit + SwiftUI,
Swift Package Manager, no external dependencies. Targets macOS 13+.

## Commands

```bash
swift build                 # debug build, compiles Sources/HotCorners
swift run                   # build + run directly (menu bar icon appears)
./build.sh                  # release build -> assembles & ad-hoc signs dist/Hot Corners.app
```

There are no automated tests and no lint config in this repo.

To try a change end-to-end, prefer `swift run` over the full `build.sh` bundling flow.

## IMPORTANT: after editing Sources/, always redeploy the installed app

The user runs this app from `/Applications/Hot Corners.app` (a login item, bundle id
`com.local.hotcorners`), not from `swift run`. `swift run`/`swift build` alone only touches
`.build/` — it does **not** update the app the user actually sees running. After **any**
change under `Sources/`, always finish with:

```bash
./build.sh
pkill -f "Hot Corners"
rm -rf "/Applications/Hot Corners.app"
cp -R "dist/Hot Corners.app" "/Applications/Hot Corners.app"
open "/Applications/Hot Corners.app"
```

Do this automatically, without waiting for the user to ask or to remind you the change
isn't visible yet. Verify the new binary is actually the one running (e.g. compare
`ps -p <pid> -o lstart` against the `dist` binary's mtime, or `md5` the two binaries)
before telling the user it's ready to check.

## Verifying visual changes (positioning, opacity, colors)

**Accessibility permission for the `Claude` app (`/Applications/Claude.app`) has been granted
by the user** — `cliclick` can move the real cursor now. This is by far the fastest way to
check anything corner/hover-related, and it's the ONLY way that exercises real interaction
state (see the hover-fill bug below, which only ever showed up while actually hovering):

```bash
cliclick m:600,600        # move away first so the corner re-triggers cleanly
sleep 0.3
cliclick m:2,2             # into the physical top-left corner (adjust per corner)
sleep 0.6                  # > 0.28s intro-animation duration
screencapture -x /path/to/shot.png
```
```bash
python3 -c "
from PIL import Image
im = Image.open('/path/to/shot.png')
im.crop((0,0,500,500)).save('/path/to/crop.png')   # menu bar/notch make full screenshots noisy; always crop
"
```
Then read the crop with the Read tool. Move the cursor back out (`cliclick m:600,600`) when
done so you don't leave the panel open. If `cliclick` ever reports "Accessibility privileges
not enabled" again (permission can be revoked from System Settings independently of this repo),
tell the user plainly and ask them to re-enable it for `Claude` under Privacy & Security →
Accessibility — don't silently fall back without saying so.

### Real bug this caught: test the *hover* state, not just the resting state

The card looked opaque at rest but turned invisible-background (fully see-through) the instant
the pointer actually sat over it. Root cause in `CornerPreviewView.updateFill()`
(`CornerPreviewPanel.swift`): `NSColor.blended(withFraction:of:)` was used to mix the dynamic
`controlAccentColor` into the flat base fill on hover. That call **can silently return `nil`**
when the two colors don't share a compatible color space (a dynamic catalog color vs. a plain
calibrated one is exactly such a case) — and `shapeLayer.fillColor = nil` means no fill at all.
Fixed by resolving both colors to `.deviceRGB` and blending the RGB components by hand instead
of trusting `blended(withFraction:of:)`. Lesson: any test of this panel MUST include the
`isHovering = true` path (i.e. an actual cursor-over-card check), since the resting-state fill
and the hover-state fill are computed by different code and can diverge.

### Fallback: if Accessibility permission is ever unavailable again

Force-show the panel from code and inspect it directly, without moving the mouse:

1. Temporarily add a debug branch to `AppDelegate.applicationDidFinishLaunching`, gated by an
   env var so it never ships:
   ```swift
   if ProcessInfo.processInfo.environment["HOTCORNERS_DEBUG_PREVIEW"] != nil, let screen = NSScreen.main {
       let icon = NSWorkspace.shared.icon(forFile: "/Applications/Claude.app")
       let panel = CornerPreviewPanel(corner: .topLeft, icon: icon, screenFrame: screen.frame)
       NSApp.activate(ignoringOtherApps: true)
       panel.orderFrontRegardless()
       panel.playIntroAnimation()   // <-- do not skip this
       debugPanel = panel           // keep a strong ref (add as a property)
   }
   ```
   **Gotcha that cost the most time:** `init()` places the panel at its off-screen
   *starting* position (`offscreenOrigin`, ~85% of the card size beyond the corner) — only
   `playIntroAnimation()` slides it to the real resting spot. Skipping that call makes the
   panel sit far outside the display, so every screenshot comes back empty and looks like
   "nothing rendered," when actually the window is just parked off in space.
2. Build the *release* bundle (the debug env-var branch must exist in the binary you run —
   `swift build` debug output works fine too, just make sure whichever binary you exec was
   built after the debug branch was added) and launch it directly, backgrounded, with the env
   var set:
   ```bash
   HOTCORNERS_DEBUG_PREVIEW=1 .build/debug/HotCorners &
   DEBUG_PID=$!
   sleep 1.0   # let playIntroAnimation() (0.28s) finish
   ```
3. Confirm the window actually exists and where, via `CGWindowListCopyWindowInfo` (needs no
   extra permission beyond what `screencapture` already has) — write a tiny throwaway script:
   ```swift
   // dumpwin.swift
   import CoreGraphics
   let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
   let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as! [[String: AnyObject]]
   for w in list where (w[kCGWindowOwnerName as String] as? String)?.contains("Hot") == true {
       print(w)   // bounds are TOP-LEFT origin (Quartz), unlike NSWindow.frame's bottom-left
   }
   ```
   Run with `swift dumpwin.swift`. Sanity-check the reported `kCGWindowBounds` against the
   panel's expected resting frame before trusting any screenshot.
4. Take the real screenshot with `screencapture -x <path>` (full screen — region args to
   `-R` are in points and easy to miscompute; crop afterward instead), then `kill $DEBUG_PID`.
   Crop and inspect with Python/PIL, e.g.:
   ```bash
   python3 -c "
   from PIL import Image
   im = Image.open('<path>')
   im.crop((0,0,700,700)).save('<crop_path>')
   "
   ```
   Read the crop with the Read tool to eyeball it.
5. For a pixel-exact opacity check (not just "looks solid"), skip the screen entirely and
   rasterize the view's own layer tree to a PNG with a real alpha channel, then check alpha
   values in Python — this proves whether the *drawn content* is opaque independent of
   anything the WindowServer/compositor might be doing:
   ```swift
   guard let contentView = panel.contentView, let layer = contentView.layer else { return }
   let bounds = contentView.bounds
   let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width) * 2,
       pixelsHigh: Int(bounds.height) * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
   bitmap.size = bounds.size
   let cg = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
   cg.scaleBy(x: 2, y: 2)
   layer.render(in: cg)
   try? bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "<path>"))
   ```
   ```bash
   python3 -c "
   from PIL import Image
   im = Image.open('<path>').convert('RGBA')
   for p in [(20,20),(200,400),(220,220)]: print(p, im.getpixel(p))   # alpha must be 255
   "
   ```
6. Always remove the debug branch (and the `debugPanel` property) before the final redeploy —
   `git diff Sources/HotCorners/AppDelegate.swift` should come back empty.

## Architecture

Everything lives in `Sources/HotCorners/`, one type per file:

- **main.swift** — entry point; creates `NSApplication`, sets `.accessory` activation policy
  (no Dock icon), assigns `AppDelegate`.
- **AppDelegate.swift** — owns the `NSStatusItem` (menu bar icon + menu) and the Settings
  window (`NSHostingView` wrapping `SettingsView`). Creates and starts the single
  `CornerMonitor` instance.
- **CornerMonitor.swift** — the core loop. Polls `NSEvent.mouseLocation` on a repeating
  `Timer` (every 80ms) and checks distance to each screen's four corners (4pt threshold).
  On a corner hit it looks up the configured app in `SettingsStore` and shows a
  `CornerPreviewPanel`; the panel's `onConfirm` callback (fired on click) actually launches
  the app via `NSWorkspace`. Tracks a `suppressedCorner` so the preview doesn't instantly
  reappear right after a launch while the cursor is still sitting in the hot zone.
- **CornerPreviewPanel.swift** — borderless, non-activating `NSPanel` that slides in from
  off-screen next to the triggered corner, showing the target app's icon. `hoverZone(in:)`
  extends the interactive area from the panel's resting frame out to the physical screen
  edges so there's no dead gap between where the hover started and the inset card.
  `CornerMonitor.tick()` uses this zone to decide whether to keep the panel open. Clicking
  the panel (`mouseDown`) fires `onConfirm`.
- **Corner.swift** — the `Corner` enum (`topLeft`/`topRight`/`bottomLeft`/`bottomRight`),
  `Codable`, used as the key type throughout.
- **SettingsStore.swift** — singleton (`SettingsStore.shared`), `ObservableObject`.
  Persists per-corner app paths in `UserDefaults` (`corner.app.<rawValue>` keys) and mirrors
  `LoginItem` state as `launchAtLogin`. This is the single source of truth both the monitor
  and the SwiftUI settings screen read from.
- **SettingsView.swift** — SwiftUI settings UI: one row per corner with an `NSOpenPanel`
  app picker, a login-at-startup toggle, and quit.
- **LoginItem.swift** — thin wrapper around `SMAppService.mainApp` (register/unregister as
  a login item).

### Data flow

`SettingsView` (or anything) mutates `SettingsStore.shared` → `CornerMonitor` reads it live
on each timer tick → `CornerPreviewPanel` is shown/launched accordingly. There's no other
messaging/notification layer — it's a single shared observable store polled directly.

### Packaging

`build.sh` is the only packaging path: it runs `swift build -c release`, hand-assembles
`dist/Hot Corners.app/Contents/{MacOS,Info.plist}`, then ad-hoc code-signs the bundle
(`codesign --force --deep --sign -`). There's no Xcode project — the app bundle's
`Info.plist` (bundle id `com.local.hotcorners`, `LSUIElement=true`) is generated inline
inside `build.sh`, not stored as a separate file.
