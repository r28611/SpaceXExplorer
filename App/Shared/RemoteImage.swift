import SwiftUI
import SpaceXCore
import ImageIO

private actor ImagePipeline {
    static let shared = ImagePipeline()
    private let cache = DiskCache(directory: URL.cachesDirectory.appending(path: "SpaceXExplorer/images"), limit: 40)
    private var memory: [URL: Data] = [:]
    private var inFlight: [URL: Task<Data, Error>] = [:]

    func image(for url: URL) async throws -> CGImage {
        let data = try await data(for: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1200,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { throw AppError.decoding }
        return image
    }

    func data(for url: URL) async throws -> Data {
        if let data = memory[url] { return data }
        if let task = inFlight[url] { return try await task.value }
        let cache = cache
        let task = Task<Data, Error> {
            if let cached = await cache.read(Data.self, key: url.absoluteString) { return cached.value }
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  http.mimeType?.hasPrefix("image/") == true, data.count < 8_000_000,
                  CGImageSourceCreateWithData(data as CFData, nil) != nil else {
                throw AppError.invalidResponse
            }
            await cache.write(data, key: url.absoluteString, date: .now)
            return data
        }
        inFlight[url] = task
        defer { inFlight[url] = nil }
        let data = try await task.value
        if memory.values.reduce(0, { $0 + $1.count }) + data.count > 16_000_000 { memory.removeAll() }
        memory[url] = data
        return data
    }
}

struct RemoteImage: View {
    let url: URL?
    let label: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            MissionArtwork()
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .clipped()
        .accessibilityLabel(image == nil ? "\(label). Image unavailable; illustration shown." : label)
        .task(id: url) {
            image = nil
            guard let url else { return }
            do {
                let thumbnail = try await ImagePipeline.shared.image(for: url)
                try Task.checkCancellation()
                image = UIImage(cgImage: thumbnail)
            } catch { /* A missing image never blocks mission information. */ }
        }
    }
}
