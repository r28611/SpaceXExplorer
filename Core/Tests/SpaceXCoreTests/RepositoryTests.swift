import XCTest
@testable import SpaceXCore

struct StubService: SpaceXService {
    var action: @Sendable (LaunchFilter, Int, Int) async throws -> Page<Launch>
    func launches(filter: LaunchFilter, page: Int, size: Int) async throws -> Page<Launch> {
        try await action(filter, page, size)
    }
    func rockets(page: Int, size: Int) async throws -> Page<Rocket> { throw AppError.offline }
    func rocket(id: String) async throws -> Rocket { throw AppError.offline }
}

private actor PageResponseGate<Item: Codable & Sendable> {
    private var continuation: CheckedContinuation<Page<Item>, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func response() async -> Page<Item> {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observers.forEach { $0.resume() }
            observers.removeAll()
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func resolve(_ response: Page<Item>) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private struct RocketStubService: SpaceXService {
    let action: @Sendable (Int, Int) async throws -> Page<Rocket>
    func launches(filter: LaunchFilter, page: Int, size: Int) async throws -> Page<Launch> { throw AppError.offline }
    func rockets(page: Int, size: Int) async throws -> Page<Rocket> { try await action(page, size) }
    func rocket(id: String) async throws -> Rocket { throw AppError.offline }
}

final class RepositoryTests: XCTestCase, @unchecked Sendable {
    private func directory() -> URL { FileManager.default.temporaryDirectory.appending(path: UUID().uuidString) }

    func testAutomaticFallsBackToLabeledDemoWithoutCachingIt() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let repository = SpaceXRepository(live: StubService { _, _, _ in throw AppError.http(525) }, cache: cache)
        let value = try await repository.launches(filter: .init(), page: 1, size: 8)
        XCTAssertEqual(value.source, .demo)
        XCTAssertNotNil(value.notice)
        let cached = await repository.cachedLaunches(filter: .init(), size: 8)
        XCTAssertNil(cached)
    }

    func testLiveModeNeverFallsBack() async throws {
        let repository = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline },
                                         cache: DiskCache(directory: directory()), mode: .live)
        do {
            _ = try await repository.launches(filter: .init(), page: 1, size: 8)
            XCTFail("Expected live-only failure")
        } catch { XCTAssertEqual(error as? AppError, .offline) }
    }

    func testDecodingFailureIsNotHiddenByDemo() async throws {
        let repository = SpaceXRepository(live: StubService { _, _, _ in throw AppError.decoding },
                                         cache: DiskCache(directory: directory()))
        do {
            _ = try await repository.launches(filter: .init(), page: 1, size: 8)
            XCTFail("Expected decoding failure")
        } catch { XCTAssertEqual(error as? AppError, .decoding) }
    }

    func testLivePageTwoFailureCannotSwitchToDemo() async throws {
        let repository = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline },
                                         cache: DiskCache(directory: directory()))
        do {
            _ = try await repository.launches(filter: .init(), page: 2, size: 8, source: .live)
            XCTFail("Expected page failure")
        } catch { XCTAssertEqual(error as? AppError, .offline) }
    }

    func testDemoPaginationNeverCallsLiveService() async throws {
        let repository = SpaceXRepository(live: StubService { _, _, _ in
            XCTFail("Demo pagination must not call network"); throw AppError.offline
        }, cache: DiskCache(directory: directory()))
        let result = try await repository.launches(filter: .init(), page: 2, size: 8, source: .demo)
        XCTAssertEqual(result.source, .demo)
        XCTAssertEqual(result.value.items.count, 8)
    }

    func testSavedLiveDataSurvivesNewRepositoryAndOfflineFailure() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let service = StubService { filter, page, size in
            try await FixtureService().launches(filter: filter, page: page, size: size)
        }
        let timestamp = Date(timeIntervalSince1970: 1000)
        let first = SpaceXRepository(live: service, cache: DiskCache(directory: url), now: { timestamp })
        let saved = try await first.launches(filter: .init(), page: 1, size: 8)
        let second = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline }, cache: DiskCache(directory: url))
        let result = try await second.launches(filter: .init(), page: 1, size: 8)
        XCTAssertEqual(result.value.items, saved.value.items)
        XCTAssertEqual(result.source, .live)
        XCTAssertTrue(result.isCached)
        XCTAssertEqual(result.fetchedAt, timestamp)
        XCTAssertNotNil(result.notice)
        let otherQuery = await second.cachedLaunches(filter: .init(period: .upcoming), size: 8)
        XCTAssertNil(otherQuery)
    }

    func testRefreshingFirstPageInvalidatesOldLaterPages() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let service = StubService { filter, page, size in try await FixtureService().launches(filter: filter, page: page, size: size) }
        let repository = SpaceXRepository(live: service, cache: cache)
        _ = try await repository.launches(filter: .init(), page: 2, size: 8, source: .live)
        _ = try await repository.launches(filter: .init(), page: 1, size: 8)
        let offline = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline }, cache: cache, mode: .live)
        do {
            _ = try await offline.launches(filter: .init(), page: 2, size: 8, source: .live)
            XCTFail("Old second page must have been invalidated")
        } catch { XCTAssertEqual(error as? AppError, .offline) }
    }

    func testOldPageCannotRepopulateCacheAfterRefresh() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let gate = PageResponseGate<Launch>()
        let first = try await FixtureService().launches(filter: .init(), page: 1, size: 8)
        let oldSecond = try await FixtureService().launches(filter: .init(), page: 2, size: 8)
        let service = StubService { _, page, _ in
            if page == 2 { return await gate.response() }
            return first
        }
        let repository = SpaceXRepository(live: service, cache: cache)
        _ = try await repository.launches(filter: .init(), page: 1, size: 8)
        let oldRequest = Task { try await repository.launches(filter: .init(), page: 2, size: 8, source: .live) }
        await gate.waitUntilStarted()
        _ = try await repository.launches(filter: .init(), page: 1, size: 8)
        await gate.resolve(oldSecond)
        do { _ = try await oldRequest.value }
        catch { XCTAssertTrue(error is CancellationError) }

        let offline = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline }, cache: cache, mode: .live)
        do {
            _ = try await offline.launches(filter: .init(), page: 2, size: 8, source: .live)
            XCTFail("An obsolete second page survived first-page cache invalidation")
        } catch { XCTAssertEqual(error as? AppError, .offline) }
        let savedFirst = await offline.cachedLaunches(filter: .init(), size: 8)
        XCTAssertEqual(savedFirst?.value.items, first.items)
    }

    func testOlderFirstPageCannotOverwriteNewerRefresh() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let gate = PageResponseGate<Launch>()
        let old = try await FixtureService().launches(filter: .init(), page: 1, size: 8)
        let fresh = Page<Launch>(items: [], nextPage: nil, total: 0)
        // Separate repositories sharing the cache also share its query generations.
        let slow = SpaceXRepository(live: StubService { _, _, _ in await gate.response() }, cache: cache)
        let fast = SpaceXRepository(live: StubService { _, _, _ in fresh }, cache: cache)
        let oldRequest = Task { try await slow.launches(filter: .init(), page: 1, size: 8) }
        await gate.waitUntilStarted()
        _ = try await fast.launches(filter: .init(), page: 1, size: 8)
        await gate.resolve(old)
        do { _ = try await oldRequest.value }
        catch { XCTAssertTrue(error is CancellationError) }
        let saved = await fast.cachedLaunches(filter: .init(), size: 8)
        XCTAssertEqual(saved?.value.items, [])
    }

    func testFailedRefreshPreservesExistingCachedPageChain() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let repository = SpaceXRepository(live: FixtureService(), cache: cache)
        _ = try await repository.launches(filter: .init(), page: 1, size: 8)
        let second = try await repository.launches(filter: .init(), page: 2, size: 8, source: .live)
        let offline = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline }, cache: cache, mode: .live)
        _ = try await offline.launches(filter: .init(), page: 1, size: 8)
        let savedSecond = try await offline.launches(filter: .init(), page: 2, size: 8, source: .live)
        XCTAssertTrue(savedSecond.isCached)
        XCTAssertEqual(savedSecond.value.items, second.value.items)
    }

    func testRefreshOfAnotherFilterDoesNotInvalidateInFlightPage() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let gate = PageResponseGate<Launch>()
        let second = try await FixtureService().launches(filter: .init(), page: 2, size: 8)
        let service = StubService { filter, page, size in
            if filter.period == .all, page == 2 { return await gate.response() }
            return try await FixtureService().launches(filter: filter, page: page, size: size)
        }
        let repository = SpaceXRepository(live: service, cache: cache)
        let pending = Task { try await repository.launches(filter: .init(), page: 2, size: 8, source: .live) }
        await gate.waitUntilStarted()
        _ = try await repository.launches(filter: .init(period: .upcoming), page: 1, size: 8)
        await gate.resolve(second)
        _ = try await pending.value
        let offline = SpaceXRepository(live: StubService { _, _, _ in throw AppError.offline }, cache: cache, mode: .live)
        let saved = try await offline.launches(filter: .init(), page: 2, size: 8, source: .live)
        XCTAssertEqual(saved.value.items, second.items)
        XCTAssertTrue(saved.isCached)
    }

    func testObsoleteRocketPageCannotCachePagesOrDetailRecords() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        let gate = PageResponseGate<Rocket>()
        let first = try await FixtureService().rockets(page: 1, size: 2)
        let second = try await FixtureService().rockets(page: 2, size: 2)
        let service = RocketStubService { page, _ in
            if page == 2 { return await gate.response() }
            return first
        }
        let repository = SpaceXRepository(live: service, cache: cache)
        _ = try await repository.rockets(page: 1, size: 2)
        let pending = Task { try await repository.rockets(page: 2, size: 2, source: .live) }
        await gate.waitUntilStarted()
        _ = try await repository.rockets(page: 1, size: 2)
        await gate.resolve(second)
        do { _ = try await pending.value }
        catch { XCTAssertTrue(error is CancellationError) }
        let savedPage = await cache.read(Page<Rocket>.self, key: "rockets/2/2")
        XCTAssertNil(savedPage)
        for rocket in second.items {
            let savedDetail = await repository.cachedRocket(id: rocket.id, source: .live)
            XCTAssertNil(savedDetail)
        }
        let currentDetail = await repository.cachedRocket(id: first.items[0].id, source: .live)
        XCTAssertEqual(currentDetail?.value, first.items[0])
    }

    func testCacheCorruptionBecomesMiss() async throws {
        let url = directory(); defer { try? FileManager.default.removeItem(at: url) }
        let cache = DiskCache(directory: url)
        await cache.write("value", key: "test", date: .now)
        let files = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
        try Data("broken".utf8).write(to: XCTUnwrap(files.first))
        let result = await cache.read(String.self, key: "test")
        XCTAssertNil(result)
    }

    func testCancellationDoesNotFallback() async throws {
        let repository = SpaceXRepository(live: StubService { _, _, _ in throw CancellationError() },
                                         cache: DiskCache(directory: directory()))
        do {
            _ = try await repository.launches(filter: .init(), page: 1, size: 8)
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }
}
