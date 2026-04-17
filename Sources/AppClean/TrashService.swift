import AppKit
import Foundation

enum TrashService {
    struct RecycleResult {
        let succeeded: [URL]
        let failed: [URL]
    }

    static func recycle(_ urls: [URL], completion: @escaping (RecycleResult) -> Void) {
        NSWorkspace.shared.recycle(urls) { trashedFiles, _ in
            let keys = Set(trashedFiles.keys.map { $0.path })
            let succeeded = urls.filter { keys.contains($0.path) }
            let failed = urls.filter { !keys.contains($0.path) }
            completion(RecycleResult(succeeded: succeeded, failed: failed))
        }
    }

    // Admin-elevated hard delete (rm -rf) via osascript. Used for items that can't be trashed
    // as the current user (e.g. /Library/..., /var/db/receipts, privileged helpers).
    static func adminDelete(_ urls: [URL], completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let quoted = urls.map { url -> String in
                let escaped = url.path
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "\"", with: "\\\"")
                return "quoted form of \"\(escaped)\""
            }.joined(separator: " & \" \" & ")
            let script = "do shell script \"rm -rf \" & \(quoted) with administrator privileges"
            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            do {
                try task.run()
                task.waitUntilExit()
                DispatchQueue.main.async { completion(task.terminationStatus == 0) }
            } catch {
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
}
