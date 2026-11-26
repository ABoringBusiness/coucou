import SwiftUI
import UIKit

/// What the Mac just read from a service's API: figures, lists, and the
/// actions it offers on each item (Face ID, then the Mac does it).
struct ServiceLiveDetail: View {
    let link: PhoneLink
    let pillId: String
    let detail: ServiceDetail

    @State private var running: ServiceActionDef?
    @State private var confirming: ServiceActionDef?
    @State private var sentFeedback = 0
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let result = detail.lastAction, Date().timeIntervalSince(result.date) < 10 * 60 {
                resultBanner(result)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            if let error = detail.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Pace.hold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .glassCard(cornerRadius: Pace.rIslandCard)
            }
            if !detail.stats.isEmpty { stats }
            ForEach(Array(detail.sections.enumerated()), id: \.offset) { _, section in
                sectionCard(section)
            }
            Text("Read from your Mac · \(detail.fetchedAt.formatted(.relative(presentation: .named)))")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Pace.ink3)
                .frame(maxWidth: .infinity)
        }
        .animation(.spring(duration: 0.45, bounce: 0.2), value: detail.lastAction)
        .sensoryFeedback(.success, trigger: sentFeedback)
        .confirmationDialog(confirming?.title ?? "", isPresented: Binding(get: { confirming != nil },
                                                                         set: { if !$0 { confirming = nil } }),
                            titleVisibility: .visible) {
            if let action = confirming {
                Button(action.title, role: action.destructive ? .destructive : nil) { run(action) }
            }
        } message: {
            Text(confirming?.confirm ?? "")
        }
    }

    // MARK: Figures

    /// The figures in one strip, like the Stocks or Fitness summaries.
    private var stats: some View {
        HStack(spacing: 0) {
            ForEach(Array(detail.stats.enumerated()), id: \.offset) { index, stat in
                VStack(spacing: 3) {
                    Text(stat.value)
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(stat.tone == .idle || stat.tone == .ok ? Pace.ink : stat.tone.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                        .contentTransition(.numericText())
                    Text(stat.label)
                        .font(.caption2)
                        .foregroundStyle(Pace.ink3)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                if index < detail.stats.count - 1 {
                    Divider().frame(height: 28)
                }
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .glassCard(cornerRadius: Pace.rIslandCard)
    }

    // MARK: Lists

    private func sectionCard(_ section: DetailSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.title).font(.subheadline.weight(.medium)).foregroundStyle(Pace.ink3)
            ForEach(Array(section.items.enumerated()), id: \.offset) { index, item in
                itemRow(item)
                if index < section.items.count - 1 { Divider() }
            }
            if let footer = section.footer {
                Text(footer).font(.caption).foregroundStyle(Pace.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: Pace.rIslandCard)
    }

    /// One line per item: a tap opens it on the web, its actions sit in the
    /// "…" menu on the right (or a long press), like Mail and Files.
    private func itemRow(_ item: DetailItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Circle().fill(item.tone == .idle ? Pace.ink3.opacity(0.5) : item.tone.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(Pace.ink)
                        .lineLimit(1)
                    if let badge = item.badge, !badge.isEmpty {
                        Text(badge)
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(item.tone == .idle ? Pace.ink3 : item.tone.color)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                HStack(spacing: 4) {
                    if !item.subtitle.isEmpty {
                        Text(item.subtitle).lineLimit(1)
                    }
                    if let date = item.date {
                        if !item.subtitle.isEmpty { Text("·") }
                        Text(date, format: .relative(presentation: .named)).monospacedDigit().lineLimit(1).fixedSize()
                    }
                }
                .font(.caption)
                .foregroundStyle(Pace.ink3)
            }
            Spacer(minLength: 4)
            if !item.actions.isEmpty {
                Menu {
                    ForEach(item.actions, id: \.self) { action in
                        Button(role: action.destructive ? .destructive : nil) {
                            if action.confirm != nil { confirming = action } else { run(action) }
                        } label: {
                            Label(action.title, systemImage: action.symbol)
                        }
                    }
                } label: {
                    Group {
                        if item.actions.contains(where: { $0 == running }) {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis")
                                .font(.callout.weight(.semibold))
                        }
                    }
                    .frame(width: 32, height: 32)
                    .glassPill(Circle(), interactive: true)
                }
                .disabled(running != nil)
            } else if item.url != nil {
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = item.url.flatMap(URL.init(string:)), url.scheme == "https" { openURL(url) }
        }
        .contextMenu {
            ForEach(item.actions, id: \.self) { action in
                Button(role: action.destructive ? .destructive : nil) {
                    if action.confirm != nil { confirming = action } else { run(action) }
                } label: {
                    Label(action.title, systemImage: action.symbol)
                }
            }
            if let url = item.url.flatMap(URL.init(string:)), url.scheme == "https" {
                Button { openURL(url) } label: { Label("Open", systemImage: "safari") }
                Button { UIPasteboard.general.url = url } label: { Label("Copy link", systemImage: "link") }
            }
        }
    }

    private func run(_ action: ServiceActionDef) {
        confirming = nil
        running = action
        Task {
            if await link.runServiceAction(action, pillId: pillId) { sentFeedback += 1 }
            running = nil
        }
    }

    // MARK: Result

    private func resultBanner(_ result: ServiceActionResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if result.ok {
                DrawnCheckmark(size: 30)
            } else {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(Pace.fail)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(result.title).font(.subheadline.weight(.semibold)).foregroundStyle(Pace.ink)
                Text(result.message).font(.callout).foregroundStyle(Pace.ink2)
            }
            Spacer(minLength: 0)
            Text(result.date, format: .relative(presentation: .named))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(Pace.ink3)
        }
        .padding(16)
        .glassCard(cornerRadius: Pace.rIslandCard, tint: result.ok ? Pace.mint : Pace.fail)
    }
}
