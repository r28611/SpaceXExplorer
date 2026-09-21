import XCTest
@testable import SpaceXCore

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)
    private final class Registry: @unchecked Sendable {
        private let lock = NSLock()
        private var handlers: [String: Handler] = [:]
        func set(_ handler: @escaping Handler, host: String) { lock.withLock { handlers[host] = handler } }
        func get(_ host: String) -> Handler? { lock.withLock { handlers[host] } }
        func remove(_ host: String) { lock.withLock { _ = handlers.removeValue(forKey: host) } }
    }
    private static let registry = Registry()
    static func register(host: String, handler: @escaping Handler) { registry.set(handler, host: host) }
    static func remove(host: String) { registry.remove(host) }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let url = request.url, let handler = Self.registry.get(url.host ?? "") else { throw AppError.invalidResponse }
            let (code, data) = try handler(request)
            let response = HTTPURLResponse(url: url, statusCode: code, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class APIClientTests: XCTestCase, @unchecked Sendable {
    func testQueryUsesPOSTPopulationAndExclusiveDateEnd() throws {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 2000)
        let request = try APIClient().launchRequest(filter: .init(period: .upcoming, start: start, endExclusive: end), page: 2, size: 8)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/v5/launches/query")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let query = try XCTUnwrap(body["query"] as? [String: Any])
        let dates = try XCTUnwrap(query["date_utc"] as? [String: String])
        XCTAssertEqual(dates["$gte"], start.ISO8601Format())
        XCTAssertEqual(dates["$lt"], end.ISO8601Format())
        XCTAssertNil(dates["$lte"])
        XCTAssertEqual(query["upcoming"] as? Bool, true)
        let options = try XCTUnwrap(body["options"] as? [String: Any])
        XCTAssertEqual(options["page"] as? Int, 2)
        XCTAssertEqual(options["limit"] as? Int, 8)
        XCTAssertEqual((options["populate"] as? [[String: String]])?.map { $0["path"] }, ["launchpad", "rocket"])
    }

    func testHTTP525IsTypedAvailabilityFailure() async throws {
        try await withClient(handler: { _ in (525, Data("origin down".utf8)) }) { client in
            do {
                _ = try await client.launches(filter: .init(), page: 1, size: 8)
                XCTFail("Expected HTTP error")
            } catch { XCTAssertEqual(error as? AppError, .http(525)) }
        }
    }

    func testMalformedSuccessfulResponseIsDecodingError() async throws {
        try await withClient(handler: { _ in (200, Data("{}".utf8)) }) { client in
            do {
                _ = try await client.launches(filter: .init(), page: 1, size: 8)
                XCTFail("Expected decoding error")
            } catch { XCTAssertEqual(error as? AppError, .decoding) }
        }
    }

    func testNetworkFailureMapsToOffline() async throws {
        try await withClient(handler: { _ in throw URLError(.notConnectedToInternet) }) { client in
            do {
                _ = try await client.launches(filter: .init(), page: 1, size: 8)
                XCTFail("Expected network failure")
            } catch { XCTAssertEqual(error as? AppError, .offline) }
        }
    }

    func testSuccessfulResponseMapsPopulatedReferences() async throws {
        let data = Data(#"{"docs":[{"id":"a","name":"Mission","date_unix":1000,"upcoming":false,"success":true,"launchpad":{"id":"p","name":"Pad","full_name":"Full pad"},"rocket":{"id":"r","name":"Falcon","type":"rocket"}}],"totalDocs":1,"hasNextPage":false,"nextPage":null}"#.utf8)
        try await withClient(handler: { _ in (200, data) }) { client in
            let result = try await client.launches(filter: .init(), page: 1, size: 8)
            XCTAssertEqual(result.items.first?.site, "Full pad")
            XCTAssertEqual(result.items.first?.rocket?.name, "Falcon")
            XCTAssertEqual(result.items.first?.status, .success)
            XCTAssertNil(result.nextPage)
        }
    }

    private func withClient(handler: @escaping StubURLProtocol.Handler,
                            operation: (APIClient) async throws -> Void) async throws {
        let host = UUID().uuidString.lowercased() + ".example"
        StubURLProtocol.register(host: host, handler: handler)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel(); StubURLProtocol.remove(host: host) }
        try await operation(APIClient(session: session, baseURL: URL(string: "https://\(host)")!))
    }
}
