import SwiftUI
import CoreGraphics

/// HeyApex Eye in a fixed pose: static geometric specular companion mark for
/// surfaces that do not run a 60 Hz display loop (iOS lists, Widgets, Live Activities).
/// The Mac notch island uses `BotCanvasView` / `MiniBotCanvasView` with live tracking.
struct MochiStill: View {
    var state: BotState = .idle
    /// Overrides the state's aperture expression (e.g. `.closed` for a sleeping agent).
    var eye: EyeShape? = nil
    /// Session or pill accent hex; `#FFFFFF` uses pure state tone.
    var bodyHex: String = "#FFFFFF"
    var showBadge: Bool = true
    /// Gaze offset and aperture expression for timeline snapshots.
    var pose: MochiPose = .neutral

    var body: some View {
        Canvas { context, size in
            let cfg = BotStates[state] ?? BotStates[.idle]!
            let resolvedEye = eye ?? pose.eye ?? cfg.eye
            let gx = max(-1, min(1, pose.yaw / 0.55))
            let gy = max(-1, min(1, pose.pitch / 0.45))

            HeyApexEyeGlyph.draw(
                context: context,
                size: size,
                state: state,
                eyeShape: resolvedEye,
                gazeX: gx,
                gazeY: gy,
                open: pose.open,
                bob: 0,
                shakeX: 0,
                tilt: pose.tilt,
                scaleX: 1,
                scaleY: 1,
                eyeScale: 1,
                pulsePhase: 0.35,
                isStatic: true,
                particleOverhang: 0,
                radiusScale: 0.36,
                sessionHex: bodyHex,
                showBadge: showBadge && cfg.badge != nil
            )
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// Computes a crisp specular stroke for a given hex accent and background luminance.
    static func tintedStroke(for hex: String, luminance: Double? = nil) -> Color {
        let lum: Double
        if let luminance {
            lum = luminance
        } else if let cg = cgColorFromHex(hex), let comps = cg.components, comps.count >= 3 {
            lum = 0.2126 * Double(comps[0]) + 0.7152 * Double(comps[1]) + 0.0722 * Double(comps[2])
        } else {
            lum = 0.5
        }
        if lum > 0.72 {
            return Pace.ink.opacity(0.42)
        }
        return Color(hex: hex).opacity(0.55)
    }
}

// MARK: - Shared HeyApex Eye Geometric Specular Renderer

enum HeyApexEyeGlyph {

    /// State tone following Kodeo Obsidian × Pace ("colour reports STATE, never identity").
    static func stateTone(for state: BotState, eyeShape: EyeShape) -> Color {
        switch state {
        case .idle, .sleeping:
            return Pace.mint
        case .working:
            return Pace.act
        case .thinking, .searching:
            return Pace.think
        case .approval, .question, .ratelimit:
            return Pace.hold
        case .error, .dizzy:
            return Pace.fail
        case .finished:
            return Pace.mint
        }
    }

    /// Specular 1pt housing border color & opacity per companion state.
    static func borderStroke(for state: BotState, eyeShape: EyeShape) -> Color {
        switch state {
        case .idle, .sleeping:
            return eyeShape == .happy ? Pace.mint.opacity(0.65) : Pace.mint.opacity(0.38)
        case .working:
            return Pace.act.opacity(0.55)
        case .thinking, .searching:
            return Pace.think.opacity(0.55)
        case .approval, .question, .ratelimit:
            return Pace.hold.opacity(0.65)
        case .error, .dizzy:
            return Pace.fail.opacity(0.65)
        case .finished:
            return Pace.mint.opacity(0.65)
        }
    }

    /// Whether the companion state emits a subtle concentric ring pulse.
    static func pulsesRing(for state: BotState) -> Bool {
        switch state {
        case .working, .thinking, .searching, .approval, .question:
            return true
        default:
            return false
        }
    }

    /// Draws the HeyApex Eye geometric specular companion glyph.
    static func draw(
        context: GraphicsContext,
        size: CGSize,
        state: BotState,
        eyeShape: EyeShape,
        gazeX: CGFloat,
        gazeY: CGFloat,
        open: CGFloat,
        bob: CGFloat,
        shakeX: CGFloat = 0,
        tilt: CGFloat = 0,
        scaleX: CGFloat = 1,
        scaleY: CGFloat = 1,
        eyeScale: CGFloat = 1,
        pulsePhase: CGFloat = 0,
        isStatic: Bool = false,
        particleOverhang: CGFloat = 0,
        radiusScale: CGFloat = 0.30,
        sessionHex: String? = nil,
        sessionCGColor: CGColor? = nil,
        morph: CGFloat = 0,
        slotOpen: CGFloat = 0,
        showBadge: Bool = false
    ) {
        let W = size.width
        let H = size.height
        guard W > 1, H > 1 else { return }

        let R = W * radiusScale
        let cx = W / 2 + shakeX * R
        let cy = H / 2 + particleOverhang / 2 + bob * R + (particleOverhang > 0 ? R * 0.04 : 0)

        let tone = stateTone(for: state, eyeShape: eyeShape)
        let border = borderStroke(for: state, eyeShape: eyeShape)

        // Housing half-extents (crisp rounded obsidian squircle)
        let hw = R * 1.06
        let hh = R * (0.94 + morph * 0.06)
        let corner = min(hw, hh) * 0.52

        var rootCtx = context
        rootCtx.translateBy(x: cx, y: cy)
        if abs(tilt) > 0.0005 {
            rootCtx.rotate(by: .radians(Double(tilt)))
        }
        if abs(scaleX - 1) > 0.0005 || abs(scaleY - 1) > 0.0005 {
            rootCtx.scaleBy(x: scaleX, y: scaleY)
        }

        // 1. Subtle ring pulse when working / thinking / searching / approval
        if pulsesRing(for: state) {
            let progress: CGFloat = isStatic ? 0.42 : (pulsePhase - floor(pulsePhase))
            let ringScale: CGFloat = 1.04 + progress * 0.22
            let ringAlpha: Double = isStatic ? 0.22 : Double((1.0 - progress) * 0.34)
            let pRect = CGRect(
                x: -hw * ringScale,
                y: -hh * ringScale,
                width: hw * 2 * ringScale,
                height: hh * 2 * ringScale
            )
            let pulsePath = Path(roundedRect: pRect, cornerRadius: corner * ringScale, style: .continuous)
            rootCtx.stroke(pulsePath, with: .color(tone.opacity(ringAlpha)), lineWidth: 1)
        }

        // 2. Rounded obsidian housing (#121615 / Pace.card) + 1pt state-tinted specular border
        let housingRect = CGRect(x: -hw, y: -hh, width: hw * 2, height: hh * 2)
        let housingPath = Path(roundedRect: housingRect, cornerRadius: corner, style: .continuous)

        rootCtx.fill(
            housingPath,
            with: .linearGradient(
                Gradient(colors: [Pace.card, Color(hex: "#121615")]),
                startPoint: CGPoint(x: -hw * 0.5, y: -hh),
                endPoint: CGPoint(x: hw * 0.5, y: hh)
            )
        )

        // Top specular rim sheen inside housing
        var sheenCtx = rootCtx
        sheenCtx.clip(to: housingPath)
        sheenCtx.fill(
            housingPath,
            with: .linearGradient(
                Gradient(colors: [Color.white.opacity(0.085), Color.clear]),
                startPoint: CGPoint(x: 0, y: -hh),
                endPoint: CGPoint(x: 0, y: 0)
            )
        )

        // Ambient radial core glow inside housing
        sheenCtx.fill(
            housingPath,
            with: .radialGradient(
                Gradient(colors: [tone.opacity(0.12), Color.clear]),
                center: .zero,
                startRadius: 0,
                endRadius: max(hw, hh)
            )
        )

        rootCtx.stroke(housingPath, with: .color(border), lineWidth: 1)

        // 3. Precision eye aperture contour + live tracking specular iris/pupil
        let aw = hw * 1.42
        let ahMax = hh * 0.52

        let clampedOpen = max(0, min(1.2, open))
        let effOpen: CGFloat = {
            if state == .sleeping || eyeShape == .closed { return 0 }
            var v = clampedOpen
            switch eyeShape {
            case .tired:  v *= 0.48
            case .flat:   v *= 0.30
            case .wide:   v = min(1.20, v * 1.15)
            case .wink:   v *= 0.68
            default:      break
            }
            if morph > 0.1 && slotOpen > 0.02 {
                v = min(1.24, v + slotOpen * 0.65)
            }
            return v
        }()

        let strokeWidth = max(0.85, min(1.35, R * 0.06))

        if eyeShape == .happy && effOpen > 0.12 {
            // Crisp upward geometric arc for happy / finished moments
            let arcW = aw * 0.86
            let arcH = ahMax * 0.72
            var happyArc = Path()
            happyArc.move(to: CGPoint(x: -arcW / 2, y: arcH * 0.28))
            happyArc.addCurve(
                to: CGPoint(x: arcW / 2, y: arcH * 0.28),
                control1: CGPoint(x: -arcW * 0.22, y: -arcH * 0.92),
                control2: CGPoint(x: arcW * 0.22, y: -arcH * 0.92)
            )
            rootCtx.stroke(
                happyArc,
                with: .color(tone),
                style: StrokeStyle(lineWidth: strokeWidth * 1.25, lineCap: .round)
            )
            // Subtle specular highlight tip at apex
            let apexDot = Path(ellipseIn: CGRect(x: -strokeWidth * 0.6, y: -arcH * 0.64 - strokeWidth * 0.6, width: strokeWidth * 1.2, height: strokeWidth * 1.2))
            rootCtx.fill(apexDot, with: .color(Pace.ink.opacity(0.85)))
        } else if effOpen <= 0.10 {
            // Smoothly closed resting lid / blink slit
            let lidW = aw * 0.84
            let dip: CGFloat = state == .sleeping ? ahMax * 0.22 : ahMax * 0.06
            var closedLine = Path()
            closedLine.move(to: CGPoint(x: -lidW / 2, y: 0))
            closedLine.addCurve(
                to: CGPoint(x: lidW / 2, y: 0),
                control1: CGPoint(x: -lidW * 0.22, y: dip),
                control2: CGPoint(x: lidW * 0.22, y: dip)
            )
            rootCtx.stroke(
                closedLine,
                with: .color(tone.opacity(state == .sleeping ? 0.55 : 0.82)),
                style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round)
            )
        } else {
            // Open precision almond lens contour
            let ah = ahMax * effOpen * max(0.82, min(1.18, eyeScale))
            let ctrlY = ah * 1.333 // Exact apex height = ah at Bezier midpoint t = 0.5
            let ctrlX = aw * 0.25

            var aperture = Path()
            aperture.move(to: CGPoint(x: -aw / 2, y: 0))
            aperture.addCurve(
                to: CGPoint(x: aw / 2, y: 0),
                control1: CGPoint(x: -ctrlX, y: -ctrlY),
                control2: CGPoint(x: ctrlX, y: -ctrlY)
            )
            aperture.addCurve(
                to: CGPoint(x: -aw / 2, y: 0),
                control1: CGPoint(x: ctrlX, y: ctrlY),
                control2: CGPoint(x: -ctrlX, y: ctrlY)
            )
            aperture.closeSubpath()

            // Deep obsidian optical recess inside the eye contour
            rootCtx.fill(aperture, with: .color(Pace.ground))

            // Clipped live-tracking iris, pupil, and dual specular catchlights
            var irisCtx = rootCtx
            irisCtx.clip(to: aperture)

            let gx = max(-1, min(1, gazeX))
            let gy = max(-1, min(1, gazeY))
            let maxShiftX = aw * 0.23
            let maxShiftY = ahMax * 0.34
            let ix = gx * maxShiftX
            let iy = -gy * maxShiftY // +gazeY = up (-y in canvas space)

            // Resolve iris accent: state tone is authoritative; subtle session tint only in calm idle if non-white
            let irisColor: Color = {
                guard state == .idle else { return tone }
                if let cg = sessionCGColor, let comps = cg.components, comps.count >= 3 {
                    let isWhite = comps[0] > 0.92 && comps[1] > 0.92 && comps[2] > 0.92
                    if !isWhite { return Pace.mint }
                }
                if let hex = sessionHex {
                    let norm = hex.uppercased()
                    if norm != "#FFFFFF" && norm != "FFFFFF" { return Pace.mint }
                }
                return tone
            }()

            let irisR = R * 0.35 * max(0.85, min(1.16, eyeScale))
            let irisRect = CGRect(x: ix - irisR, y: iy - irisR, width: irisR * 2, height: irisR * 2)
            let irisPath = Path(ellipseIn: irisRect)

            irisCtx.fill(
                irisPath,
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: irisColor.opacity(0.32), location: 0.0),
                        .init(color: irisColor.opacity(0.78), location: 0.72),
                        .init(color: irisColor.opacity(0.95), location: 1.0),
                    ]),
                    center: CGPoint(x: ix, y: iy),
                    startRadius: 0,
                    endRadius: irisR
                )
            )
            irisCtx.stroke(irisPath, with: .color(irisColor), lineWidth: max(0.75, strokeWidth * 0.85))

            // Optical pupil with subtle forward lens parallax
            let pupilR = irisR * (eyeShape == .wide ? 0.38 : 0.46)
            let px = ix * 1.12
            let py = iy * 1.12
            let pupilRect = CGRect(x: px - pupilR, y: py - pupilR, width: pupilR * 2, height: pupilR * 2)
            irisCtx.fill(Path(ellipseIn: pupilRect), with: .color(Color(hex: "#050706")))

            // Primary specular catchlight + secondary opposite pinpoint reflection
            let hl1R = max(0.75, irisR * 0.21)
            let hl1Rect = CGRect(
                x: px - irisR * 0.30 - hl1R,
                y: py - irisR * 0.30 - hl1R,
                width: hl1R * 2,
                height: hl1R * 2
            )
            irisCtx.fill(Path(ellipseIn: hl1Rect), with: .color(Pace.ink))

            if R >= 8 {
                let hl2R = max(0.5, irisR * 0.095)
                let hl2Rect = CGRect(
                    x: px + irisR * 0.24 - hl2R,
                    y: py + irisR * 0.22 - hl2R,
                    width: hl2R * 2,
                    height: hl2R * 2
                )
                irisCtx.fill(Path(ellipseIn: hl2Rect), with: .color(Color.white.opacity(0.62)))
            }

            // Crisp aperture rim contour on top
            rootCtx.stroke(
                aperture,
                with: .linearGradient(
                    Gradient(colors: [Pace.ink.opacity(0.86), tone.opacity(0.72)]),
                    startPoint: CGPoint(x: 0, y: -ah),
                    endPoint: CGPoint(x: 0, y: ah)
                ),
                style: StrokeStyle(lineWidth: strokeWidth, lineJoin: .round)
            )
        }

        // 4. Optional status pip at housing corner (for static tiles & mini badges)
        if showBadge && morph < 0.25 {
            let pipR = max(2.0, R * 0.19)
            let bx = hw * 0.82
            let by = -hh * 0.82
            let haloRect = CGRect(x: bx - pipR - 1.2, y: by - pipR - 1.2, width: (pipR + 1.2) * 2, height: (pipR + 1.2) * 2)
            let pipRect = CGRect(x: bx - pipR, y: by - pipR, width: pipR * 2, height: pipR * 2)
            rootCtx.fill(Path(ellipseIn: haloRect), with: .color(Pace.ground))
            rootCtx.fill(Path(ellipseIn: pipRect), with: .color(tone))
        }
    }
}

