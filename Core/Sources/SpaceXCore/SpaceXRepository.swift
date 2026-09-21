import Foundation

public actor SpaceXRepository {
    private let live: any SpaceXService
    private let demo: any SpaceXService
    private let cache: DiskCache
    private let mode: DataMode
    private let now: @Sendable () -> Date

    public init(live: any SpaceXService = APIClient(), demo: any SpaceXService = FixtureService(),
                cache: DiskCache, mode: DataMode = .automatic, now: @escaping @Sendable () -> Date = { .now }) {
        self.live = live
        self.demo = demo
        self.cache = cache
        self.mode = mode
        self.now = now
    }

    public func cachedLaunches(filter: LaunchFilter, size: Int) async -> Snapshot<Page<Launch>>? {
        guard mode != .demo else { return nil }
        return await cache.read(Page<Launch>.self, key: launchPrefix(filter, size: size) + "1")
    }

    public func launches(filter: LaunchFilter, page: Int, size: Int,
                         source: DataSource? = nil) async throws -> Snapshot<Page<Launch>> {
        let prefix = launchPrefix(filter, size: size)
        return try await fetch(key: prefix + String(page), invalidate: page == 1 ? prefix : nil,
                               source: source, allowDemo: page == 1) { service in
            try await service.launches(filter: filter, page: page, size: size)
        }
    }

    public func cachedRockets(size: Int) async -> Snapshot<Page<Rocket>>? {
        guard mode != .demo else { return nil }
        return await cache.read(Page<Rocket>.self, key: "rockets/\(size)/1")
    }

    public func rockets(page: Int, size: Int, source: DataSource? = nil) async throws -> Snapshot<Page<Rocket>> {
        let prefix = "rockets/\(size)/"
        let result: Snapshot<Page<Rocket>> = try await fetch(
            key: prefix + String(page), invalidate: page == 1 ? prefix : nil,
            source: source, allowDemo: page == 1) { service in
                try await service.rockets(page: page, size: size)
            }
        if result.source == .live, !result.isCached {
            for rocket in result.value.items { await cache.write(rocket, key: "rocket/\(rocket.id)", date: result.fetchedAt) }
        }
        return result
    }

    public func cachedRocket(id: String, source: DataSource) async -> Snapshot<Rocket>? {
        guard source == .live else { return nil }
        return await cache.read(Rocket.self, key: "rocket/\(id)")
    }

    public func rocket(id: String, source: DataSource) async throws -> Snapshot<Rocket> {
        try await fetch(key: "rocket/\(id)", source: source, allowDemo: false) { service in
            try await service.rocket(id: id)
        }
    }

    private func fetch<Value: Codable & Sendable>(
        key: String, invalidate prefix: String? = nil, source: DataSource?, allowDemo: Bool,
        operation: @Sendable (any SpaceXService) async throws -> Value
    ) async throws -> Snapshot<Value> {
        if source == .demo || mode == .demo {
            return Snapshot(value: try await operation(demo), source: .demo, fetchedAt: now())
        }
        do {
            let value = try await operation(live)
            try Task.checkCancellation()
            let date = now()
            if let prefix { await cache.invalidate(prefix: prefix) }
            await cache.write(value, key: key, date: date)
            return Snapshot(value: value, source: .live, fetchedAt: date)
        } catch is CancellationError { throw CancellationError() }
        catch {
            try Task.checkCancellation()
            if let cached = await cache.read(Value.self, key: key) {
                return Snapshot(value: cached.value, source: .live, fetchedAt: cached.fetchedAt,
                                isCached: true, notice: error.localizedDescription)
            }
            // Never mask a contract/decoding defect or switch sources partway through pagination.
            guard mode == .automatic, source == nil, allowDemo,
                  let failure = error as? AppError, failure.permitsFallback else { throw error }
            return Snapshot(value: try await operation(demo), source: .demo, fetchedAt: now(),
                            notice: "Live API unavailable. Showing local sample data.")
        }
    }

    private func launchPrefix(_ filter: LaunchFilter, size: Int) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key = (try? encoder.encode(filter)).flatMap { String(data: $0, encoding: .utf8) } ?? "default"
        return "launches/\(DiskCache.digest(key))/\(size)/"
    }
}
