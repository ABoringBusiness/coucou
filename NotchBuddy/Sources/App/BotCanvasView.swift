import SwiftUI
import AppKit

/// SwiftUI wrapper: TimelineView drives a Canvas that calls BotEngine.draw().
/// Uses a shared engine per-task; the main bot uses AppState's shared engine.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// When set, overrides island-based eye-tracking (used by desktop Mochi).
    /// CGPoint in the same coord space as state.mousePosition (DesktopSpace, y-down).
    var lookOriginOverride: CGPoint? = nil
    /// Not drawn while true (e.g. the notch copy while Mochi is on the desktop).
    var paused: Bool = false

    var body: some View {
        // Nova, not Mochi: the character and its animations are reserved by
        // upstream's LICENSE-ASSETS.md even though they live in code.
        //
        // `lookXY` is kept and reused rather than replaced. It already returns
        // the pointer as a tanh-normalised pair, which is exactly the gaze Nova
        // takes, and following the pointer is most of what made this feel like
        // something rather than a spinner.
        //
        // The engine wiring that used to live here — morph, slot, outfits, mood
        // from MachineVitals, the greet and dance notifications — went with the
        // character it animated. Those are expressions of Mochi, not state a
        // dotted sphere can carry.
        let look = lookXY(state: state)
        let isHidden = paused || state.mode == .hidden
        let targetFPS: Double = state.mode == .expanded ? 60 : 30
        NovaAvatarView(
            energy: isHidden ? 0 : state.effectiveState.novaEnergy,
            gaze: CGPoint(x: look.x, y: look.y),
            detailed: state.mode == .expanded,
            particleOverhang: particleOverhang,
            bodyScale: 0.55,
            tone: VesperTone(botState: state.effectiveState),
            fpsCap: targetFPS,
            paused: isHidden
        )
    }

    /// Where Mochi looks (the pointer), both axes at once: the island geometry and the
    /// screen are looked up once per frame instead of twice each.
    private func lookXY(state: AppState) -> (x: CGFloat, y: CGFloat) {
        if let origin = lookOriginOverride {
            return (tanh((state.mousePosition.x - origin.x) / 260),
                    -tanh((state.mousePosition.y - origin.y) / 200))
        }
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view,
                                             progress: state.uploadProgress,
                                             nw: state.notchWidth, nh: state.notchHeight)
        let screen = IslandWindowController.islandScreen().frame
        let desktopTop = IslandWindowController.desktopTop
        // The pointer read now, not from the island poll (which slows down far from it).
        let mouse = DesktopSpace.topDown(NSEvent.mouseLocation, desktopTop: desktopTop)
        func botPoint(islandH: CGFloat) -> CGPoint {
            let (botCx, botCy, _, _) = botPosition(mode: state.mode, view: state.view,
                                                    islandW: islandW, islandH: islandH,
                                                    uploadProgress: state.uploadProgress)
            return DesktopSpace.topDown(CGPoint(x: screen.midX - islandW / 2 + botCx,
                                                y: screen.maxY - botCy),
                                        desktopTop: desktopTop)
        }
        let botX = botPoint(islandH: islandH)
        // The chat view grows with the conversation: vertical look uses its real height.
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatHistory.count) * 40)
            : islandH
        let botY = actualH == islandH ? botX : botPoint(islandH: actualH)
        return (tanh((mouse.x - botX.x) / 260),
                -tanh((mouse.y - botY.y) / 200))
    }
}

/// Crisp vector glyph badge for secondary agent/service pills and compact notch slots.
/// Preserves the singular Vesper ring exclusively for the primary companion (`BotCanvasView`),
/// eliminating cloned/blurry mini rings while reporting live state via Pace tokens.
struct MiniBotCanvasView: View {
    let task: AgentTask
    var isDancing: Bool = false
    var size: CGFloat = 22
    var framed: Bool = true

