import SwiftUI
import SpaceXCore

struct RocketsView: View {
    let repository: SpaceXRepository
    let mode: DataMode
    @State private var model = PageModel<Rocket>()
    @State private var refreshTask: Task<Void, Never>?
    private let pageSize = 2

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built for beyond.").font(.title2.weight(.semibold))
                    Text("Explore the vehicles behind the missions.")
                        .foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }.listRowBackground(Color.clear)
            if model.source == .demo || model.isCached || model.notice != nil {
                Section {
                    SourceBanner(source: model.source, isCached: model.isCached,
                                 fetchedAt: model.fetchedAt, notice: model.notice,
                                 retry: mode != .demo ? { refresh() } : nil)
                }
            }
            if let error = model.error, !model.items.isEmpty {
                Section { Text(error).foregroundStyle(.secondary); Button("Retry refresh") { refresh() } }
            }
            Section("Fleet") {
                if model.items.isEmpty {
                    if model.isLoading {
                        ProgressView("Loading rockets…").frame(maxWidth: .infinity)
                    } else if let error = model.error {
                        FailureView(message: error) { refresh() }
                    } else if model.hasLoaded {
                        ContentUnavailableView("No rockets available", systemImage: "airplane.up.forward")
                    }
                }
                ForEach(model.items) { rocket in
                    NavigationLink {
                        RocketDetailView(id: rocket.id, source: model.source ?? .live, repository: repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 12) {
                            RemoteImage(url: rocket.imageURL, label: "\(rocket.name) image")
                                .frame(height: 170).clipShape(RoundedRectangle(cornerRadius: 16))
                            Text(rocket.name).font(.title3.weight(.semibold))
                            ViewThatFits(in: .horizontal) {
                                HStack {
                                    Text(rocket.type.capitalized)
                                    Spacer()
                                    Text("\(rocket.successRate)% success")
                                }
                                VStack(alignment: .leading) {
                                    Text(rocket.type.capitalized)
                                    Text("\(rocket.successRate)% success")
                                }
                            }.font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("rocket-\(rocket.id)")
                }
                PageFooter(model: model) {
                    refreshTask?.cancel()
                    refreshTask = Task { await model.loadMore { page, source in
                        try await repository.rockets(page: page, size: pageSize, source: source)
                    } }
                }
            }
        }
        .navigationTitle("Rockets")
        .task { if !model.hasLoaded { await reload() } }
        .refreshable { await reload() }
        .onDisappear { refreshTask?.cancel() }
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await reload() }
    }

    private func reload() async {
        await model.reload(keepingContent: true, cached: { await repository.cachedRockets(size: pageSize) }) { page, source in
            try await repository.rockets(page: page, size: pageSize, source: source)
        }
    }
}
