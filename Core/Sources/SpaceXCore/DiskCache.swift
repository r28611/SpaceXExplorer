import CryptoKit
import Foundation
import OSLog

/// Disposable, bounded snapshots; never the source of truth for the whole dataset.
public actor DiskCache {
    private let directory: URL
    private let limit: Int
    private let logger = Logger(subsystem: "SpaceXExplorer", category: "Cache")
    private var pageGenerations: [String: UUID] = [:]

    struct PageRequest: Sendable {
        let prefix: String
        let generation: UUID
    }
    private struct Record: Codable {
        let version: Int
        let key: String
        let date: Date
        let data: Data
    }

    public init(directory: URL, limit: Int = 100) {
        self.directory = directory
        self.limit = max(1, limit)
    }

    /// Starting a refresh obsoletes in-flight writes, but keeps saved pages for failure recovery.
    func beginPageRequest(prefix: String, refreshing: Bool) -> PageRequest {
        let generation: UUID
        if !refreshing, let current = pageGenerations[prefix] {
            generation = current
        } else {
            generation = UUID()
            pageGenerations[prefix] = generation
        }
        return PageRequest(prefix: prefix, generation: generation)
    }

    func isCurrent(_ request: PageRequest) -> Bool {
        pageGenerations[request.prefix] == request.generation
    }

    /// Validation, invalidation, and persistence run in one actor turn, with no suspension point.
    func writePage<Value: Codable & Sendable>(_ value: Value, key: String, date: Date,
                                              request: PageRequest, replacingPages: Bool) -> Bool {
        guard !Task.isCancelled, isCurrent(request) else { return false }
        if replacingPages { invalidate(prefix: request.prefix) }
        write(value, key: key, date: date)
        return true
    }

    /// Rocket detail records derived from a page must obey the same generation as that page.
    func writeIfCurrent<Value: Codable & Sendable>(_ value: Value, key: String, date: Date,
                                                   request: PageRequest) {
        guard !Task.isCancelled, isCurrent(request) else { return }
        write(value, key: key, date: date)
    }

    public func read<Value: Codable & Sendable>(_ type: Value.Type, key: String) -> Snapshot<Value>? {
        let url = file(key)
        do {
            let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: url))
            guard record.version == 1, record.key == key else { return nil }
            let value = try JSONDecoder().decode(type, from: record.data)
            return Snapshot(value: value, source: .live, fetchedAt: record.date, isCached: true)
        } catch {
            // Corrupt and missing cache entries are cache misses, not screen failures.
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }

    public func write<Value: Codable & Sendable>(_ value: Value, key: String, date: Date) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let record = Record(version: 1, key: key, date: date, data: try JSONEncoder().encode(value))
            try JSONEncoder().encode(record).write(to: file(key), options: .atomic)
            let files = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
                .filter { $0.pathExtension == "json" }
                .sorted { modificationDate($0) > modificationDate($1) }
            var bytes = 0
            for (index, url) in files.enumerated() {
                bytes += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                if index >= limit || bytes > 10_000_000 { try? FileManager.default.removeItem(at: url) }
            }
        } catch {
            logger.error("Snapshot persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func invalidate(prefix: String) {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for url in files where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let record = try? JSONDecoder().decode(Record.self, from: data),
                  record.key.hasPrefix(prefix) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func file(_ key: String) -> URL {
        directory.appending(path: Self.digest(key) + ".json")
    }
    private func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
    static func digest(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
