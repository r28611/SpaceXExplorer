import SwiftUI
import SpaceXCore

struct MissionArtwork: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(red: 0.025, green: 0.10, blue: 0.17),
                                        Color(red: 0.04, green: 0.25, blue: 0.30)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().stroke(.white.opacity(0.12), lineWidth: 1)
                    .frame(width: geometry.size.width * 0.8)
                    .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.2)
                Circle().stroke(.white.opacity(0.08), lineWidth: 1)
                    .frame(width: geometry.size.width * 1.2)
                    .offset(x: geometry.size.width * 0.3, y: geometry.size.height * 0.2)
                Image(systemName: "sparkles")
                    .font(.system(size: min(geometry.size.height * 0.28, 60), weight: .ultraLight))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .clipped()
        .accessibilityHidden(true)
    }
}

struct SourceBanner: View {
    let source: DataSource?
    let isCached: Bool
    let fetchedAt: Date?
    let notice: String?
    var retry: (() -> Void)? = nil

    var body: some View {
        if source == .demo || isCached || notice != nil {
            VStack(alignment: .leading, spacing: 8) {
                Label(source == .demo ? "Sample data" : "Saved results",
                      systemImage: source == .demo ? "testtube.2" : "clock.arrow.circlepath")
                    .font(.subheadline.weight(.semibold))
                if source == .demo {
                    Text(notice ?? "Local demo · illustrative missions and specifications.")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    if let fetchedAt {
                        Text("Last updated \(fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let notice { Text(notice).font(.footnote).foregroundStyle(.secondary) }
                }
                if let retry { Button("Retry live API", action: retry).font(.footnote.weight(.semibold)) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("sourceBanner")
        }
    }
}

struct StatusBadge: View {
    let status: LaunchStatus
    private var color: Color {
        switch status {
        case .upcoming: .blue
        case .success: .green
        case .failure: .orange
        case .unknown: .secondary
        }
    }
    private var symbol: String {
        switch status {
        case .upcoming: "clock"
        case .success: "checkmark.circle"
        case .failure: "exclamationmark.circle"
        case .unknown: "questionmark.circle"
        }
    }
    var body: some View {
        Label(status.rawValue, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}

struct FailureView: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        ContentUnavailableView {
            Label("Unable to load", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Try again", action: retry).buttonStyle(.borderedProminent)
        }
    }
}

func launchDate(_ launch: Launch) -> String {
    let formatter = DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    switch launch.datePrecision {
    case "year": formatter.setLocalizedDateFormatFromTemplate("yyyy")
    case "month": formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
    case "quarter":
        let components = LaunchFilter.utcCalendar.dateComponents([.month, .year], from: launch.date)
        return "Q\(((components.month ?? 1) - 1) / 3 + 1) \(components.year ?? 0)"
    case "hour": formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy HHmm")
    default: formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
    }
    return formatter.string(from: launch.date) + (launch.datePrecision == "hour" ? " UTC" : "")
}

struct PageFooter<Item: Codable & Identifiable & Sendable>: View where Item.ID: Sendable {
    let model: PageModel<Item>
    let loadMore: () -> Void
    var body: some View {
        if model.isLoadingMore {
            HStack { Spacer(); ProgressView("Loading more…"); Spacer() }
        } else if let error = model.pageError {
            VStack(spacing: 8) {
                Text(error).font(.footnote).foregroundStyle(.secondary)
                Button("Retry this page", action: loadMore)
            }.frame(maxWidth: .infinity)
        } else if model.nextPage != nil {
            Button("Load more", action: loadMore)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("loadMore")
        } else if !model.items.isEmpty {
            Text("\(model.items.count) of \(model.total) loaded")
                .font(.footnote).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }
}
