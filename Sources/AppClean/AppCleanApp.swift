import SwiftUI
import AppKit

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        if let idx = args.firstIndex(of: "--scan"), idx + 1 < args.count {
            runHeadlessScan(appPath: args[idx + 1])
            return
        }
        if args.contains("--scan-system") {
            runHeadlessSystemScan()
            return
        }
        if let idx = args.firstIndex(of: "--scan-projects"), idx + 1 < args.count {
            runHeadlessProjectScan(root: args[idx + 1])
            return
        }
        AppCleanApp.main()
    }
}

private func runHeadlessScan(appPath: String) {
    let url = URL(fileURLWithPath: appPath)
    guard let info = AppScanner.readAppInfo(from: url) else {
        FileHandle.standardError.write(Data("Not a valid .app bundle: \(appPath)\n".utf8))
        exit(1)
    }
    print("App:       \(info.displayName)")
    print("BundleID:  \(info.bundleID)")
    let items = AppScanner.scan(for: info)
    let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
    print("Matches:   \(items.count)  (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))")
    for item in items {
        print("  [\(item.category)] \(item.sizeFormatted.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.url.path)")
    }
}

private func runHeadlessProjectScan(root: String) {
    let url = URL(fileURLWithPath: root)
    let items = AppScanner.scanProjects(root: url)
    let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
    print("Project scan: \(items.count) items (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))")
    for item in items {
        print("  [\(item.category)] \(item.sizeFormatted.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.url.path)")
    }
}

private func runHeadlessSystemScan() {
    let items = AppScanner.scanSystem()
    let total = items.reduce(Int64(0)) { $0 + $1.sizeBytes }
    print("System scan: \(items.count) items (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))")
    for item in items.prefix(30) {
        print("  [\(item.category)] \(item.sizeFormatted.padding(toLength: 10, withPad: " ", startingAt: 0)) \(item.url.path)")
    }
    if items.count > 30 { print("  ... and \(items.count - 30) more") }
}

struct AppCleanApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup("App Clean") {
            ContentView()
                .frame(minWidth: 720, minHeight: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
