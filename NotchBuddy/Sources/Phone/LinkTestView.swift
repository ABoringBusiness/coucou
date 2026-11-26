import SwiftUI

struct LinkTestView: View {
    let link: PhoneLink
    @State private var sending = false

    var body: some View {
            List {
                Section {
                    statusRow
                    if link.notificationsAllowed == false {
                        Label("Notifications are off: the \"Ping from your Mac\" banner won't show.",
                              systemImage: "bell.slash")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Approval notifications", value: link.approvalsStatus)
                    LabeledContent("Live Activities",
                                   value: LiveActivityLink.shared.activitiesEnabled ? "Allowed" : "Off in Settings")
                    if let error = link.pushError {
                        Label("Push registration failed: \(error)", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Pace.hold)
                    }
                }

                Section {
                    if link.sessions.isEmpty {
                        Text("No session yet. Open HeyApex Eye on your Mac (NotchBuddyCloud).")
                            .foregroundStyle(Pace.ink3)
                    }
                    ForEach(link.sessions) { session in
                        HStack(alignment: .top, spacing: 12) {
                            MochiStill(state: session.state)
                                .padding(4)
                                .frame(width: 40, height: 40)
                                .background(Color.mochiTile(hex: session.color), in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.name.isEmpty ? session.pillName : session.name)
                                    .foregroundStyle(Pace.ink)
                                Text("\(session.pillName) · \(session.state.rawValue)" +
                                     (session.steps.isEmpty ? "" : " · \(session.stepIndex + 1)/\(session.steps.count)"))
                                    .font(.caption.monospacedDigit()).foregroundStyle(Pace.ink2)
                                if session.needsApproval {
                                    Text(session.approvalCommand.isEmpty ? "Waiting for your approval" : session.approvalCommand)
                                        .font(.caption.monospaced()).foregroundStyle(Pace.hold).lineLimit(2)
                                } else if !session.question.isEmpty {
                                    Text(session.question).font(.caption).foregroundStyle(Pace.act).lineLimit(2)
                                } else if let step = session.currentStep {
                                    Text(step).font(.caption).lineLimit(1)
                                }
                                Text(session.updatedAt, style: .relative)
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(Pace.ink3)
                            }
                        }
                    }
                } header: {
                    Text("Sessions on your Mac").textCase(nil)
                }

                Section {
                    Button {
                        sending = true
                        Task {
                            await link.sendPong()
                            sending = false
                        }
                    } label: {
                        HStack {
                            Text("Send pong").foregroundStyle(Pace.mint)
                            if sending { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(link.pings.isEmpty || sending || link.status != .ready)
                    if let pong = link.lastPong {
                        Text(pong).font(.footnote).foregroundStyle(Pace.ink3)
                    }
                }

                Section {
                    if link.pings.isEmpty {
                        Text("No ping yet.").foregroundStyle(Pace.ink3)
                    }
                    ForEach(link.pings) { ping in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(ping.message.isEmpty ? "Ping" : ping.message)
                            HStack {
                                Text("\(ping.macName) · \(ping.app)")
                                Spacer()
                                Text(ping.sentAt, style: .time).monospacedDigit()
                            }
                            .font(.caption)
                            .foregroundStyle(Pace.ink2)
                            Text(delayText(ping))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(ping.delay == nil ? Pace.ink3 : Pace.mint)
                        }
                    }
                } header: {
                    Text("Pings from your Mac").textCase(nil)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Pace.ground)
            .navigationTitle("Coucou link test")
            .refreshable { await link.refresh() }
            .toolbar {
                NavigationLink("Kit") { KitPreviewView() }
            }
    }

    @ViewBuilder private var statusRow: some View {
        switch link.status {
        case .starting:
            Label("Connecting to iCloud…", systemImage: "icloud")
        case .noAccount(let reason):
            Label("iCloud not connected. \(reason) Sign in in Settings, using the same account as your Mac.",
                  systemImage: "icloud.slash")
                .foregroundStyle(Pace.hold)
        case .zoneMissing:
            Label("The HeyApex Eye zone doesn't exist yet. Launch HeyApex Eye on your Mac (NotchBuddyCloud scheme), then pull to refresh.",
                  systemImage: "tray")
                .foregroundStyle(Pace.hold)
        case .ready:
            Label("Linked to iCloud", systemImage: "checkmark.icloud")
                .foregroundStyle(Pace.mint)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.icloud")
                .foregroundStyle(Pace.fail)
        }
    }

    private func delayText(_ ping: PingItem) -> String {
        guard let delay = ping.delay else { return "already there at launch" }
        return String(format: "received %.1f s after sending", delay)
    }
}
