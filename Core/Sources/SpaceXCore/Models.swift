import Foundation

public enum LaunchStatus: String, Codable, Sendable {
    case upcoming = "Upcoming", success = "Successful", failure = "Failed", unknown = "Unknown"
}

public struct RocketSummary: Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String
}

public struct Launch: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let date: Date
    public let datePrecision: String
    public let status: LaunchStatus
    public let site: String
    public let details: String?
    public let imageURL: URL?
    public let webcastURL: URL?
    public let rocket: RocketSummary?
}

public struct Rocket: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let type: String
    public let details: String
    public let isActive: Bool
    public let engineCount: Int
    public let engineType: String
    public let successRate: Int
    public let imageURL: URL?
}

public struct Page<Item: Codable & Sendable>: Codable, Sendable {
    public let items: [Item]
    public let nextPage: Int?
    public let total: Int

    public init(items: [Item], nextPage: Int?, total: Int) {
        self.items = items
        self.nextPage = nextPage
        self.total = total
    }
}

public enum DataSource: String, Codable, Sendable { case live, demo }
public enum DataMode: String, CaseIterable, Sendable {
    case automatic, live, demo
    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .live: "Live API only"
        case .demo: "Demo data"
        }
    }
}

public struct Snapshot<Value: Sendable>: Sendable {
    public let value: Value
    public let source: DataSource
    public let fetchedAt: Date
    public let isCached: Bool
    public let notice: String?

    public init(value: Value, source: DataSource, fetchedAt: Date = .now,
                isCached: Bool = false, notice: String? = nil) {
        self.value = value
        self.source = source
        self.fetchedAt = fetchedAt
        self.isCached = isCached
        self.notice = notice
    }
}

public struct LaunchFilter: Hashable, Codable, Sendable {
    public enum Period: String, CaseIterable, Codable, Sendable {
        case all = "All", past = "Past", upcoming = "Upcoming"
    }
    public var period: Period
    public var start: Date?
    public var endExclusive: Date?

    public init(period: Period = .all, start: Date? = nil, endExclusive: Date? = nil) {
        self.period = period
        self.start = start
        self.endExclusive = endExclusive
    }

    /// The UI uses UTC days consistently for filtering and displaying launch dates.
    public static func days(from start: Date, through end: Date,
                            period: Period = .all, calendar: Calendar = utcCalendar) throws -> Self {
        let lower = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        guard lower <= last,
              let upper = calendar.date(byAdding: .day, value: 1, to: last) else {
            throw AppError.invalidFilter
        }
        return Self(period: period, start: lower, endExclusive: upper)
    }

    public static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public func includes(_ launch: Launch) -> Bool {
        (start.map { launch.date >= $0 } ?? true)
        && (endExclusive.map { launch.date < $0 } ?? true)
        && (period == .all || (period == .upcoming ? launch.status == .upcoming : launch.status != .upcoming))
    }
}

public enum AppError: Error, LocalizedError, Equatable, Sendable {
    case offline, timeout, http(Int), invalidResponse, decoding, invalidFilter, notFound, transport

    public var errorDescription: String? {
        switch self {
        case .offline: "You’re offline. Check your connection and try again."
        case .timeout: "The request took too long. Please try again."
        case .http(let code): "SpaceX is unavailable (HTTP \(code)). Please try again later."
        case .invalidResponse, .decoding: "SpaceX returned data we couldn’t read. Please try again later."
        case .invalidFilter: "The end date must be on or after the start date."
        case .notFound: "This item isn’t available."
        case .transport: "Couldn’t connect to SpaceX. Please try again."
        }
    }

    public var permitsFallback: Bool {
        switch self {
        case .offline, .timeout, .transport: true
        case .http(let code): code == 429 || code >= 500
        default: false
        }
    }
}
