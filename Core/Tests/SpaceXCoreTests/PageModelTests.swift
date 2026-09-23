import XCTest
@testable import SpaceXCore

private actor Gate<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?
    private var observers: [CheckedContinuation<Void, Never>] = []
    func value() async -> Value {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for observer in observers { observer.resume() }
            observers.removeAll()
        }
    }
    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { observers.append($0) }
    }
    func resolve(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
}

@MainActor
final class PageModelTests: XCTestCase {
    private func fixtures() async throws -> [Launch] {
        try await FixtureService().launches(filter: .init(), page: 1, size: 24).items
    }

    func testPaginationDeduplicatesAndRetainsRowsOnFailure() async throws {
        let values = try await fixtures()
        let model = PageModel<Launch>()
        await model.reload { _, _ in Snapshot(value: Page(items: [values[0]], nextPage: 2, total: 3), source: .live) }
        await model.loadMore { _, _ in throw AppError.offline }
        XCTAssertEqual(model.items.count, 1)
        XCTAssertNotNil(model.pageError)
        XCTAssertEqual(model.nextPage, 2)
        await model.loadMore { _, source in
            XCTAssertEqual(source, .live)
            return Snapshot(value: Page(items: [values[0], values[1]], nextPage: nil, total: 2), source: .live)
        }
        XCTAssertEqual(model.items.count, 2)
        XCTAssertNil(model.pageError)
        XCTAssertNil(model.nextPage)
    }

    func testLateResponseCannotOverwriteNewQuery() async throws {
        let values = try await fixtures()
        let model = PageModel<Launch>()
        let gate = Gate<Snapshot<Page<Launch>>>()
        let old = Task { await model.reload { _, _ in await gate.value() } }
        await gate.waitUntilStarted()
        await model.reload { _, _ in Snapshot(value: Page(items: [values[1]], nextPage: nil, total: 1), source: .demo) }
        await gate.resolve(Snapshot(value: Page(items: [values[0]], nextPage: nil, total: 1), source: .demo))
        await old.value
        XCTAssertEqual(model.items.map(\.id), [values[1].id])
        XCTAssertFalse(model.isLoading)
    }

    func testDuplicateLoadMoreCallsOnlyStartOneRequest() async throws {
        let values = try await fixtures()
        let model = PageModel<Launch>()
        await model.reload { _, _ in Snapshot(value: Page(items: [values[0]], nextPage: 2, total: 2), source: .live) }
        let gate = Gate<Snapshot<Page<Launch>>>()
        let first = Task { await model.loadMore { _, _ in await gate.value() } }
        await gate.waitUntilStarted()
        await model.loadMore { _, _ in XCTFail("Duplicate request"); throw AppError.offline }
        await gate.resolve(Snapshot(value: Page(items: [values[1]], nextPage: nil, total: 2), source: .live))
        await first.value
        XCTAssertEqual(model.items.count, 2)
    }

    func testRefreshFailureKeepsVisibleContent() async throws {
        let values = try await fixtures()
        let model = PageModel<Launch>()
        await model.reload { _, _ in Snapshot(value: Page(items: [values[0]], nextPage: nil, total: 1), source: .live) }
        await model.reload(keepingContent: true) { _, _ in throw AppError.timeout }
        XCTAssertEqual(model.items.map(\.id), [values[0].id])
        XCTAssertNotNil(model.error)
        XCTAssertFalse(model.isLoading)
    }

    func testFailedRefreshPreservesPaginationOfVisibleDemo() async throws {
        let model = PageModel<Launch>()
        let first = try await FixtureService().launches(filter: .init(), page: 1, size: 8)
        let second = try await FixtureService().launches(filter: .init(), page: 2, size: 8)
        await model.reload { _, _ in Snapshot(value: first, source: .demo) }

        await model.reload(keepingContent: true) { _, _ in throw AppError.decoding }

        XCTAssertEqual(model.items, first.items)
        XCTAssertEqual(model.nextPage, 2)
        XCTAssertEqual(model.total, 24)
        XCTAssertEqual(model.source, .demo)
        XCTAssertNotNil(model.error)
        await model.loadMore { page, source in
            XCTAssertEqual(page, 2)
            XCTAssertEqual(source, .demo)
            return Snapshot(value: second, source: .demo)
        }
        XCTAssertEqual(model.items, first.items + second.items)
        XCTAssertEqual(model.nextPage, 3)
    }

    func testCancelledRefreshPreservesPagination() async throws {
        let model = PageModel<Launch>()
        let first = try await FixtureService().launches(filter: .init(), page: 1, size: 8)
        await model.reload { _, _ in Snapshot(value: first, source: .live) }
        await model.reload(keepingContent: true) { _, _ in throw CancellationError() }
        XCTAssertEqual(model.nextPage, 2)
        XCTAssertEqual(model.items, first.items)
        XCTAssertNil(model.error)
        XCTAssertFalse(model.isLoading)
    }

    func testCachedPaginationSurvivesFailedRevalidation() async throws {
        let model = PageModel<Launch>()
        let first = try await FixtureService().launches(filter: .init(), page: 1, size: 8)
        await model.reload(cached: { Snapshot(value: first, source: .live, isCached: true) }) { _, _ in
            throw AppError.offline
        }
        XCTAssertEqual(model.items, first.items)
        XCTAssertEqual(model.nextPage, 2)
        XCTAssertTrue(model.isCached)
    }

    func testRefreshBlocksLoadMoreAndReplacesOldPaginationOnSuccess() async throws {
        let model = PageModel<Launch>()
        let first = try await FixtureService().launches(filter: .init(), page: 1, size: 8)
        await model.reload { _, _ in Snapshot(value: first, source: .demo) }
        let gate = Gate<Snapshot<Page<Launch>>>()
        let refresh = Task { await model.reload(keepingContent: true) { _, _ in await gate.value() } }
        await gate.waitUntilStarted()
        await model.loadMore { _, _ in
            XCTFail("Retaining the cursor must not allow pagination during refresh")
            throw AppError.offline
        }
        await gate.resolve(Snapshot(value: Page(items: [], nextPage: nil, total: 0), source: .live))
        await refresh.value
        XCTAssertTrue(model.items.isEmpty)
        XCTAssertNil(model.nextPage)
        XCTAssertEqual(model.source, .live)
        XCTAssertFalse(model.isLoading)
    }

    func testPaginationRejectsSourceChange() async throws {
        let values = try await fixtures()
        let model = PageModel<Launch>()
        await model.reload { _, _ in Snapshot(value: Page(items: [values[0]], nextPage: 2, total: 2), source: .live) }
        await model.loadMore { _, _ in Snapshot(value: Page(items: [values[1]], nextPage: nil, total: 2), source: .demo) }
        XCTAssertEqual(model.source, .live)
        XCTAssertEqual(model.items.count, 1)
        XCTAssertNotNil(model.pageError)
    }
}
