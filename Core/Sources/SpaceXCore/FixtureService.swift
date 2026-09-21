import Foundation

/// Deliberately synthetic scenarios using the API wire format. No demo record is persisted as live data.
public struct FixtureService: SpaceXService {
    public init() {}

    public func launches(filter: LaunchFilter, page: Int, size: Int) async throws -> Page<Launch> {
        try Task.checkCancellation()
        let records: [LaunchDTO] = try load("launches")
        let values = records.map(\.model).filter(filter.includes).sorted {
            if $0.date == $1.date { return $0.id < $1.id }
            return filter.period == .upcoming ? $0.date < $1.date : $0.date > $1.date
        }
        return try paginate(values, page: page, size: size)
    }

    public func rockets(page: Int, size: Int) async throws -> Page<Rocket> {
        try Task.checkCancellation()
        let records: [RocketDTO] = try load("rockets")
        return try paginate(records.map(\.model).sorted { $0.name < $1.name }, page: page, size: size)
    }

    public func rocket(id: String) async throws -> Rocket {
        let records: [RocketDTO] = try load("rockets")
        guard let rocket = records.first(where: { $0.id == id }) else { throw AppError.notFound }
        return rocket.model
    }

    private func load<Value: Decodable>(_ name: String) throws -> Value {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { throw AppError.notFound }
        return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
    }

    private func paginate<Value>(_ values: [Value], page: Int, size: Int) throws -> Page<Value> {
        guard page > 0, size > 0, page <= Int.max / size else { throw AppError.invalidResponse }
        let start = min((page - 1) * size, values.count)
        let end = min(start + size, values.count)
        return Page(items: Array(values[start..<end]), nextPage: end < values.count ? page + 1 : nil, total: values.count)
    }
}
