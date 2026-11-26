import SwiftUI
import AppKit

/// SwiftUI wrapper: TimelineView drives a Canvas that advances `BotEngine` physics/timers
/// and renders the HeyApex Eye geometric specular companion glyph.
struct BotCanvasView: View {
    @ObservedObject var state: AppState
    var particleOverhang: CGFloat = 0
    /// When set, overrides island-based eye-tracking (used by desktop companion).
    /// CGPoint in the same coord space as state.mousePosition (DesktopSpace, y-down).
    var lookOriginOverride: CGPoint? = nil
    /// Not drawn while true (e.g. the notch copy while the companion is on the desktop).
    var paused: Bool = false

    // One engine per view instance (main companion)
    @StateObject private var engine = BotEngine()

    var body: some View {
        observedTimeline
            .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { notif in
                if let emote = notif.object as? BotEmote {
                    engine.triggerEmote(emote)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { _ in
                engine.slap()
            }
            .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { _ in
                engine.blink()
            }
            .onReceive(NotificationCenter.default.publisher(for: .botSetTgEs)) { notif in
                if let v = notif.object as? CGFloat {
                    engine.tgEs = v
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .botGulp)) { _ in
                engine.gulp()
            }
            .onReceive(NotificationCenter.default.publisher(for: .botMorphTo)) { notif in
                if let target = notif.object as? CGFloat {
                    let dur: CGFloat = target > 0.5 ? 550 : 650
                    engine.anim("morph", keys: [TweenKey(target: target, duration: dur, ease: Ease.inOut)])
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
                engine.greet()
            }
            .onAppear {
                engine.setState(state.effectiveState, force: true)
                let isWardrobe = state.mode == .expanded && state.view == .wardrobe
                let isFocusMain = state.focusId == state.mainPillId || state.focusId == nil
                let showOutfit = isFocusMain || state.mode != .expanded || isWardrobe
                engine.setOutfit(showOutfit ? state.resolvedOutfit : .none, animated: false)
            }
    }

    private var observedTimeline: some View {
        TimelineView(.animation(paused: state.mode == .hidden || paused)) { timeline in
            let frame = timeline.date
            Canvas { context, size in
                renderMainFrame(context: context, size: size, frame: frame)
            }
        }
        .onChange(of: state.effectiveState) { _, newState in
            engine.setState(newState)
        }
        #if !APPSTORE
        .onChange(of: state.voiceActive) { _, on in
            if on { engine.enterVoiceCompact() } else { engine.exitVoiceCompact() }
        }
        #endif
        .onChange(of: state.view) { oldView, newView in
            if state.mode == .expanded && newView == .upload {
                engine.anim("morph", keys: [TweenKey(target: 1, duration: 550, ease: Ease.inOut)])
            } else if newView != .upload && newView != .uploading && engine.morph > 0.01 {
                engine.anim("morph", keys: [TweenKey(target: 0, duration: 550, ease: Ease.inOut)])
            }
            #if !APPSTORE
            if newView == .listening {
                engine.enterListening()
            } else if oldView == .listening {
                engine.exitListening(hadCommand: !VoiceEngine.shared.commandTranscript.isEmpty)
            }
            #endif
        }
        .onChange(of: state.mode) { _, newMode in
            if newMode != .expanded {
                engine.tweens.removeValue(forKey: "morph")
                engine.locks.remove("morph")
                engine.morph = 0
            }
        }
    }

    private func renderMainFrame(context: GraphicsContext, size: CGSize, frame: Date) {
        _ = frame
        let look = lookXY(state: state)
        engine.lookX = look.x
        engine.lookY = look.y
        engine.particleOverhang = particleOverhang
        engine.moodTarget = MachineVitals.shared.mood

        if engine.morph > 0.3 {
            engine.slotHTarget = state.fileDragOver ? 0.20 : 0
        } else {
            engine.slotHTarget = 0
            if engine.morph < 0.05 { engine.slotH = 0; engine.slotHVel = 0 }
        }

        #if !APPSTORE
        if state.showingPlanDetail {
            let hex = state.planDetailIsCodex
                ? CodexPlanGauge.color(state.codexPlanUsage)
                : ClaudePlanGauge.color(for: state.claudePlanUsage.flatMap { ClaudePlanGauge.dominantPct($0) })
            engine.bodyColor = cgColorFromHex(hex)
        } else {
            engine.bodyColor = (state.focusTask?.isIntegration == true)
                ? cgColorFromHex(state.focusTask!.color)
                : nil
        }
        #else
        engine.bodyColor = (state.focusTask?.isIntegration == true)
            ? cgColorFromHex(state.focusTask!.color)
            : nil
        #endif

        let dancing: Bool = {
            #if !APPSTORE
            let active = AppState.shared.activeIntegrations
            let music = AppState.shared.musicPlaying && active.contains("integration_music")
            let spotify = SpotifyController.shared.isPlaying && active.contains(SpotifyController.pillId)
            guard music || spotify else { return false }
            let allowed: Set<BotState> = [.idle, .working, .thinking, .searching, .finished]
            guard allowed.contains(state.effectiveState) else { return false }
            if state.mode == .compact { return true }
            guard state.mode == .expanded && state.view == .overview else { return false }
            return (music && state.focusId == "integration_music")
                || (spotify && state.focusId == SpotifyController.pillId)
            #else
            return false
            #endif
        }()
        engine.setDancing(dancing)
        let isWardrobe = state.mode == .expanded && state.view == .wardrobe
        let isFocusMain = state.focusId == state.mainPillId || state.focusId == nil
        let showOutfit = isFocusMain || state.mode != .expanded || isWardrobe
        engine.setOutfit(showOutfit ? state.resolvedOutfit : .none,
                         animated: state.view != .wardrobe)

        #if !APPSTORE
        if state.view == .listening {
            let target = CGFloat(VoiceEngine.shared.micLevel)
            engine.listeningLevel += (target - engine.listeningLevel) * 0.12
            engine.listeningHasWords = !VoiceEngine.shared.commandTranscript.isEmpty
        } else if state.voiceActive && state.mode == .compact {
            let target = CGFloat(VoiceEngine.shared.micLevel)
            engine.listeningLevel += (target - engine.listeningLevel) * 0.12
        }
        if state.voiceActive { engine.voiceSubState = state.voiceSubState }
        else if engine.voiceSubState != .none { engine.voiceSubState = .none }
        #endif

        MochiFrameClock.advance(engine)
        var ctx = context
        engine.applyDance(&ctx, size: size)

        let now = CACurrentMediaTime()
        let t = CGFloat(now - engine.t0)
        let breathe: CGFloat = engine.state == .sleeping ? sin(t * 1.4) * 0.035 : sin(t * 1.85) * 0.026
        let bob = engine.oy + breathe

        let gx: CGFloat
        let gy: CGFloat
        if engine.cfg.scans || engine.state == .sleeping || engine.state == .dizzy {
            gx = engine.yaw / 0.62
            gy = engine.pitch / 0.50
        } else {
            gx = engine.yaw / 0.62 * 0.72 + engine.lookX * 0.28
            gy = engine.pitch / 0.50 * 0.72 + engine.lookY * 0.28
        }

        var resolvedShape = engine.eyeOverride ?? engine.cfg.eye
        if engine.isDancing && engine.dancingLevel > 0.15 && (engine.state == .idle || engine.state == .finished) {
            resolvedShape = .happy
        }
        let pulsePhase = CGFloat(t.truncatingRemainder(dividingBy: 1.75) / 1.75)

        HeyApexEyeGlyph.draw(
            context: ctx,
            size: size,
            state: engine.state,
            eyeShape: resolvedShape,
            gazeX: gx,
            gazeY: gy,
            open: engine.open,
            bob: bob,
            shakeX: engine.ox,
            tilt: engine.tilt,
            scaleX: engine.sx,
            scaleY: engine.sy,
            eyeScale: engine.es,
            pulsePhase: pulsePhase,
            isStatic: false,
            particleOverhang: particleOverhang,
            radiusScale: 0.30,
            sessionCGColor: engine.bodyColor,
            morph: engine.morph,
            slotOpen: engine.slotH,
            showBadge: engine.badge != nil && engine.badgeS > 0.2 && engine.morph < 0.25
        )
    }

    /// Pointer gaze vector in normalized companion space (`+x` right, `+y` up).
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
        let actualH: CGFloat = (state.mode == .expanded && state.view == .prompt)
            ? min(300, 240 + CGFloat(state.chatHistory.count) * 40)
            : islandH
        let botY = actualH == islandH ? botX : botPoint(islandH: actualH)
        return (tanh((mouse.x - botX.x) / 260),
                -tanh((mouse.y - botY.y) / 200))
    }
}

/// Mini HeyApex Eye canvas (for agent pills, compact 2×2 grid, and column strip)
struct MiniBotCanvasView: View {
    let task: AgentTask
    var isDancing: Bool = false
    @StateObject private var engine: BotEngine

    init(task: AgentTask, isDancing: Bool = false) {
        self.task = task
        self.isDancing = isDancing
        _engine = StateObject(wrappedValue: {
            let e = BotEngine()
            e.isMini = true
            e.bodyColor = cgColorFromHex(task.color)
            return e
        }())
    }

    @Environment(\.islandViewActive) private var viewActive

    var body: some View {
        TimelineView(.animation(paused: !viewActive)) { timeline in
            let frame = timeline.date
            Canvas { context, size in
                _ = frame
                engine.setDancing(isDancing)
                MochiFrameClock.advance(engine)
                var ctx = context
                engine.applyDance(&ctx, size: size)

                let t = CGFloat(CACurrentMediaTime() - engine.t0)
                let bob = engine.oy + sin(t * 2.1) * 0.025
                let gx = engine.yaw / 0.62
                let gy = engine.pitch / 0.50
                let pulsePhase = CGFloat(t.truncatingRemainder(dividingBy: 1.75) / 1.75)
                let resolvedShape = engine.eyeOverride ?? engine.cfg.eye

                HeyApexEyeGlyph.draw(
                    context: ctx,
                    size: size,
                    state: engine.state,
                    eyeShape: resolvedShape,
                    gazeX: gx,
                    gazeY: gy,
                    open: engine.open,
                    bob: bob,
                    shakeX: engine.ox,
                    tilt: engine.tilt,
                    scaleX: engine.sx,
                    scaleY: engine.sy,
                    eyeScale: engine.es,
                    pulsePhase: pulsePhase,
                    isStatic: false,
                    particleOverhang: 0,
                    radiusScale: 0.30,
                    sessionCGColor: engine.bodyColor,
                    showBadge: false
                )
            }
        }
        .onChange(of: task.state) { _, newState in
            engine.setState(newState)
        }
        .onChange(of: task.color) { _, newColor in
            engine.bodyColor = cgColorFromHex(newColor)
        }
        .onAppear {
            engine.setState(task.state, force: true)
            if let emote = task.emote {
                engine.setPermanentEmote(emote)
            }
            if let eye = task.miniEye {
                engine.permanentEye = eye
                engine.eyeOverride = eye
                engine.eyeOverrideUntil = .greatestFiniteMagnitude
            }
        }
    }
}

// MARK: - Frame clock

@MainActor
enum MochiFrameClock {
    private static var fpsCache: (value: Double, at: CFTimeInterval) = (60, -10)
    static var displayFPS: Double {
        let now = CACurrentMediaTime()
        if now - fpsCache.at > 2 {
            let fps = IslandWindowController.islandScreen().maximumFramesPerSecond
            fpsCache = (Double(min(120, max(30, fps))), now)
        }
        return fpsCache.value
    }

    static func interval(fps: Double) -> TimeInterval { 0.9 / fps }

    static func advance(_ engine: BotEngine) {
        engine.update(dt: 0.05)
    }
}
