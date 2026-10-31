import Foundation
import CNSNNCore

/// A Sprint, Survie or Double sens game in progress, saved on this device after every move so that
/// closing the app never loses it. Never synced: only finished games become records.
struct ModeRun: Codable {
    var mode: PlayMode
    var sprint: SprintGame?
    var survival: SurvivalGame?
    var duo: DuoGame?
    /// Game time when saved, and the wall clock then: a game reopened later goes on from there,
    /// the time away included (the Sprint and Double sens clocks never stop).
    var elapsedMs: Int
    var savedAt: Date

    var finished: Bool { sprint?.finished ?? survival?.finished ?? duo?.finished ?? true }
    /// The elapsed time once reopened.
    var resumedElapsedMs: Int { elapsedMs + max(0, Int(Date().timeIntervalSince(savedAt) * 1000)) }
}

/// Games in progress and the cards seen lately (so a new game draws other ones), on this device only.
enum ModeRunStore {
    private static var memory: [String: Data] = [:]
    private static func data(_ key: String) -> Data? { RuntimeFlags.isTesting ? memory[key] : UserDefaults.standard.data(forKey: key) }
    private static func set(_ value: Data?, _ key: String) {
        if RuntimeFlags.isTesting { memory[key] = value } else { UserDefaults.standard.set(value, forKey: key) }
    }
    private static func key(_ mode: PlayMode) -> String { "cnsnn.run." + mode.rawValue }

    static func load(_ mode: PlayMode) -> ModeRun? {
        guard let data = data(key(mode)) else { return nil }
        return try? JSONDecoder().decode(ModeRun.self, from: data)
    }
    static func save(_ run: ModeRun) { set(try? JSONEncoder().encode(run), key(run.mode)) }
    static func clear(_ mode: PlayMode) { set(nil, key(mode)) }
    /// Modes with a game to pick up (Survie, Double sens).
    static func inProgress() -> Set<PlayMode> { Set(PlayMode.allCases.filter { $0 != .sprint && load($0).map { !$0.finished } == true }) }
    static func clearAll() { PlayMode.allCases.forEach(clear) }

    /// Cards (Sprint, Survie) or duos (Double sens) played lately, newest last.
    static func recent(_ mode: PlayMode) -> [String] {
        guard let data = data("cnsnn.recent." + (mode == .duo ? "duo" : "cards")) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }
    static func remember(_ ids: [String], mode: PlayMode) {
        let limit = mode == .duo ? 20 : 1000
        var list = recent(mode).filter { !ids.contains($0) } + ids
        list = Array(list.suffix(limit))
        set(try? JSONEncoder().encode(list), "cnsnn.recent." + (mode == .duo ? "duo" : "cards"))
    }

    /// One id per installation: each device counts its own games, so merging never adds a game twice.
    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: "cnsnn.deviceID") { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: "cnsnn.deviceID")
        return id
    }
}
