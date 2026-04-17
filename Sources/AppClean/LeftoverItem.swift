import Foundation

struct LeftoverItem: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let category: String
    let sizeBytes: Int64

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let p = url.path
        return p.hasPrefix(home) ? "~" + p.dropFirst(home.count) : p
    }

    var sizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
}
