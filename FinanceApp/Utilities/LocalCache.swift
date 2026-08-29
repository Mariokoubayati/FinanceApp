import Foundation

// Lightweight JSON file cache for offline resilience.
// ViewModels call save() after a successful fetch and load() on startup.
final class LocalCache {
    static let shared = LocalCache()
    private init() {}

    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url  = base.appendingPathComponent("FinanceCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private func fileURL(key: String) -> URL {
        dir.appendingPathComponent("\(key).json")
    }

    func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: fileURL(key: key), options: .atomic)
    }

    func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = try? Data(contentsOf: fileURL(key: key)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    func clear(key: String) {
        try? FileManager.default.removeItem(at: fileURL(key: key))
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: dir)
    }
}
