import SwiftUI

/// A question Claude asks (AskUserQuestion), with its choices: pick, then
/// Send. The Mac answers Claude with exactly these choices.
struct QuestionCard: View {
    let link: PhoneLink
    let session: SessionItem
    let payload: QuestionPayload

    @State private var picks: [Set<String>] = []
    @State private var sending = false
    @State private var sent = false
    @State private var error: String?

    private var ready: Bool {
        picks.count == payload.items.count && !picks.contains { $0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Question").font(.subheadline.weight(.semibold)).foregroundStyle(Pace.act)
            ForEach(Array(payload.items.enumerated()), id: \.offset) { index, item in
                VStack(alignment: .leading, spacing: 8) {
                    if !item.header.isEmpty {
                        Text(item.header)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Pace.ink3)
                    }
                    Text(item.question).font(.callout.weight(.semibold)).foregroundStyle(Pace.ink)
                    if item.multiSelect {
                        Text("Pick one or more").font(.caption).foregroundStyle(Pace.ink3)
                    }
                    ForEach(item.options, id: \.label) { option in
                        optionRow(option, item: item, index: index)
                    }
                }
            }
            if sent {
                Label("Answer sent to your Mac", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Pace.mint)
            } else {
                Button {
                    Task { await send() }
                } label: {
                    Label("Send answer", systemImage: "paperplane.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(ready && !sending ? Pace.onMint : Pace.ink3)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(ready && !sending ? Pace.mint : Pace.sunk,
                                    in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!ready || sending)
                Text("Claude waits about 2 minutes, then asks in the terminal.")
                    .font(.caption.monospacedDigit()).foregroundStyle(Pace.ink3)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(Pace.fail)
            }
        }
        .padding(16)
        .glassCard(cornerRadius: Pace.rIslandCard, tint: Pace.act)
        .overlay(RoundedRectangle(cornerRadius: Pace.rIslandCard, style: .continuous)
            .strokeBorder(Pace.act.opacity(0.35), lineWidth: 1))
        .onAppear { reset() }
        .onChange(of: payload) { reset() }
    }

    private func optionRow(_ option: QuestionPayload.Option, item: QuestionPayload.Item, index: Int) -> some View {
        let selected = picks.indices.contains(index) && picks[index].contains(option.label)
        return Button {
            guard picks.indices.contains(index), !sent else { return }
            if item.multiSelect {
                if selected { picks[index].remove(option.label) } else { picks[index].insert(option.label) }
            } else {
                picks[index] = [option.label]
            }
            Haptics.impact()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.multiSelect
                      ? (selected ? "checkmark.square.fill" : "square")
                      : (selected ? "largecircle.fill.circle" : "circle"))
                    .foregroundStyle(selected ? Pace.mint : Pace.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.label).font(.callout).foregroundStyle(Pace.ink)
                    if !option.description.isEmpty {
                        Text(option.description).font(.caption).foregroundStyle(Pace.ink2)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(selected ? Pace.mintSoft : Pace.sunk,
                        in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                .strokeBorder(selected ? Pace.mint.opacity(0.5) : Pace.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reset() {
        picks = Array(repeating: [], count: payload.items.count)
        sent = false
        error = nil
    }

    private func send() async {
        sending = true
        defer { sending = false }
        error = nil
        // Keep the order of the choices, as Claude listed them.
        let selections = payload.items.enumerated().map { index, item in
            item.options.map(\.label).filter { picks[index].contains($0) }
        }
        if await link.answer(fingerprint: session.questionFingerprint, pillId: session.id, selections: selections) {
            sent = true
            Haptics.success()
        } else {
            error = link.lastPong ?? "Couldn't reach iCloud."
            Haptics.error()
        }
    }
}