    private var symbolName: String {
        switch task.id {
        case "integration_github":
            return "chevron.left.forwardslash.chevron.right"
        case "integration_claude", "agent_cursor", "agent_codex", "agent_antigravity",
             "agent_gemini", "agent_copilot", "agent_muse", "agent_opencode",
             "agent_amp", "agent_hermes", "agent_claude-desktop":
            return "terminal"
        case let id where id.hasPrefix("ai_"):
            return "sparkles"
        case "integration_vercel":
            return "triangle.fill"
        case "integration_stripe":
            return "creditcard"
        case "integration_calcom":
            return "calendar"
        case "integration_notion":
            return "doc.text"
        case "integration_mail", "integration_resend":
            return "envelope"
        case "integration_music", "integration_spotify":
            return isDancing ? "waveform" : "music.note"
        case "integration_n8n":
            return "point.3.connected.trianglepath.dotted"
        case "integration_crypto", "integration_portfolio":
            return "chart.line.uptrend.xyaxis"
        default:
            return task.isIntegration
                ? "square.grid.2x2"
                : "point.topleft.down.curvedto.point.bottomright.up"
        }
    }

    private var glyphTone: Color {
        if isDancing { return Pace.mint }
        switch task.state {
        case .working, .searching:
            return Pace.act
        case .thinking:
            return Pace.think
        case .approval, .question, .ratelimit:
            return Pace.hold
        case .error, .dizzy:
            return Pace.fail
        case .finished:
            return Pace.mint
        case .idle, .sleeping:
            return framed ? Pace.ink2 : Pace.ink3
        }
    }

    private var isActiveState: Bool {
        if isDancing { return true }
        switch task.state {
        case .idle, .sleeping:
            return false
        default:
            return true
        }
    }

    var body: some View {
        let iconSize = framed ? max(8, round(size * 0.48)) : max(8, round(size * 0.78))
        ZStack {
            if framed {
                RoundedRectangle(cornerRadius: Pace.r, style: .continuous)
                    .fill(isActiveState ? glyphTone.opacity(0.14) : Pace.raised)
                RoundedRectangle(cornerRadius: Pace.r, style: .continuous)
                    .stroke(isActiveState ? glyphTone.opacity(0.34) : Pace.line, lineWidth: 1)
            }
            Image(systemName: symbolName)
                .font(.system(size: iconSize, weight: .semibold))
                .foregroundColor(glyphTone)
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Frame clock

/// Mochi's engine has always moved one `update(dt: 0.05)` per display frame (its look,
/// colour, springs and particles are tuned to that). Drawing slower than the display must
/// not slow Mochi down: each drawn frame runs the steps of the display frames it skipped.
@MainActor
enum MochiFrameClock {
    /// The island screen's refresh rate, looked up at most every 2 s.
    private static var fpsCache: (value: Double, at: CFTimeInterval) = (60, -10)
    static var displayFPS: Double {
        let now = CACurrentMediaTime()
        if now - fpsCache.at > 2 {
            let fps = IslandWindowController.islandScreen().maximumFramesPerSecond
            fpsCache = (Double(min(120, max(30, fps))), now)
        }
        return fpsCache.value
    }

    /// minimumInterval for a target rate, 10 % short: display frames come every 16.6 ms
    /// with jitter, and an interval of exactly 1/60 s skipped every other one (30 fps on a
    /// 60 Hz screen). 60 on a 60 Hz screen draws every frame; on ProMotion, one in two.
    static func interval(fps: Double) -> TimeInterval { 0.9 / fps }

    /// One engine step per drawn frame, exactly as before the frame clock (9 October): a
    /// perfectly regular rhythm. The step-debt version measured the time between renders,
    /// and its jitter made frames with 0 steps (Mochi froze) and frames with 2 or more
    /// (Mochi jumped), several times a second: the stutter when the island opens and when
    /// Mochi follows the pointer. Mochi draws at the display rate, so one step per frame
    /// is one step per display frame, which is what his motion is tuned to.
    static func advance(_ engine: BotEngine) {
        engine.update(dt: 0.05)
    }
}
