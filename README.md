# Barloom

**Your Mac. One Bar. Everything.**

Barloom brings a menu bar icon shelf, live system readings, an animated companion, and a local port viewer into one native macOS app. It is built with Swift 6, SwiftUI, and AppKit, with no third-party runtime dependencies.

> **Early preview (0.1.0).** The source builds and runs locally, but there is no downloadable, notarized release yet. Menu bar icon management is still being refined across macOS versions.

## What works today

| Area | Current features |
| --- | --- |
| **Menu Bar** | An optional horizontal shelf below the menu bar; a visual icon chooser; selected icon images in the shelf; keyboard shortcut; custom image for Barloom's own status item. |
| **System Monitor** | CPU, memory, disk capacity, network rates, battery, uptime, and thermal readings; a dashboard and optional status widget. |
| **Runner** | Cat, Orbit, and Pulse animations that respond to CPU usage, with reduced-motion support. |
| **Local Ports** | Discover TCP listeners visible to your user, search by process or port, open or copy localhost URLs, and confirm a graceful stop for supported development processes. |

Modules can be turned off independently. Barloom shares one system sampler, offers 1/2/5/10-second sampling intervals, slows port scans when the dashboard is closed, and pauses work during sleep.

## Build and run

**Requirements:** macOS 14 or later and Xcode 16 or later, or equivalent Swift 6 command-line tools.

```sh
git clone https://github.com/fordft/barloom.git
cd barloom
./scripts/build-app.sh --launch
```

The script creates `.build/Barloom.app` and signs it locally with an ad-hoc signature by default. For a faster development build, use `./scripts/build-app.sh --debug --launch`. Quit a running Barloom instance before opening a rebuilt app.

To use a stable Apple Development identity for local permission approvals:

```sh
BARLOOM_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-app.sh --launch
```

Changing the signing identity may cause macOS to ask for Screen Recording and Accessibility approval again. Developer ID signing and notarization are future release work.

### Try the app

1. Open **Settings** in the dashboard and enable the modules you want. Menu Bar management starts disabled.
2. Click Barloom's menu bar icon or press **Control–Option–B** to open the icon shelf. **Shift-click** the icon for the Quick Monitor popover.
3. In **Menu Bar** settings, choose which discovered icons appear in the shelf. Right-click Barloom and choose **Open All Hidden Icons** to reach hidden icons that are not selected.
4. Open **Local Ports** to inspect listeners. The Stop action is offered only for supported development processes owned by your user and asks for confirmation.

## Menu bar permissions and limits

Barloom asks for **Screen Recording** only when you choose to allow icon image capture, and for **Accessibility** when you choose to allow opening or moving other apps' menu bar items. System Monitor, Runner, and Local Ports work without these permissions. Captured status images stay in memory; Barloom does not record audio or send readings to a service.

The icon chooser controls which items appear in Barloom's shelf. Clicking an image temporarily reveals and activates the real status item; the other app's native menu opens from its item in the **system menu bar**. macOS does not provide a way to relocate another app's menu or custom popover to Barloom's shelf. Barloom keeps the shelf visible during activation. Some apps expose limited menu actions, so activation or movement can vary by app and macOS version. The shelf is positioned for the active display and closes when the display or Space changes.

Port discovery is limited to sockets visible to the current user. **Open** assumes HTTP, except ports 443 and 8443, which use HTTPS; a non-web listener may not open in a browser.

## Development

```sh
swift test
swift run Barloom --diagnostics
```

`--diagnostics` prints current system readings and discovered listeners as JSON without opening the interface. For an isolated native shelf smoke check, launch the bundled app with `--shelf-smoke-test`; it creates disposable status items and uses a separate preference domain.

| Path | Purpose |
| --- | --- |
| `Sources/Barloom/` | App lifecycle, menu bar UI, artwork, and SwiftUI screens |
| `Sources/BarloomCore/` | Metrics, port scanning, preferences, and process safety |
| `Sources/BarloomMenuBarNative/` | Small native bridge for status images and permission prompts |
| `Tests/` | Core and menu bar behavior tests |
| `scripts/build-app.sh` | Build, bundle, sign, and optionally launch the app |

### Next steps

- Improve icon movement and activation reliability across more macOS versions and display setups.
- Add GPU and disk I/O telemetry, more widgets, and custom Runner animation imports.
- Extend local development process controls and test performance on more Macs.
- Prepare a signed and notarized release.

The offscreen icon capture bridge currently uses a deprecated public Quartz image API. It is isolated in `Sources/BarloomMenuBarNative/` so it can be replaced as macOS evolves.

## License

Barloom is available under the [MIT License](LICENSE).
