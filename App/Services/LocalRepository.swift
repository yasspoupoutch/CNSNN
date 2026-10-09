import Foundation
import CNSNNCore

protocol ProgressRepository {
    func load() throws -> CNSNNCore.Progress
    func save(_ progress: CNSNNCore.Progress) throws
}
struct LocalRepository: ProgressRepository {
    var scope: String = "guest"
    var directoryOverride: URL?
    private var url: URL {
        get throws {
            let directory = try directoryOverride ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let safeScope = scope.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            return directory.appendingPathComponent("cnsnn-progress-v1-\(safeScope).json")
        }
    }
    func load() throws -> CNSNNCore.Progress {
        let file = try url
        guard FileManager.default.fileExists(atPath: file.path) else { return CNSNNCore.Progress() }
        return try JSONDecoder().decode(CNSNNCore.Progress.self, from: Data(contentsOf: file))
    }
    func save(_ progress: CNSNNCore.Progress) throws {
        try JSONEncoder().encode(progress).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

struct MemoryRepository: ProgressRepository {
    func load() throws -> CNSNNCore.Progress { CNSNNCore.Progress() }
    func save(_ progress: CNSNNCore.Progress) throws {}
}

enum RuntimeFlags {
    static var isTesting: Bool {
        ProcessInfo.processInfo.arguments.contains("--uitesting") || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
