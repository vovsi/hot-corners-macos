# Hot Corners for macOS

A tiny menu bar utility that launches an app of your choice when you push the
mouse cursor into a corner of the screen — classic "hot corners", but with
any app you pick (not just Mission Control / Desktop).

Works on Apple Silicon Macs (including M5 Pro) running macOS Tahoe (26) and
newer.

## Install (already built for you)

The app is already built and installed at:

```
/Applications/Hot Corners.app
```

Just open it:

1. Open **Finder → Applications**.
2. Double-click **Hot Corners**.
3. macOS may show a warning because the app isn't signed by an Apple
   Developer account. If that happens: **right-click (or Control-click)**
   the app → **Open** → click **Open** again in the dialog. You only need
   to do this once.
4. Look at the top-right menu bar — a small square icon appears. That means
   it's running. There is **no Dock icon** for Hot Corners itself (it's a
   background menu bar tool); apps that it launches for you will appear in
   the Dock normally, like any other app.

## How to use it

1. Click the menu bar icon → **Settings…**
2. For each corner (Top Left, Top Right, Bottom Left, Bottom Right), click
   **Choose…** and pick an app from `/Applications`.
3. Close the window. Now push your mouse into that screen corner and the
   app will launch/activate.
4. Optional: toggle **Launch Hot Corners at login** so it starts
   automatically every time you log in.
5. To stop it: menu bar icon → **Quit Hot Corners**.
6. To remove a corner's app: **Settings…** → **Clear** next to that corner.

## Notes

- No special permissions (Accessibility, Input Monitoring, etc.) are
  required — it only reads the mouse position.
- There's a short cooldown (1 second) after triggering a corner so it
  doesn't relaunch the app repeatedly while your cursor sits there.
- Settings are stored per-user (`UserDefaults`), so each macOS account has
  its own corner setup.

## Uninstall

1. Menu bar icon → **Quit Hot Corners**.
2. If you enabled "Launch at login", untoggle it first (or just delete the
   app — macOS removes the login item automatically).
3. Delete `/Applications/Hot Corners.app`.

## Rebuilding from source (optional, for developers)

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
./build.sh
```

This produces `dist/Hot Corners.app`, ad-hoc signs it, and you can copy it
to `/Applications` yourself.
