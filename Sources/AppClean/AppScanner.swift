import Foundation
import AppKit

struct AppInfo: Hashable {
    let bundleURL: URL
    let bundleID: String
    let displayName: String
}

enum AppScanner {
    static func readAppInfo(from bundleURL: URL) -> AppInfo? {
        let plistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = plist["CFBundleIdentifier"] as? String else {
            return nil
        }
        let name = (plist["CFBundleName"] as? String)
            ?? (plist["CFBundleDisplayName"] as? String)
            ?? bundleURL.deletingPathExtension().lastPathComponent
        return AppInfo(bundleURL: bundleURL, bundleID: bundleID, displayName: name)
    }

    static func scan(for app: AppInfo) -> [LeftoverItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var searchDirs: [(String, String)] = [
            ("\(home)/Library",                        "Library (User)"),
            ("/Library",                               "Library (System)"),
            ("\(home)/Library/Application Support",    "Application Support"),
            ("\(home)/Library/Application Support/CrashReporter", "Crash Reporter"),
            ("\(home)/Library/Preferences",            "Preferences"),
            ("\(home)/Library/Preferences/ByHost",     "Preferences (ByHost)"),
            ("\(home)/Library/Caches",                 "Caches"),
            ("\(home)/Library/Caches/SentryCrash",     "Sentry Crash"),
            ("\(home)/Library/Containers",             "Containers"),
            ("\(home)/Library/Group Containers",       "Group Containers"),
            ("\(home)/Library/LaunchAgents",           "LaunchAgents (User)"),
            ("\(home)/Library/Logs",                   "Logs"),
            ("\(home)/Library/Logs/DiagnosticReports", "Diagnostic Reports"),
            ("\(home)/Library/Saved Application State","Saved State"),
            ("\(home)/Library/HTTPStorages",           "HTTPStorages"),
            ("\(home)/Library/WebKit",                 "WebKit"),
            ("\(home)/Library/Cookies",                "Cookies"),
            ("\(home)/Library/Application Scripts",    "Application Scripts"),
            ("\(home)/Library/Caches/com.apple.helpd/Generated", "Help Cache"),
            ("/Applications/Utilities",                "Related Install"),
            ("/Library/Application Support",           "Application Support (System)"),
            ("/Library/Preferences",                   "Preferences (System)"),
            ("/Library/Caches",                        "Caches (System)"),
            ("/Library/LaunchAgents",                  "LaunchAgents (System)"),
            ("/Library/LaunchDaemons",                 "LaunchDaemons"),
            ("/Library/Logs",                          "Logs (System)"),
            ("/Library/Logs/DiagnosticReports",        "Diagnostic Reports (System)"),
            ("/Library/PrivilegedHelperTools",         "Privileged Helpers"),
            ("/var/db/receipts",                       "Installer Receipts"),
        ]

        // Darwin per-user dirs: /var/folders/xx/.../T/ and .../C/
        let tmp = NSTemporaryDirectory()
        let base = (tmp as NSString).deletingLastPathComponent
        if !base.isEmpty {
            searchDirs.append(("\(base)/T", "Darwin Temp"))
            searchDirs.append(("\(base)/C", "Darwin Cache"))
            searchDirs.append(("\(base)/X", "Darwin CodeSign"))
            searchDirs.append(("\(base)/0", "Darwin User"))
        }

        let bundleLower = app.bundleID.lowercased()
        let nameLower = app.displayName.lowercased()
        let concatName = nameLower.replacingOccurrences(of: " ", with: "")
        let useConcatMatch = concatName.count >= 10
        let vendor = vendorToken(from: app.bundleID) ?? ""
        let vendorPrefix: String = {
            let parts = bundleLower.split(separator: ".")
            guard parts.count >= 2 else { return "" }
            return "\(parts[0]).\(parts[1])."
        }()
        // Vendors with many unrelated products — broad vendor-prefix match would over-reach.
        let multiProductVendors: Set<String> = ["google", "microsoft", "adobe", "apple", "amazon", "meta", "facebook"]
        let useBroadVendor = !multiProductVendors.contains(vendor)
        let systemCategories: Set<String> = ["Privileged Helpers", "LaunchDaemons", "LaunchAgents (System)", "LaunchAgents (User)"]
        let appSize = directorySize(at: app.bundleURL)
        var items: [LeftoverItem] = []

        for (dir, category) in searchDirs {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                let lower = entry.lowercased()
                let entryNoExt = (entry as NSString).deletingPathExtension.lowercased()
                let bundleMatch = !bundleLower.isEmpty
                    && (lower == bundleLower
                        || lower.hasPrefix("\(bundleLower).")
                        || lower.hasPrefix("\(bundleLower)-")
                        || (bundleLower.count >= 8 && lower.contains(bundleLower)))
                let nameMatch = !nameLower.isEmpty && entryNoExt == nameLower
                let namePrefixMatch = !nameLower.isEmpty && nameLower.count >= 4
                    && (lower.hasPrefix("\(nameLower)_") || lower.hasPrefix("\(nameLower)-") || lower.hasPrefix("\(nameLower)."))
                let teamIDNameMatch = !nameLower.isEmpty && nameLower.count >= 4
                    && isTeamIDPrefixed(lower, suffix: ".\(nameLower)")
                let concatMatch = useConcatMatch && lower.contains(concatName)
                let groupMatch = lower.hasPrefix("group.")
                    && ((!vendor.isEmpty && vendor.count >= 4 && lower.contains(vendor))
                        || (!nameLower.isEmpty && nameLower.count >= 4 && lower.contains(nameLower)))
                let vendorMatch = !vendorPrefix.isEmpty && lower.hasPrefix(vendorPrefix)
                    && (useBroadVendor || systemCategories.contains(category))
                let matches = bundleMatch || nameMatch || namePrefixMatch || teamIDNameMatch || concatMatch || groupMatch || vendorMatch
                if matches {
                    let fullURL = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                    let size = directorySize(at: fullURL)
                    items.append(LeftoverItem(url: fullURL, category: category, sizeBytes: size))
                }
            }
        }
        // Vendor-nested scan: com.google.Chrome → look in .../Application Support/Google/ for "Chrome"
        if let vendor = vendorToken(from: app.bundleID) {
            let vendorRoots = [
                "\(home)/Library/Application Support",
                "\(home)/Library/Caches",
                "\(home)/Library",
                "/Library/Application Support",
                "/Library",
            ]
            for root in vendorRoots {
                guard let tops = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
                guard let vendorDir = tops.first(where: { $0.lowercased() == vendor }) else { continue }
                let vendorPath = "\(root)/\(vendorDir)"
                guard let inner = try? FileManager.default.contentsOfDirectory(atPath: vendorPath) else { continue }
                for entry in inner {
                    let lower = entry.lowercased()
                    let entryNoExt = (entry as NSString).deletingPathExtension.lowercased()
                    let nameHit = !nameLower.isEmpty && entryNoExt == nameLower
                    let concatHit = useConcatMatch && lower.contains(concatName)
                    let bundleHit = !bundleLower.isEmpty
                        && (lower == bundleLower || lower.hasPrefix("\(bundleLower)."))
                    if nameHit || concatHit || bundleHit {
                        let fullURL = URL(fileURLWithPath: vendorPath).appendingPathComponent(entry)
                        let size = directorySize(at: fullURL)
                        items.append(LeftoverItem(url: fullURL, category: "Vendor (\(vendorDir))", sizeBytes: size))
                    }
                }
            }
        }

