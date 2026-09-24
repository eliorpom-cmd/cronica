//
//  ParentalGuideSection.swift
//  Cronica
//

import SwiftUI

/// IMDb parents guide summary for the details screen, shown only when enabled in Settings.
struct ParentalGuideSection: View {
    let imdbID: String?
    @StateObject private var settings = SettingsStore.shared
    @State private var guide: IMDbParentalGuide?
    @State private var selectedCategory: IMDbParentalGuide.Category?

    var body: some View {
        VStack(spacing: 0) {
            if settings.showParentalGuide, let guide, !guide.isEmpty {
                TitleView(title: String(localized: "Parents Guide"),
                          subtitle: String(localized: "Provided by IMDb"),
                          showChevron: false)
                summaryCard(guide)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }
        }
        .task(id: TaskKey(imdbID: imdbID, isEnabled: settings.showParentalGuide)) {
            await load()
        }
        .sheet(item: $selectedCategory) { category in
            ParentalGuideCategoryView(category: category, webURL: guide?.webURL)
        }
    }

    private func summaryCard(_ guide: IMDbParentalGuide) -> some View {
        VStack(spacing: 0) {
            ForEach(guide.categories) { category in
                Button {
                    selectedCategory = category
                } label: {
                    categoryRow(category)
                }
                .buttonStyle(.plain)
                if category.id != guide.categories.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, 4)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
    }

    private func categoryRow(_ category: IMDbParentalGuide.Category) -> some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbol)
                .font(.subheadline)
                .foregroundStyle(category.severity.tint)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(category.title)
                .font(.subheadline)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            SeverityBadge(severity: category.severity, label: category.severityLabel)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        guard settings.showParentalGuide, let imdbID else { return }
        if guide?.imdbID == imdbID { return }
        do {
            let result = try await IMDbParentalGuideService.shared.fetch(imdbID: imdbID)
            withAnimation { guide = result }
        } catch {
            // Parents guide is optional; hide the section on failure.
            guide = nil
        }
    }

    private struct TaskKey: Equatable {
        let imdbID: String?
        let isEnabled: Bool
    }
}

/// Full detail for one category: vote breakdown and every community entry.
struct ParentalGuideCategoryView: View {
    let category: IMDbParentalGuide.Category
    let webURL: URL?
    @Environment(\.dismiss) private var dismiss
    @State private var revealedSpoilers = Set<Int>()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Text("Severity")
                        Spacer()
                        SeverityBadge(severity: category.severity, label: category.severityLabel)
                    }
                    if category.totalVotes > 0 {
                        ForEach(category.votes, id: \.severity) { vote in
                            voteRow(vote)
                        }
                    }
                } footer: {
                    if category.totalVotes > 0 {
                        Text("\(category.totalVotes) votes")
                    }
                }

                Section {
                    if category.items.isEmpty {
                        Text("No details yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(category.items.enumerated()), id: \.offset) { index, item in
                            itemRow(item, index: index)
                        }
                    }
                } footer: {
                    if category.totalItems > category.items.count {
                        Text("Showing \(category.items.count) of \(category.totalItems) entries.")
                    }
                }
            }
            .navigationTitle(category.title)
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if let webURL {
                    ToolbarItem(placement: .primaryAction) {
                        Link(destination: webURL) {
                            Label("View on IMDb", systemImage: "safari")
                        }
                    }
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
#endif
    }

    private func voteRow(_ vote: IMDbParentalGuide.SeverityVote) -> some View {
        let share = Double(vote.count) / Double(max(category.totalVotes, 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(vote.label)
                    .font(.subheadline)
                Spacer()
                Text(share, format: .percent.precision(.fractionLength(0)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Optional(vote.severity).tint)
                        .frame(width: proxy.size.width * share)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func itemRow(_ item: IMDbParentalGuide.Item, index: Int) -> some View {
        if item.isSpoiler && !revealedSpoilers.contains(index) {
            Button {
                withAnimation { _ = revealedSpoilers.insert(index) }
            } label: {
                Label("Spoiler: tap to reveal", systemImage: "eye.slash")
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                if item.isSpoiler {
                    Text("Spoiler")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(item.text)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct SeverityBadge: View {
    let severity: IMDbParentalGuide.Severity?
    let label: String?

    var body: some View {
        Text(label ?? String(localized: "Not Rated"))
            .font(.caption.weight(.semibold))
            .foregroundStyle(severity.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(severity.tint.opacity(0.15), in: Capsule())
    }
}

private extension Optional where Wrapped == IMDbParentalGuide.Severity {
    var tint: Color {
        switch self {
        case nil, .some(.none): .secondary
        case .some(.mild): .green
        case .some(.moderate): .orange
        case .some(.severe): .red
        }
    }
}
