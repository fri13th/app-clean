import AppKit
import Foundation

enum TrashService {
    static func recycle(_ urls: [URL], completion: @escaping (Result<[URL], Error>) -> Void) {
        NSWorkspace.shared.recycle(urls) { trashedFiles, error in
            if let error = error {
                completion(.failure(error))
            } else {
                completion(.success(Array(trashedFiles.values)))
            }
        }
    }
}
