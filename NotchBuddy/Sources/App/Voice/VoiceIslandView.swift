#if !APPSTORE
import SwiftUI

// MARK: - VoiceListeningView

/// Content of the island while the voice engine is listening for a command.
/// Shown when `AppState.view == .listening`.
///
/// `isActive` must be true only when this view is the currently displayed island view.
/// Pass `state.view == .listening` from IslandViewContent. This prevents the MicDot
/// animation from running while the view is off-screen (ForEach instantiates all views).
struct VoiceListeningView: View {
    let isActive: Bool
    @ObservedObject private var voice = VoiceEngine.shared
    @ObservedObject private var state = AppState.shared

    /// Question text to show above transcript when re-listening after a .question outcome.
    private var pendingQuestionText: String? {
        if case .question(let text) = state.voiceResult?.outcome { return text }
        return nil
    }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)

            HStack(spacing: 0) {
                Spacer().frame(width: 110)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        MicDotView(active: isActive)
                        Text("Listening\u{2026}", tableName: "Localizable")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Pace.ink)
                    }

                    if let question = pendingQuestionText {
                        Text(question)
                            .font(.system(size: 12))
                            .foregroundColor(Pace.hold)
                            .lineLimit(2)
                    } else if voice.commandTranscript.isEmpty {
                        Text("Say your command", tableName: "Localizable")
                            .font(.system(size: 12))
                            .foregroundColor(Pace.ink3)
                    }

                    if !voice.commandTranscript.isEmpty {
                        Text(voice.commandTranscript)
                            .font(.system(size: 12))
                            .foregroundColor(Pace.body)
                            .lineLimit(2)
                            .animation(.easeOut(duration: 0.1), value: voice.commandTranscript)
                    }
                }
                .padding(.trailing, 18)

                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - MicDotView

/// Pulsing microphone indicator. Animation only runs when `active` is true,
/// preventing CPU waste when the view is in the ForEach but not visible.
private struct MicDotView: View {
    let active: Bool
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Pace.live)
            .frame(width: 8, height: 8)
            .scaleEffect((active && pulsing) ? 1.35 : 1.0)
            .opacity((active && pulsing) ? 0.65 : 1.0)
            .animation(
                active
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulsing
            )
            .onChange(of: active) { _, newValue in pulsing = newValue }
            .onAppear  { pulsing = active }
            .onDisappear { pulsing = false }
    }
}
#endif
