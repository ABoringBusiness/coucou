#if !APPSTORE
import SwiftUI

// MARK: - VoiceResultView

/// Card shown for ~2 s after a voice command executes.
/// Displayed as `IslandView.voiceResult` (Mochi on left, result on right).
struct VoiceResultView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ZStack {
            CardBackground(wash: state.voiceResult?.outcome == .success
                           ? .green
                           : .red)

            HStack(spacing: 0) {
                Spacer().frame(width: 110)   // Mochi lives here (BotCanvasView)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: state.voiceResult?.outcome == .success
                              ? "checkmark.circle.fill"
                              : "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(state.voiceResult?.outcome == .success
                                             ? Pace.mint
                                             : Pace.fail)

                        Text(state.voiceResult?.message ?? "")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Pace.ink)
                    }
                }
                .padding(.trailing, 18)

                Spacer(minLength: 0)
            }
        }
    }
}
#endif
