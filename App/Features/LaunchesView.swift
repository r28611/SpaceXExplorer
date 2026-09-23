import SwiftUI
import SpaceXCore

struct LaunchesView: View {
    let repository: SpaceXRepository
    let mode: DataMode
    @State private var model = PageModel<Launch>()
    @State private var filter = LaunchFilter()
    @State private var showsFilter = false
    @State private var refreshTask: Task<Void, Never>?
    @ScaledMetric(relativeTo: .title) private var heroHeight = 190.0
    private let pageSize = 8

    var body: some View {
        List {
            Section {
                ZStack(alignment: .bottomLeading) {
                    MissionArtwork()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SPACE EXPLORER").font(.caption.weight(.semibold)).tracking(2)
                        Text("Every mission.\nA new perspective.")
                            .font(.title.weight(.semibold))
                    }
                    .foregroundStyle(.white).padding(24)
                }
                .frame(height: heroHeight).clipShape(RoundedRectangle(cornerRadius: 24))
                .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section {
                Picker("Launch period", selection: $filter.period) {
                    ForEach(LaunchFilter.Period.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("launchPeriod")
                if filter.start != nil {
                    HStack {
                        Label("Date range applied · UTC", systemImage: "calendar")
                            .font(.footnote)
                        Spacer()
                        Button("Clear") { filter.start = nil; filter.endExclusive = nil }
                            .font(.footnote)
                    }
                }
            }
            if model.source == .demo || model.isCached || model.notice != nil {
                Section {
                    SourceBanner(source: model.source, isCached: model.isCached,
                                 fetchedAt: model.fetchedAt, notice: model.notice,
                                 retry: mode != .demo ? { refresh() } : nil)
                }
            }
            if let error = model.error, !model.items.isEmpty {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                    Button("Retry refresh") { refresh() }
                }
            }
            Section("Missions") {
                if model.items.isEmpty {
                    if model.isLoading {
                        ProgressView("Loading missions…").frame(maxWidth: .infinity).padding()
                    } else if let error = model.error {
                        FailureView(message: error) { refresh() }
                    } else if model.hasLoaded {
                        ContentUnavailableView("No matching launches", systemImage: "sparkle.magnifyingglass",
                                               description: Text("Try another date range or launch period."))
                    }
                }
                ForEach(model.items) { launch in
                    NavigationLink {
                        LaunchDetailView(launch: launch, source: model.source ?? .live,
                                         isCached: model.isCached, fetchedAt: model.fetchedAt,
                                         repository: repository)
                    } label: {
                        VStack(alignment: .leading, spacing: 9) {
                            Text(launch.name).font(.headline)
                            Text(launch.site).font(.subheadline).foregroundStyle(.secondary)
                            Text(launchDate(launch)).font(.caption).foregroundStyle(.secondary)
                            StatusBadge(status: launch.status)
                        }.padding(.vertical, 7)
                    }
                    .accessibilityIdentifier("launch-\(launch.id)")
                }
                PageFooter(model: model) {
                    refreshTask?.cancel()
                    let query = filter
                    refreshTask = Task { await model.loadMore { page, source in
                        try await repository.launches(filter: query, page: page, size: pageSize, source: source)
                    } }
                }
            }
        }
        .navigationTitle("Launches")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Filter dates", systemImage: filter.start == nil ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill") {
                    showsFilter = true
                }.accessibilityIdentifier("filterDates")
            }
        }
        .sheet(isPresented: $showsFilter) { DateFilterView(filter: $filter) }
        .task(id: filter) { await reload(keepingContent: false) }
        .refreshable { await reload(keepingContent: true) }
        .onDisappear { refreshTask?.cancel() }
    }

    private func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { await reload(keepingContent: true) }
    }

    private func reload(keepingContent: Bool) async {
        let query = filter
        await model.reload(keepingContent: keepingContent,
                           cached: { await repository.cachedLaunches(filter: query, size: pageSize) }) { page, source in
            try await repository.launches(filter: query, page: page, size: pageSize, source: source)
        }
    }
}

private struct DateFilterView: View {
    @Binding var filter: LaunchFilter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var start: Date
    @State private var end: Date
    @State private var error: String?

    init(filter: Binding<LaunchFilter>) {
        _filter = filter
        _start = State(initialValue: filter.wrappedValue.start ?? LaunchFilter.utcCalendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!)
        _end = State(initialValue: filter.wrappedValue.endExclusive?.addingTimeInterval(-1) ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Start date", selection: $start, displayedComponents: .date)
                    DatePicker("End date", selection: $end, displayedComponents: .date)
                } footer: {
                    Text("Both selected days are included. Dates use UTC to match the launch schedule.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    actionLayout {
                        Button(role: .destructive) {
                            filter.start = nil; filter.endExclusive = nil; dismiss()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(.red)
                        .accessibilityLabel("Clear date range")
                        .accessibilityIdentifier("clearDateRange")

                        Button {
                            do {
                                filter = try LaunchFilter.days(from: start, through: end, period: filter.period)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .accessibilityIdentifier("applyDateRange")
                    }
                    .controlSize(.large)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .navigationTitle("Date range").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }
}
