import Foundation
import Observation

/// Shared pagination mechanics, with feature-specific queries injected at the boundary.
@MainActor @Observable
public final class PageModel<Item: Codable & Identifiable & Sendable> where Item.ID: Sendable {
    public private(set) var items: [Item] = []
    public private(set) var source: DataSource?
    public private(set) var fetchedAt: Date?
    public private(set) var isCached = false
    public private(set) var notice: String?
    public private(set) var error: String?
    public private(set) var pageError: String?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    public private(set) var hasLoaded = false
    public private(set) var total = 0
    public private(set) var nextPage: Int?
    @ObservationIgnored private var generation = UUID()

    public typealias Loader = @Sendable (Int, DataSource?) async throws -> Snapshot<Page<Item>>
    public init() {}

    public func reload(keepingContent: Bool = false,
                       cached: @Sendable () async -> Snapshot<Page<Item>>? = { nil },
                       load: Loader) async {
        let token = UUID()
        generation = token
        isLoading = true
        isLoadingMore = false
        error = nil
        pageError = nil
        nextPage = nil
        if !keepingContent {
            items = []; source = nil; notice = nil; fetchedAt = nil; hasLoaded = false; isCached = false
        }
        defer { if generation == token { isLoading = false } }
        if items.isEmpty, let snapshot = await cached(), generation == token, !Task.isCancelled {
            apply(snapshot, append: false)
            // Cached content is visible, but pagination waits for revalidation.
            nextPage = nil
        }
        do {
            let snapshot = try await load(1, nil)
            guard generation == token, !Task.isCancelled else { return }
            apply(snapshot, append: false)
            hasLoaded = true
        } catch is CancellationError { }
        catch {
            guard generation == token, !Task.isCancelled else { return }
            self.error = error.localizedDescription
            hasLoaded = true
        }
    }

    public func loadMore(load: Loader) async {
        guard !isLoading, !isLoadingMore, let page = nextPage, let source else { return }
        let token = generation
        isLoadingMore = true
        pageError = nil
        defer { if generation == token { isLoadingMore = false } }
        do {
            let snapshot = try await load(page, source)
            guard generation == token, !Task.isCancelled else { return }
            guard snapshot.source == source,
                  snapshot.value.nextPage.map({ $0 > page }) ?? true else { throw AppError.invalidResponse }
            apply(snapshot, append: true)
        } catch is CancellationError { }
        catch {
            guard generation == token, !Task.isCancelled else { return }
            pageError = error.localizedDescription
        }
    }

    private func apply(_ snapshot: Snapshot<Page<Item>>, append: Bool) {
        var seen = Set<Item.ID>()
        items = (append ? items + snapshot.value.items : snapshot.value.items).filter { seen.insert($0.id).inserted }
        source = snapshot.source
        fetchedAt = append ? min(fetchedAt ?? snapshot.fetchedAt, snapshot.fetchedAt) : snapshot.fetchedAt
        isCached = append ? isCached || snapshot.isCached : snapshot.isCached
        notice = snapshot.notice ?? (append ? notice : nil)
        total = snapshot.value.total
        nextPage = snapshot.value.nextPage
    }
}
