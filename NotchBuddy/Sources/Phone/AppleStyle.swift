import SwiftUI

// The pieces that make Coucou feel like an Apple app: Liquid Glass on iOS 26
// (a frosted material before), the agent's color moving softly behind a
// session, Apple Pay's drawn checkmark, and symbols that move with the state.

extension View {
    /// A card in glass (iOS 26) or the Kodeo Obsidian Pace card surface before.
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = Pace.rIslandCard, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                glassEffect(.regular.tint(tint.opacity(0.14)), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            }
        } else {
            background(Pace.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Pace.line, lineWidth: 1))
        }
    }

    /// A small glass shape for pills and fields (iOS 26), a recessed Pace sunk fill before.
    @ViewBuilder
    func glassPill<S: Shape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = interactive ? .regular.interactive() : .regular
            if let tint {
                glassEffect(base.tint(tint.opacity(0.22)), in: shape)
            } else {
                glassEffect(base, in: shape)
            }
        } else {
            background(tint?.opacity(0.16) ?? Pace.sunk, in: shape)
        }
    }
}

/// The agent's color, moving slowly like the background of Apple Music. Drawn
/// in code (MeshGradient), 30 frames a second, only while on screen.
struct AgentBackdrop: View {
    let hex: String

    /// A subtle ambient glow from the top (<= 0.14 opacity), fading into obsidian.
    private var colors: [Color] {
        let base = Color(hex: Self.glowHex(for: hex))
        return [base.opacity(0.14), base.opacity(0.09), base.opacity(0.12),
                base.opacity(0.06), base.opacity(0.03), base.opacity(0.05),
                Color.clear, Color.clear, Color.clear]
    }

    /// White and grey agents (VS Code, Cursor) would make a dull grey haze:
    /// they glow in Pace mint instead.
    static func glowHex(for hex: String) -> String {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = Int(digits, radix: 16) else { return "#34D399" }
        let r = Double((value >> 16) & 0xFF) / 255, g = Double((value >> 8) & 0xFF) / 255, b = Double(value & 0xFF) / 255
        let high = max(r, g, b), low = min(r, g, b)
        let saturation = high == 0 ? 0 : (high - low) / high
        return saturation < 0.25 ? "#34D399" : hex
    }

    /// The middle points drift a little; the edges stay put.
    private static func points(at t: Float) -> [SIMD2<Float>] {
        let topX: Float = 0.5 + 0.1 * sin(t * 0.31)
        let leftY: Float = 0.5 + 0.08 * cos(t * 0.27)
        let midX: Float = 0.5 + 0.12 * cos(t * 0.23)
        let midY: Float = 0.45 + 0.1 * sin(t * 0.37)
        let rightY: Float = 0.5 + 0.08 * sin(t * 0.29)
        let bottomX: Float = 0.5 + 0.1 * cos(t * 0.33)
        return [
            SIMD2(0, 0), SIMD2(topX, 0), SIMD2(1, 0),
            SIMD2(0, leftY), SIMD2(midX, midY), SIMD2(1, rightY),
            SIMD2(0, 1), SIMD2(bottomX, 1), SIMD2(1, 1),
        ]
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { timeline in
            MeshGradient(width: 3, height: 3,
                         points: Self.points(at: Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))),
                         colors: colors)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// Apple Pay's "Done": a Pace mint ring draws itself, then the checkmark.
struct DrawnCheckmark: View {
    var size: CGFloat = 56
    @State private var ring: CGFloat = 0
    @State private var tick: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .trim(from: 0, to: ring)
                .stroke(Pace.mint, style: StrokeStyle(lineWidth: size * 0.07, lineCap: .round))
                .rotationEffect(.degrees(-90))
            CheckShape()
                .trim(from: 0, to: tick)
                .stroke(Pace.mint, style: StrokeStyle(lineWidth: size * 0.08, lineCap: .round, lineJoin: .round))
                .padding(size * 0.28)
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { ring = 1 }
            withAnimation(.easeOut(duration: 0.3).delay(0.35)) { tick = 1 }
        }
    }

    private struct CheckShape: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.minX, y: rect.midY + rect.height * 0.05))
            path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.12))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.12))
            return path
        }
    }
}

/// A small symbol that moves with the session's state: it breathes while
/// waiting for you, pulses while working, wiggles on an error, bounces when done.
struct StateSymbol: View {
    let session: SessionItem

    var body: some View {
        switch session.urgency {
        case 0:
            Image(systemName: "hand.raised.fill").foregroundStyle(Pace.hold)
                .symbolEffect(.breathe)
        case 1:
            Image(systemName: "questionmark.bubble.fill").foregroundStyle(Pace.act)
                .symbolEffect(.breathe)
        case 2:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Pace.fail)
                .symbolEffect(.wiggle, options: .repeat(2), value: session.updatedAt)
        case 3:
            Image(systemName: "ellipsis").foregroundStyle(Pace.act)
                .symbolEffect(.variableColor.iterative)
        case 4:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Pace.mint)
                .symbolEffect(.bounce, value: session.updatedAt)
        default:
            Image(systemName: "moon.zzz.fill").foregroundStyle(Pace.ink3)
        }
    }
}

/// Deny, optional Always, and Allow in Kodeo Obsidian × Pace tokens.
struct ApprovalChoiceButtons: View {
    var disabled = false
    private let always: (() -> Void)?
    let deny: () -> Void
    let allow: () -> Void

    init(disabled: Bool = false, deny: @escaping () -> Void, allow: @escaping () -> Void) {
        self.disabled = disabled
        self.always = nil
        self.deny = deny
        self.allow = allow
    }

    init(disabled: Bool = false, deny: @escaping () -> Void, always: @escaping () -> Void, allow: @escaping () -> Void) {
        self.disabled = disabled
        self.always = always
        self.deny = deny
        self.allow = allow
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: deny) {
                Text("Deny")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Pace.fail)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Pace.sunk, in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                        .strokeBorder(Pace.fail.opacity(0.42), lineWidth: 1))
            }
            if let always {
                Button(action: always) {
                    Text("Always")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Pace.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Pace.sunk, in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                            .strokeBorder(Pace.line, lineWidth: 1))
                }
            }
            Button(action: allow) {
                Label("Allow", systemImage: "faceid")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Pace.onMint)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Pace.mint, in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
            }
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.6 : 1)
    }
}

/// Shrinks a little under the finger, like system buttons.
struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.3), value: configuration.isPressed)
    }
}

/// The command waiting for your OK: who asks, the exact command, Deny / Allow.
struct ApprovalPanel: View {
    let session: SessionItem
    var disabled = false
    let deny: () -> Void
    let allow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(Pace.hold).frame(width: 8, height: 8)
                Text("\(session.pillName) asks to run")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Pace.hold)
                Spacer(minLength: 0)
                Text(session.title)
                    .font(.caption)
                    .foregroundStyle(Pace.ink3)
                    .lineLimit(1)
            }
            Text(session.approvalCommand.isEmpty ? "A permission" : session.approvalCommand)
                .font(.callout.monospaced())
                .foregroundStyle(Pace.ink)
                .lineLimit(4)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Pace.sunk, in: RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                    .strokeBorder(Pace.line, lineWidth: 1))
                .textSelection(.enabled)
            ApprovalChoiceButtons(disabled: disabled, deny: deny, allow: allow)
        }
        .padding(16)
    }
}
