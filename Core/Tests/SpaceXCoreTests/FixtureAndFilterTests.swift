import XCTest
@testable import SpaceXCore

final class FixtureAndFilterTests: XCTestCase, @unchecked Sendable {
    func testPaginationCoversEveryFixtureOnce() async throws {
        let service = FixtureService()
        var ids: [String] = []
        var page: Int? = 1
        while let next = page {
            let result = try await service.launches(filter: .init(), page: next, size: 8)
            ids += result.items.map(\.id)
            page = result.nextPage
        }
        XCTAssertEqual(ids.count, 24)
        XCTAssertEqual(Set(ids).count, 24)
    }

    func testUpcomingFilterAndAscendingOrder() async throws {
        let result = try await FixtureService().launches(filter: .init(period: .upcoming), page: 1, size: 100)
        XCTAssertFalse(result.items.isEmpty)
        XCTAssertTrue(result.items.allSatisfy { $0.status == .upcoming })
        XCTAssertEqual(result.items.map(\.date), result.items.map(\.date).sorted())
    }

    func testInclusiveEndDayAndExclusiveNextDay() async throws {
        let records = try await FixtureService().launches(filter: .init(), page: 1, size: 100).items
        let launch = try XCTUnwrap(records.last)
        let filter = try LaunchFilter.days(from: launch.date, through: launch.date)
        XCTAssertTrue(filter.includes(launch))
        XCTAssertEqual(filter.endExclusive!.timeIntervalSince(filter.start!), 86_400)
        let nextDay = LaunchFilter(start: filter.endExclusive)
        XCTAssertFalse(nextDay.includes(launch))
    }

    func testDayRangeUsesCalendarAcrossDaylightSaving() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Amsterdam"))
        let day = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 29)))
        let filter = try LaunchFilter.days(from: day, through: day, calendar: calendar)
        XCTAssertEqual(filter.endExclusive!.timeIntervalSince(filter.start!), 23 * 3600)
    }

    func testInvalidDateRangeIsRejected() {
        XCTAssertThrowsError(try LaunchFilter.days(from: Date(timeIntervalSince1970: 100_000),
                                                  through: Date(timeIntervalSince1970: 0)))
    }

    func testMissingSuccessIsUnknownNotFailure() throws {
        let json = #"{"id":"1","name":"Unknown","date_unix":0,"upcoming":false,"success":null,"rocket":"r1","launchpad":null}"#
        let launch = try JSONDecoder().decode(LaunchDTO.self, from: Data(json.utf8)).model
        XCTAssertEqual(launch.status, .unknown)
        XCTAssertEqual(launch.rocket?.id, "r1")
        XCTAssertNil(launch.imageURL)
        XCTAssertNil(launch.webcastURL)
    }

    func testRocketsPaginateAndResolveByID() async throws {
        let service = FixtureService()
        let first = try await service.rockets(page: 1, size: 2)
        let second = try await service.rockets(page: 2, size: 2)
        XCTAssertEqual(first.nextPage, 2)
        XCTAssertNil(second.nextPage)
        XCTAssertEqual(Set((first.items + second.items).map(\.id)).count, 4)
        let rocket = try await service.rocket(id: first.items[0].id)
        XCTAssertEqual(rocket, first.items[0])
    }
}
