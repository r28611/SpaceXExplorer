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
