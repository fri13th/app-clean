import SwiftUI
import UniformTypeIdentifiers
import AppKit

enum ScanTab: String, CaseIterable, Identifiable {
    case uninstall = "Uninstall App"
    case system = "System Cleanup"
    case projects = "Dev Projects"
    var id: String { rawValue }
}

struct ContentView: View {
    @State private var tab: ScanTab = .uninstall
    @State private var appInfo: AppInfo?
    @State private var items: [LeftoverItem] = []
    @State private var selected: Set<UUID> = []
    @State private var isTargeted = false
    @State private var statusMessage: String?
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appInfo != nil {
                resultsView
            } else {
                Picker("Mode", selection: $tab) {
                    ForEach(ScanTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                tabContent
            }
        }
    }

    private var header: some View {
        HStack {
            Text("App Clean").font(.title2).bold()
            Spacer()
            if appInfo != nil {
                Button("Cancel") { reset() }
            }
        }
        .padding()
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .uninstall: appDropZone
        case .system: systemView
        case .projects: projectDropZone
        }
    }

    private var appDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.slash")
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(.secondary)
            Text("Drop a .app here").font(.headline)
            Text("Finds leftover files in ~/Library and /Library").font(.caption).foregroundStyle(.secondary)
            Button("Choose .app…") { chooseApp() }
            if let msg = statusMessage {
                Text(msg).font(.callout).foregroundStyle(.green).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary)
                .padding(20)
        )
        .dropDestination(for: URL.self) { urls, _ in
            if let url = urls.first { processApp(at: url) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var systemView: some View {
        VStack(spacing: 14) {
            Image(systemName: "internaldrive")
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(.secondary)
            Text("Clean system caches & logs").font(.headline)
            Text("Scans ~/Library and /Library caches, logs, diagnostics, and Darwin temp/cache.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Scan") { scanSystem() }
                .keyboardShortcut(.defaultAction)
            if let msg = statusMessage {
                Text(msg).font(.callout).foregroundStyle(.green).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var projectDropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "folder.badge.minus")
                .resizable().scaledToFit().frame(width: 64, height: 64)
                .foregroundStyle(.secondary)
            Text("Drop a projects folder here").font(.headline)
            Text("Finds node_modules, target, .next, __pycache__, DerivedData, etc.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 40)
            Button("Choose folder…") { chooseProjectRoot() }
            if let msg = statusMessage {
                Text(msg).font(.callout).foregroundStyle(.green).padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
        .background(isTargeted ? Color.accentColor.opacity(0.15) : Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8]))
                .foregroundStyle(.secondary)
                .padding(20)
        )
        .dropDestination(for: URL.self) { urls, _ in
            if !urls.isEmpty { scanProjects(at: urls) }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    @ViewBuilder
    private var resultsView: some View {
        VStack(spacing: 0) {
            if let info = appInfo {
                HStack {
                    VStack(alignment: .leading) {
                        Text(info.displayName).font(.headline)
                        if !info.bundleID.isEmpty {
                            Text(info.bundleID).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("\(items.count) items · \(totalSize)").foregroundStyle(.secondary)
                }
                .padding()
            }

            if isScanning {
                ProgressView("Scanning…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if items.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.green)
                    Text("Nothing to clean up.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items) { item in
                    HStack {
                        Image(systemName: selected.contains(item.id) ? "checkmark.square.fill" : "square")
                            .foregroundStyle(selected.contains(item.id) ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayPath).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Text(item.category).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(item.sizeFormatted).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { toggle(item.id) }
                }
            }

            Divider()
            HStack {
                Button(allSelected ? "Deselect all" : "Select all") {
                    selected = allSelected ? [] : Set(items.map { $0.id })
                }
                .disabled(items.isEmpty)
                if let msg = statusMessage {
                    Text(msg).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button("Move \(selected.count) to Trash") { moveSelectedToTrash() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected.isEmpty)
            }
            .padding()
        }
    }

    private var allSelected: Bool { !items.isEmpty && selected.count == items.count }

    private var totalSize: String {
        let bytes = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func toggle(_ id: UUID) {
        if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
    }

    private func reset() {
        appInfo = nil
        items = []
        selected = []
        statusMessage = nil
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application, .folder]
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            processApp(at: url)
        }
    }

    private func chooseProjectRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Scan"
        if panel.runModal() == .OK, !panel.urls.isEmpty {
            scanProjects(at: panel.urls)
        }
    }

    private func processApp(at url: URL) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            statusMessage = "Drop a .app or a folder."
            return
        }

        let info: AppInfo
        if url.pathExtension == "app", let read = AppScanner.readAppInfo(from: url) {
            info = read
        } else {
            var bundleID = ""
            if let entries = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil),
               let nested = entries.first(where: { $0.pathExtension == "app" }),
               let read = AppScanner.readAppInfo(from: nested) {
                bundleID = read.bundleID
            }
            info = AppInfo(bundleURL: url, bundleID: bundleID, displayName: url.lastPathComponent)
        }
        appInfo = info
        isScanning = true
        items = []
        selected = []
        statusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppScanner.scan(for: info)
            DispatchQueue.main.async {
                items = found
                selected = Set(found.map { $0.id })
                isScanning = false
                if found.isEmpty {
                    appInfo = nil
                    statusMessage = "No leftover files for \(info.displayName)."
                }
            }
        }
    }

    private func scanSystem() {
        appInfo = AppInfo(bundleURL: URL(fileURLWithPath: "/"), bundleID: "", displayName: "System Caches & Logs")
        isScanning = true
        items = []
        selected = []
        statusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppScanner.scanSystem()
            DispatchQueue.main.async {
                items = found
                selected = Set(found.map { $0.id })
                isScanning = false
                if found.isEmpty {
                    reset()
                    statusMessage = "Nothing to clean."
                }
            }
        }
    }

    private func scanProjects(at urls: [URL]) {
        let fm = FileManager.default
        let dirs = urls.filter {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
        }
        guard !dirs.isEmpty else {
            statusMessage = "Drop one or more folders."
            return
        }
        let label = dirs.count == 1
            ? "Projects: \(dirs[0].lastPathComponent)"
            : "Projects: \(dirs.count) folders"
        appInfo = AppInfo(bundleURL: dirs[0], bundleID: "", displayName: label)
        isScanning = true
        items = []
        selected = []
        statusMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let found = AppScanner.scanProjects(roots: dirs)
            DispatchQueue.main.async {
                items = found
                selected = Set(found.map { $0.id })
                isScanning = false
                if found.isEmpty {
                    reset()
                    statusMessage = "No reclaimable artifacts found."
                }
            }
        }
    }

    private func moveSelectedToTrash() {
        let toTrash = items.filter { selected.contains($0.id) }
        let urls = toTrash.map { $0.url }
        let (writable, preAdmin) = partitionByWritability(urls)

        if writable.isEmpty {
            promptAdminChoice(trashed: [], admin: preAdmin)
            return
        }

        TrashService.recycle(writable) { result in
            DispatchQueue.main.async {
                // recycle may fail silently on TCC/FDA-protected paths even though parent is writable;
                // treat those failures as needing admin.
                let admin = result.failed + preAdmin
                if admin.isEmpty {
                    finishDeletion(removed: result.succeeded)
                } else {
                    promptAdminChoice(trashed: result.succeeded, admin: admin)
                }
            }
        }
    }

    private func promptAdminChoice(trashed: [URL], admin: [URL]) {
        let alert = NSAlert()
        alert.messageText = "\(admin.count) item\(admin.count == 1 ? "" : "s") need administrator permission"
        let alreadyLine = trashed.isEmpty ? "" : "\(trashed.count) item\(trashed.count == 1 ? " was" : "s were") already moved to Trash.\n\n"
        alert.informativeText = "\(alreadyLine)These items are in protected locations (e.g. /Library, /var/db, or TCC-protected /var/folders).\n\n• Delete with admin — prompts for password; admin-deleted items are permanent (not recoverable from Trash).\n• Skip — leave them."
        alert.addButton(withTitle: "Delete with admin…")
        alert.addButton(withTitle: "Skip")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            TrashService.adminDelete(admin) { ok, err in
                DispatchQueue.main.async {
                    finishDeletion(removed: trashed + (ok ? admin : []))
                    if !ok { statusMessage = err ?? "Admin delete failed." }
                }
            }
        case .alertSecondButtonReturn:
            finishDeletion(removed: trashed)
            statusMessage = "Trashed \(trashed.count) · skipped \(admin.count) admin-only."
        default:
            finishDeletion(removed: trashed)
            if !trashed.isEmpty {
                statusMessage = "\(trashed.count) already in Trash before cancel."
            }
        }
    }

    private func partitionByWritability(_ urls: [URL]) -> (writable: [URL], needsAdmin: [URL]) {
        var writable: [URL] = []
        var needsAdmin: [URL] = []
        for url in urls {
            let parent = url.deletingLastPathComponent().path
            if access(parent, W_OK) == 0 {
                writable.append(url)
            } else {
                needsAdmin.append(url)
            }
        }
        return (writable, needsAdmin)
    }

    private func finishDeletion(removed: [URL]) {
        let removedPaths = Set(removed.map { $0.path })
        items.removeAll { removedPaths.contains($0.url.path) }
        selected = selected.intersection(Set(items.map { $0.id }))
        statusMessage = "Removed \(removed.count) items."
        if items.isEmpty { reset() }
    }
}
