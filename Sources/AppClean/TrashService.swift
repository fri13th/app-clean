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
    static func adminDelete(_ urls: [URL], completion: @escaping (Bool, String?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            // Write paths to a temp file to avoid ARG_MAX / AppleScript length limits.
            let tmpPath = "/tmp/appclean-paths-\(UUID().uuidString)"
            let listing = urls.map { $0.path }.joined(separator: "\n")
            do {
                try listing.write(toFile: tmpPath, atomically: true, encoding: .utf8)
            } catch {
                DispatchQueue.main.async { completion(false, "Failed to prepare delete list: \(error.localizedDescription)") }
                return
            }

            // Escape tmpPath for AppleScript string
            let tmpEscaped = tmpPath
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let shellCmd = "while IFS= read -r p; do rm -rf \\\"$p\\\"; done < \\\"\(tmpEscaped)\\\"; rm -f \\\"\(tmpEscaped)\\\""
            let script = "do shell script \"\(shellCmd)\" with administrator privileges"

            let task = Process()
            task.launchPath = "/usr/bin/osascript"
            task.arguments = ["-e", script]
            let stderr = Pipe()
            task.standardError = stderr
            do {
                try task.run()
                task.waitUntilExit()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                let errMsg = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                try? FileManager.default.removeItem(atPath: tmpPath)
                let ok = task.terminationStatus == 0
                DispatchQueue.main.async {
                    if ok {
                        completion(true, nil)
                    } else if errMsg.contains("-128") || errMsg.lowercased().contains("user canceled") {
                        completion(false, "Cancelled.")
                    } else {
                        completion(false, errMsg.isEmpty ? "Exit code \(task.terminationStatus)" : errMsg)
                    }
                }
            } catch {
                try? FileManager.default.removeItem(atPath: tmpPath)
                DispatchQueue.main.async { completion(false, error.localizedDescription) }
            }
        }
    }
}
