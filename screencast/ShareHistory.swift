import Foundation

struct ShareEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let localPath: String
    let publicURL: URL
    let createdAt: Date

    var localURL: URL? {
        let url = URL(fileURLWithPath: localPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

@MainActor
final class ShareHistoryStore {
    static let shared = ShareHistoryStore()

    private let key = "screencast.shareHistory.v1"
    private let maxEntries = 50
    private(set) var entries: [ShareEntry] = []

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ShareEntry].self, from: data) else {
            entries = []
            return
        }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    @discardableResult
    func record(localURL: URL, publicURL: URL) -> ShareEntry {
        let entry = ShareEntry(
            id: UUID(),
            localPath: localURL.path,
            publicURL: publicURL,
            createdAt: Date()
        )
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        save()
        return entry
    }

    func uploadedLocalPaths() -> Set<String> {
        Set(entries.map { $0.localPath })
    }
}
