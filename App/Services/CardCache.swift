import Foundation
import CNSNNCore

/// Approved community cards kept on this device with the catalogue version they came with
/// (`meta/cards`), so the app downloads them again only when a moderator changed something.
struct CardCache: Codable {
    var version: Int
    var savedAt: Date
    var cards: [Card]

    /// Up to date when the server's version is the cached one. A catalogue without a version yet
    /// (no moderation since this feature) is refreshed once a day.
    func isCurrent(version server: Int?) -> Bool {
        guard let server else { return version == 0 && Date().timeIntervalSince(savedAt) < 24 * 3600 }
        return server == version
    }

    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("cnsnn-cards-v1.json")
    }
    static func load() -> CardCache? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CardCache.self, from: data)
    }
    static func save(_ cache: CardCache) {
        guard let url, let data = try? JSONEncoder().encode(cache) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