/// One frame of companion gaze & expression for static surfaces (Widgets, iOS rows).
/// Widgets refresh on a timeline; each tick picks a deterministic pose so the system cross-fades cleanly.
struct MochiPose: Equatable, Sendable {
    var yaw: CGFloat = 0
    var pitch: CGFloat = 0
    var tilt: CGFloat = 0
    var open: CGFloat = 1
    var eye: EyeShape? = nil

    static let neutral = MochiPose()

    static let idlePoses: [MochiPose] = [
        MochiPose(),
        MochiPose(yaw: -0.45),
        MochiPose(yaw: 0.45),
        MochiPose(yaw: -0.3, pitch: -0.25),
        MochiPose(yaw: 0.35, pitch: 0.2, tilt: 0.08),
        MochiPose(pitch: -0.3, tilt: -0.06),
        MochiPose(eye: .closed),                 // blink
        MochiPose(yaw: 0.2, eye: .happy),
        MochiPose(yaw: -0.5, tilt: -0.1),
        MochiPose(yaw: 0.15, pitch: 0.25),
    ]

    /// Deterministic pose per session ID and timeline tick.
    static func idle(id: String, tick: Int) -> MochiPose {
        var hash: UInt64 = 5381
        for byte in id.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        hash = (hash &* 31) &+ UInt64(truncatingIfNeeded: tick &* 7919)
        hash ^= hash >> 13
        return idlePoses[Int(hash % UInt64(idlePoses.count))]
    }
}

extension Color {
    /// Backdrop tile behind `MochiStill` on iOS and Widgets — calibrated to Kodeo Obsidian
    /// while clamping high-luminance brand hexes so contrast never washes out.
    static func mochiTile(hex: String) -> Color {
        guard let c = cgColorFromHex(hex), let comps = c.components, comps.count >= 3 else {
            return Pace.card
        }
        let luminance = 0.2126 * comps[0] + 0.7152 * comps[1] + 0.0722 * comps[2]
        return luminance > 0.7 ? Pace.sunk : Color(hex: hex).opacity(0.22)
    }
}
