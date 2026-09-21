import Foundation

// Explicit keys keep the wire contract separate from our domain models.
struct RocketDTO: Decodable, Sendable {
    let id: String
    let name: String
    let type: String
    let description: String
    let active: Bool
    let success_rate_pct: Int
    let flickr_images: [String]
    let engines: Engines
    struct Engines: Decodable, Sendable { let number: Int; let type: String; let version: String? }

    var model: Rocket {
        Rocket(id: id, name: name, type: type, details: description, isActive: active,
               engineCount: engines.number,
               engineType: [engines.type, engines.version].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " "),
               successRate: success_rate_pct, imageURL: flickr_images.first.flatMap(safeURL))
    }
}

struct LaunchDTO: Decodable, Sendable {
    let id: String
    let name: String
    let date_unix: Double
    let date_precision: String?
    let upcoming: Bool
    let success: Bool?
    let details: String?
    let launchpad: Reference<Pad>?
    let rocket: Reference<RocketInfo>?
    let links: Links?

    struct Pad: Decodable, Sendable { let id: String; let name: String; let full_name: String? }
    struct RocketInfo: Decodable, Sendable { let id: String; let name: String; let type: String }
    struct Links: Decodable, Sendable {
        let patch: Patch?
        let flickr: Flickr?
        let webcast: String?
        struct Patch: Decodable, Sendable { let large: String?; let small: String? }
        struct Flickr: Decodable, Sendable { let original: [String]? }
    }

    var model: Launch {
        let rocketModel: RocketSummary?
        switch rocket {
        case .value(let info): rocketModel = RocketSummary(id: info.id, name: info.name, type: info.type)
        case .id(let id): rocketModel = RocketSummary(id: id, name: "View rocket", type: "Specifications")
        case nil: rocketModel = nil
        }
        let site: String
        if case .value(let pad) = launchpad { site = pad.full_name ?? pad.name }
        else { site = "Launch site unavailable" }
        return Launch(id: id, name: name, date: Date(timeIntervalSince1970: date_unix),
                      datePrecision: date_precision ?? "day",
                      status: upcoming ? .upcoming : success.map { $0 ? .success : .failure } ?? .unknown,
                      site: site, details: details,
                      imageURL: (links?.flickr?.original?.first ?? links?.patch?.large ?? links?.patch?.small).flatMap(safeURL),
                      webcastURL: links?.webcast.flatMap(safeURL), rocket: rocketModel)
    }
}

enum Reference<Value: Decodable & Sendable>: Decodable, Sendable {
    case id(String), value(Value)
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let id = try? container.decode(String.self) { self = .id(id) }
        else { self = .value(try container.decode(Value.self)) }
    }
}

struct PageDTO<Value: Decodable & Sendable>: Decodable, Sendable {
    let docs: [Value]
    let totalDocs: Int
    let hasNextPage: Bool
    let nextPage: Int?
}

private func safeURL(_ value: String) -> URL? {
    guard let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
    return url
}
