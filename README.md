# App Clean

A macOS cleanup tool — uninstall apps completely, purge system caches/logs, and reclaim dev-project build artifacts. SwiftUI, no dependencies, trash-based (reversible).

## Features

Three cleanup modes in one window:

- **Uninstall App** — Drop a `.app` bundle (or folder) to find every related file the app left behind across `~/Library`, `/Library`, `/var/db/receipts`, and Darwin temp/cache folders. Matches by bundle ID, display name, team-ID prefix, vendor folder, versioned IDs, helper bundle IDs, and more.
- **System Cleanup** — Scan user and system caches, logs, DiagnosticReports, and Darwin `/T` `/C` `/X` folders for reclaimable data.
- **Dev Projects** — Drop one or more project-root folders to find `node_modules`, Cargo `target`, `.next`, `__pycache__`, `DerivedData`, and similar throwaway build artifacts.

Everything is moved to the Trash (not hard-deleted), so mistakes are reversible. Requires macOS 13+. No sandbox, no telemetry, no third-party dependencies.

## Build and run

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (the `.xcodeproj` is generated).

```bash
git clone https://github.com/fri13th/app-clean.git
cd app-clean
brew install xcodegen
xcodegen generate
```

Then either:

- `swift run` — quickest, runs from terminal
- `open AppClean.xcodeproj` — build and run in Xcode (⌘R)
- `xcodebuild -project AppClean.xcodeproj -scheme AppClean -configuration Release -derivedDataPath build` — builds a `.app` at `build/Build/Products/Release/AppClean.app`

## Project layout

```
Sources/AppClean/       Swift sources (~500 lines total)
App/                    Icon assets + generated Info.plist
project.yml             XcodeGen spec (source of truth)
Package.swift           SwiftPM config (for `swift run`)
```

`AppClean.xcodeproj/` and `App/Info.plist` are generated — regenerate with `xcodegen generate` after editing `project.yml`.

## Headless CLI

The executable accepts flags for scripted use:

```bash
swift run AppClean --scan "/Applications/Figma.app"     # scan one app
swift run AppClean --scan-system                         # system caches/logs
swift run AppClean --scan-projects "/Users/me/projects"  # dev artifacts
```

No delete in CLI mode — just prints what would be found.