        // Deep name scan: some apps store under vendor/company folder whose name doesn't match bundleID vendor.
        // Look one level deep under these roots for entries matching the app display name.
        if !nameLower.isEmpty && nameLower.count >= 4 {
            let deepRoots = [
                "\(home)/Library/Application Support",
                "/Library/Application Support",
                "\(home)/Library/Caches",
            ]
            let seen = Set(items.map { $0.url.path })
            for root in deepRoots {
                guard let tops = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
                for top in tops {
                    let subPath = "\(root)/\(top)"
                    var isDir: ObjCBool = false
                    guard FileManager.default.fileExists(atPath: subPath, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard let inner = try? FileManager.default.contentsOfDirectory(atPath: subPath) else { continue }
                    for entry in inner {
                        let entryNoExt = (entry as NSString).deletingPathExtension.lowercased()
                        if entryNoExt == nameLower {
                            let fullURL = URL(fileURLWithPath: subPath).appendingPathComponent(entry)
                            guard !seen.contains(fullURL.path) else { continue }
                            let size = directorySize(at: fullURL)
                            items.append(LeftoverItem(url: fullURL, category: "Vendor (\(top))", sizeBytes: size))
                        }
                    }
                }
            }
        }

        items.sort { $0.sizeBytes > $1.sizeBytes }
        items.insert(LeftoverItem(url: app.bundleURL, category: "Application", sizeBytes: appSize), at: 0)
        return items
    }

