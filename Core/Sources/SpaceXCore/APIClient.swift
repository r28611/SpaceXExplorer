import Foundation

public protocol SpaceXService: Sendable {
    func launches(filter: LaunchFilter, page: Int, size: Int) async throws -> Page<Launch>
    func rockets(page: Int, size: Int) async throws -> Page<Rocket>
    func rocket(id: String) async throws -> Rocket
}

public struct APIClient: SpaceXService, Sendable {
    private let session: URLSession
    private let baseURL: URL

    public init(session: URLSession = .shared, baseURL: URL = URL(string: "https://api.spacexdata.com")!) {
        self.session = session
        self.baseURL = baseURL
    }

    public func launches(filter: LaunchFilter, page: Int, size: Int) async throws -> Page<Launch> {
        let response: PageDTO<LaunchDTO> = try await send(launchRequest(filter: filter, page: page, size: size))
        return Page(items: response.docs.map(\.model), nextPage: response.hasNextPage ? response.nextPage : nil,
                    total: response.totalDocs)
    }

    public func rockets(page: Int, size: Int) async throws -> Page<Rocket> {
        let request = try queryRequest(path: "v4/rockets/query", query: [:],
                                       options: ["page": page, "limit": size, "sort": ["name": "asc", "_id": "asc"]])
        let response: PageDTO<RocketDTO> = try await send(request)
        return Page(items: response.docs.map(\.model), nextPage: response.hasNextPage ? response.nextPage : nil,
                    total: response.totalDocs)
    }

    public func rocket(id: String) async throws -> Rocket {
        var request = URLRequest(url: baseURL.appending(path: "v4/rockets").appending(component: id))
        request.timeoutInterval = 12
        let dto: RocketDTO = try await send(request)
        return dto.model
    }

    func launchRequest(filter: LaunchFilter, page: Int, size: Int) throws -> URLRequest {
        guard page > 0, size > 0 else { throw AppError.invalidResponse }
        if let start = filter.start, let end = filter.endExclusive, start >= end { throw AppError.invalidFilter }
        var query: [String: Any] = [:]
        if filter.period != .all { query["upcoming"] = filter.period == .upcoming }
        var dates: [String: String] = [:]
        if let start = filter.start { dates["$gte"] = start.ISO8601Format() }
        if let end = filter.endExclusive { dates["$lt"] = end.ISO8601Format() }
        if !dates.isEmpty { query["date_utc"] = dates }
        return try queryRequest(path: "v5/launches/query", query: query, options: [
            "page": page, "limit": size,
            "sort": ["date_utc": filter.period == .upcoming ? "asc" : "desc", "_id": "asc"],
            "populate": [
                ["path": "launchpad", "select": "name full_name"],
                ["path": "rocket", "select": "name type"]
            ]
        ])
    }

    private func queryRequest(path: String, query: [String: Any], options: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 12
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "options": options])
        return request
    }

    private func send<Value: Decodable & Sendable>(_ request: URLRequest) async throws -> Value {
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
            guard (200..<300).contains(http.statusCode) else { throw AppError.http(http.statusCode) }
            do { return try JSONDecoder().decode(Value.self, from: data) }
            catch { throw AppError.decoding }
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError {
            switch error.code {
            case .cancelled: throw CancellationError()
            case .notConnectedToInternet, .networkConnectionLost: throw AppError.offline
            case .timedOut: throw AppError.timeout
            default: throw AppError.transport
            }
        }
    }
}
