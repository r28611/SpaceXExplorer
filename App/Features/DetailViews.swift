import SwiftUI
import SpaceXCore

struct LaunchDetailView: View {
    let launch: Launch
    let source: DataSource
    let isCached: Bool
    let fetchedAt: Date?
    let repository: SpaceXRepository

    var body: some View {
        List {
            Section {
                RemoteImage(url: launch.imageURL, label: "Launch image")
                    .frame(height: 240)
                    .listRowInsets(EdgeInsets())
                VStack(alignment: .leading, spacing: 12) {
                    Text(launch.name).font(.title2.weight(.semibold))
                    StatusBadge(status: launch.status)
                    Text(launch.details ?? "No description is available for this mission.")
                        .font(.body).foregroundStyle(.secondary)
                }.padding(.vertical, 8)
            }
            if source == .demo || isCached {
                Section { SourceBanner(source: source, isCached: isCached, fetchedAt: fetchedAt, notice: nil) }
            }
            Section("Mission overview") {
                Label(launch.site, systemImage: "mappin.and.ellipse")
                Label(launchDate(launch), systemImage: "calendar")
                if launch.datePrecision != "hour" {
                    Text("Launch date is approximate (\(launch.datePrecision) precision).")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("Launch vehicle") {
                if let rocket = launch.rocket {
                    NavigationLink {
                        RocketDetailView(id: rocket.id, source: source, repository: repository)
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "airplane.up.forward")
                                .font(.title2).foregroundStyle(.teal)
                                .frame(width: 44, height: 50)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rocket.name).font(.headline)
                                Text(rocket.type.capitalized).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 6)
                    }.accessibilityIdentifier("rocketCard")
                } else {
                    Text("Rocket information unavailable").foregroundStyle(.secondary)
                }
            }
            Section {
                if let url = launch.webcastURL {
                    Link(destination: url) {
                        Label(source == .demo ? "Watch example launch" : "Watch launch", systemImage: "play.circle.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.glassProminent)
                    .listRowBackground(Color.clear)
                    .accessibilityHint("Opens the video in your browser. Requires a connection.")
                } else {
                    Label("Video not available", systemImage: "video.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Mission details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RocketDetailView: View {
    let id: String
    let source: DataSource
    let repository: SpaceXRepository
    @State private var snapshot: Snapshot<Rocket>?
    @State private var error: String?
    @State private var loading = false
    @State private var reloadID = UUID()

    var body: some View {
        List {
            if let snapshot {
                let rocket = snapshot.value
                Section {
                    RemoteImage(url: rocket.imageURL, label: "\(rocket.name) image")
                        .frame(height: 240).listRowInsets(EdgeInsets())
                    VStack(alignment: .leading, spacing: 12) {
                        Text(rocket.name).font(.title2.weight(.semibold))
                        Label(rocket.isActive ? "Active" : "Inactive", systemImage: rocket.isActive ? "checkmark.circle" : "pause.circle")
                            .font(.subheadline).foregroundStyle(rocket.isActive ? .teal : .secondary)
                        Text(rocket.details).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }
                if snapshot.source == .demo || snapshot.isCached {
                    Section {
                        SourceBanner(source: snapshot.source, isCached: snapshot.isCached,
                                     fetchedAt: snapshot.fetchedAt, notice: snapshot.notice)
                    }
                }
                Section("Specifications") {
                    LabeledContent("Type", value: rocket.type.capitalized)
                    LabeledContent("Engines", value: "\(rocket.engineCount)")
                    LabeledContent("Engine type", value: rocket.engineType.capitalized)
                    LabeledContent("Success rate", value: "\(rocket.successRate)%")
                }
                if let error {
                    Section { Text(error).foregroundStyle(.secondary); Button("Retry") { reloadID = UUID() } }
                }
            } else if loading {
                ProgressView("Loading rocket…").frame(maxWidth: .infinity)
            } else if let error {
                FailureView(message: error) { reloadID = UUID() }
            }
        }
        .navigationTitle("Rocket details").navigationBarTitleDisplayMode(.inline)
        .task(id: reloadID) { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard !loading else { return }
        loading = true; error = nil
        defer { loading = false }
        if snapshot == nil { snapshot = await repository.cachedRocket(id: id, source: source) }
        do {
            let value = try await repository.rocket(id: id, source: source)
            try Task.checkCancellation()
            snapshot = value
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