    static func scanProjects(roots: [URL]) -> [LeftoverItem] {
        var all: [LeftoverItem] = []
        for root in roots {
            all.append(contentsOf: scanProjects(root: root))
        }
        return all.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func scanProjects(root: URL) -> [LeftoverItem] {
        let throwaway: Set<String> = [
            "node_modules",
            ".next", ".nuxt", ".svelte-kit",
            "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
            ".gradle", ".parcel-cache", ".turbo", ".vite", ".cache",
            "DerivedData",
            "bower_components",
        ]
        var items: [LeftoverItem] = []
        let fm = FileManager.default

        func walk(_ dir: URL) {
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return }
            for entry in entries {
                let vals = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard vals?.isDirectory == true, vals?.isSymbolicLink != true else { continue }
                let name = entry.lastPathComponent
                if throwaway.contains(name) {
                    items.append(LeftoverItem(url: entry, category: "Project: \(name)", sizeBytes: directorySize(at: entry)))
                    continue
                }
                if name == "target", isLikelyRustTarget(entry) {
                    items.append(LeftoverItem(url: entry, category: "Project: target (Rust)", sizeBytes: directorySize(at: entry)))
                    continue
                }
                if name == ".build", isLikelySwiftBuild(entry) {
                    items.append(LeftoverItem(url: entry, category: "Project: .build (Swift)", sizeBytes: directorySize(at: entry)))
                    continue
                }
                walk(entry)
            }
        }
        walk(root)
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func isLikelyRustTarget(_ url: URL) -> Bool {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.appendingPathComponent("Cargo.toml").path) { return true }
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return false }
        let markers: Set<String> = ["debug", "release", "doc", "rust-analyzer", ".rustc_info.json", "CACHEDIR.TAG"]
        return !markers.isDisjoint(with: Set(contents))
    }

    private static func isLikelySwiftBuild(_ url: URL) -> Bool {
        let fm = FileManager.default
        let parent = url.deletingLastPathComponent()
        if fm.fileExists(atPath: parent.appendingPathComponent("Package.swift").path) { return true }
        guard let contents = try? fm.contentsOfDirectory(atPath: url.path) else { return false }
        let markers: Set<String> = ["checkouts", "workspace-state.json", "artifacts", "repositories", "arm64-apple-macosx", "x86_64-apple-macosx"]
        return !markers.isDisjoint(with: Set(contents))
    }

    static func scanSystem() -> [LeftoverItem] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var roots: [(String, String)] = [
            ("\(home)/Library/Caches",                  "User Caches"),
            ("/Library/Caches",                         "System Caches"),
            ("\(home)/Library/Logs",                    "User Logs"),
            ("/Library/Logs",                           "System Logs"),
            ("\(home)/Library/Logs/DiagnosticReports",  "Diagnostic Reports"),
            ("/Library/Logs/DiagnosticReports",         "Diagnostic Reports (System)"),
        ]
        let tmp = NSTemporaryDirectory()
        let base = (tmp as NSString).deletingLastPathComponent
        if !base.isEmpty {
            roots.append(("\(base)/T", "Darwin Temp"))
            roots.append(("\(base)/C", "Darwin Cache"))
            roots.append(("\(base)/X", "Darwin CodeSign"))
        }
        var items: [LeftoverItem] = []
        for (dir, category) in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(entry)
                let size = directorySize(at: url)
                items.append(LeftoverItem(url: url, category: category, sizeBytes: size))
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func runningBundleIDs() -> Set<String> {
        Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
    }

    static func markRunning(_ items: [LeftoverItem], running: Set<String>) -> [LeftoverItem] {
        guard !running.isEmpty else { return items }
        return items.map { item in
            var it = item
            let name = item.url.lastPathComponent.lowercased()
            let noExt = (name as NSString).deletingPathExtension
            for bid in running {
                if noExt == bid
                    || noExt.hasPrefix("\(bid).")
                    || noExt.hasPrefix("\(bid)-")
                    || name.contains(bid) {
                    it.isRunning = true
                    break
                }
            }
            return it
        }
    }

    static func hasFullDiskAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        // ~/Library/Safari and ~/Library/Mail require FDA on macOS Mojave+.
        // Probe either — return true if any existing one is listable.
        for probe in ["\(home)/Library/Safari", "\(home)/Library/Mail"] {
            if FileManager.default.fileExists(atPath: probe) {
                return (try? FileManager.default.contentsOfDirectory(atPath: probe)) != nil
            }
        }
        return false  // Inconclusive — assume no; a banner will still be shown, user can dismiss.
    }

    private static func isTeamIDPrefixed(_ entry: String, suffix: String) -> Bool {
        guard entry.hasSuffix(suffix) else { return false }
        let prefix = entry.dropLast(suffix.count)
        return prefix.count == 10 && prefix.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private static func vendorToken(from bundleID: String) -> String? {
        let parts = bundleID.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return nil }
        let v = String(parts[1])
        let skip: Set<String> = ["apple", "app", "application", "example"]
        return skip.contains(v) ? nil : v
    }

    static func directorySize(at url: URL) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            return (attrs?[.size] as? Int64) ?? 0
        }
        var total: Int64 = 0
        let seen = NSMutableSet()
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey, .fileResourceIdentifierKey]
        if let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys, options: []) {
            for case let fileURL as URL in enumerator {
                guard let values = try? fileURL.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true,
                      let size = values.fileSize else { continue }
                if let fid = values.fileResourceIdentifier {
                    if seen.contains(fid) { continue }
                    seen.add(fid)
                }
                total += Int64(size)
            }
        }
        return total
    }
}
