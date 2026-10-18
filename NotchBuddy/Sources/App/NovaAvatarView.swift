import SwiftUI

/// Nova — the dotted avatar, drawn natively.
///
/// This replaces Mochi. Mochi's design, look, expressions and animations are
/// reserved by upstream's LICENSE-ASSETS.md even though the character is drawn
/// in code, so it cannot ship in a HeyApex build; Nova is ours.
///
/// It is a port of the Three.js `initNova3DAvatar`, not a reimplementation: the
/// shell generation, the lobe/ripple displacement, the rotation terms and the
/// eye behaviour are the same expressions with the same constants. What changed
/// is the renderer.
///
/// **Why Canvas and not SceneKit.** The original pushes ~9,300 points through
/// WebGL at 215×200. In the notch this draws at 30pt, where a GPU scene costs a
/// Metal layer, a depth buffer and a second render loop to show roughly a
/// thousand dots. Projecting the same points by hand into a `Canvas` is a few
/// hundred lines of arithmetic per frame and composites with the rest of the
/// SwiftUI tree for free. The shape of this view deliberately matches
/// `FlowMochiView` so it drops into the same call sites.
struct NovaAvatarView: View {
    /// 0 at rest, approaching 1 while speaking or listening. Drives the lobe
    /// amplitude, the eye pulse and the time step, exactly as in the original.
    var energy: Double = 0
    /// Where the eyes look, in normalised screen space (-1...1). The host
    /// decides whether that is the cursor, the active window, or nothing.
    var gaze: CGPoint = .zero
    /// Rest is the common case and it does not need three shells; see `shells`.
    var detailed: Bool = false

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                draw(context: &context,
                     size: size,
                     time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - Geometry

    private struct Dot {
        let x, y, z: Double
        /// 0 = innermost shell (brightest), rising outward.
        let band: Int
    }

    /// Latitude/longitude point shells.
    ///
    /// The original uses three (38×76, 44×88, 34×68 ≈ 9,300 points). At the size
    /// this view is actually used, the third shell lands inside the second's
    /// dots and costs a third of the frame for nothing, so the default is two
    /// coarser shells. `detailed` restores the original counts for the large
    /// case.
    private var shells: [(radius: Double, lat: Int, lon: Int)] {
        detailed
            ? [(1.06, 38, 76), (1.18, 44, 88), (1.30, 34, 68)]
            : [(1.06, 14, 26), (1.21, 12, 22)]
    }

    private var base: [Dot] {
        var out: [Dot] = []
        for (index, shell) in shells.enumerated() {
            for i in 0...shell.lat {
                let theta = Double(i) * .pi / Double(shell.lat)
                let sinTheta = sin(theta), cosTheta = cos(theta)
                for j in 0..<shell.lon {
                    let phi = Double(j) * 2 * .pi / Double(shell.lon)
                    let x = shell.radius * sinTheta * cos(phi)
                    let y = shell.radius * cosTheta
                    let z = shell.radius * sinTheta * sin(phi)
                    // Carve the window the eyes show through. Without it the
                    // front of the innermost shell sits in front of them.
                    if z > 0.75, hypot(x, y * 1.1) < 0.56, index == 0 { continue }
                    out.append(Dot(x: x, y: y, z: z, band: index))
                }
            }
        }
        return out
    }

    // MARK: - Frame

    private func draw(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let side = min(size.width, size.height)
        guard side > 1 else { return }

        let t = time * (1.32 + energy * 2.4)
        let camZ = 4.35
        let focal = 1.0 / tan((42.0 * .pi / 180) / 2)
        let half = side / 2

        let waveAmp = 0.11 + energy * 0.18
        let yaw = gaze.x * 0.55 + sin(t * 0.5) * 0.1
        let pitch = -gaze.y * 0.45 + cos(t * 0.4) * 0.06
        let roll = sin(t * 0.4) * 0.08

        struct Projected { let px, py, r, z: Double; let band: Int; let frontness: Double }
        var dots: [Projected] = []
        dots.reserveCapacity(base.count)

        let dotRadius = side * (detailed ? 0.0062 : 0.013)

        for dot in base {
            let lobe = sin(dot.x * 2.6 + t)
                * cos(dot.y * 2.6 - t * 0.85)
                * sin(dot.z * 2.6 + t * 0.65)
            let ripple = sin((dot.x * dot.x + dot.y * dot.y) * 3.2 - t * 1.8) * 0.04
            let scale = 1 + lobe * waveAmp + ripple * (1 + energy * 1.6)

            var x = dot.x * scale, y = dot.y * scale, z = dot.z * scale
            let cr = cos(roll), sr = sin(roll)
            (x, y) = (x * cr - y * sr, x * sr + y * cr)
            let cy = cos(yaw), sy = sin(yaw)
            (x, z) = (x * cy + z * sy, -x * sy + z * cy)
            let cp = cos(pitch), sp = sin(pitch)
            (y, z) = (y * cp - z * sp, y * sp + z * cp)

            let depth = camZ - z
            guard depth > 0.05 else { continue }
            let frontness = max(0.2, (z + 1.3) / 2.6)
            dots.append(Projected(px: half + x * focal / depth * half,
                                  py: half - y * focal / depth * half,
                                  r: dotRadius * (0.8 + frontness * 0.45),
                                  z: z, band: dot.band, frontness: frontness))
        }

        // Painter's algorithm, because a Canvas has no depth buffer. The WebGL
        // original relies on a dark SphereGeometry(0.92) sitting inside the
        // shells to hide the far side; dropping it was what turned this into a
        // white blob — every back dot drew over the front ones and additive
        // blending saturated the lot.
        //
        // Order: far dots, then that core, then near dots, then the eyes. The
        // eye sprites use depthTest:false upstream, which is "always on top".
        let core = CORE_RADIUS * focal / (camZ) * half

        func paint(_ subset: [Projected]) {
            var paths = [Path(), Path(), Path()]
            for d in subset {
                paths[d.band].addEllipse(in: CGRect(x: d.px - d.r, y: d.py - d.r,
                                                    width: d.r * 2, height: d.r * 2))
            }
            for (index, path) in paths.enumerated() where !path.isEmpty {
                context.fill(path, with: .color(bandColor(index)))
            }
        }

        paint(dots.filter { $0.z < 0 })

        context.fill(
            Path(ellipseIn: CGRect(x: half - core, y: half - core, width: core * 2, height: core * 2)),
            with: .color(Color(red: 0.020, green: 0.027, blue: 0.035).opacity(0.94))
        )

        paint(dots.filter { $0.z >= 0 })

        drawEyes(context: &context, side: side, focal: focal, camZ: camZ, t: t)
    }

    /// The dark inner sphere's radius in the original.
    private let CORE_RADIUS = 0.92

    /// Per-shell colour. Normal blending rather than additive: additive needs a
    /// depth-sorted GPU to stay readable, and at 34pt it just clips to white.
    private func bandColor(_ index: Int) -> Color {
        switch index {
        case 0:  return Color(red: 0.97, green: 0.99, blue: 1.00).opacity(0.97)
        case 1:  return Color(red: 0.72, green: 0.92, blue: 0.90).opacity(0.72)
        default: return Color(red: 0.42, green: 0.66, blue: 0.64).opacity(0.52)
        }
    }

    private func drawEyes(context: inout GraphicsContext, side: CGFloat,
                          focal: Double, camZ: Double, t: TimeInterval) {
        let half = side / 2
        let blink = blinkFactor(at: t)
        let pulse = 1 + energy * 0.22 * sin(t * 8)
        let scaleY = max(0.05, 0.46 * blink * pulse)

        for sign in [-1.0, 1.0] {
            let ex = sign * 0.27 + gaze.x * 0.32
            let ey = 0.02 + gaze.y * 0.28
            let depth = camZ - 0.94
            let px = half + ex * focal / depth * half
            let py = half - ey * focal / depth * half
            let w = 0.32 * focal / depth * half
            let h = scaleY * focal / depth * half
            let rect = CGRect(x: px - w / 2, y: py - h / 2, width: w, height: h)
            // A soft pass under a hard one: the sprite texture was a white
            // capsule inside a glow, and two fills is the cheapest way to say
            // the same thing.
            context.fill(Path(ellipseIn: rect.insetBy(dx: -w * 0.5, dy: -h * 0.35)),
                         with: .color(.white.opacity(0.16)))
            context.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.97)))
        }
    }

    /// Eyes close roughly every 2–4 seconds and the blink itself is fast.
    ///
    /// The original counts frames down to a random next blink. Derived from the
    /// clock instead so it does not drift with frame rate, and so this view
    /// holds no mutable state.
    private func blinkFactor(at t: TimeInterval) -> Double {
        let period = 3.1
        let phase = t.truncatingRemainder(dividingBy: period)
        let blinkLength = 0.22
        guard phase < blinkLength else { return 1 }
        return abs(cos(.pi * phase / blinkLength))
    }
}

#Preview {
    HStack(spacing: 18) {
        NovaAvatarView().frame(width: 30, height: 30)
        NovaAvatarView(energy: 0.85).frame(width: 30, height: 30)
        NovaAvatarView(energy: 0.4, detailed: true).frame(width: 120, height: 120)
    }
    .padding(26)
    .background(Color.black)
}

// MARK: - What a bot state looks like

extension BotState {
    /// How much Nova should move for this state.
    ///
    /// One mapping for every surface, so the pill, the minis and the hub cannot
    /// drift into disagreeing about what "working" looks like. The scale is the
    /// avatar's `energy`: 0 is still, 1 is the speaking peak.
    ///
    /// Grouped by what the user should FEEL, not by how the states are named:
    /// something waiting on them moves most, something in progress moves
    /// steadily, something stopped barely moves at all.
    var novaEnergy: Double {
        switch self {
        case .idle:                       return 0
        case .sleeping:                   return 0
        // Waiting on a person. This is the only group allowed to be loud,
        // because it is the only group a person has to act on.
        case .approval, .question:        return 0.78
        // In progress. Enough motion to read as alive across a room, not
        // enough to pull the eye off whatever the user is actually doing.
        case .working, .thinking,
             .searching:                  return 0.42
        // Stopped, and not going anywhere without help.
        case .error, .dizzy, .ratelimit:  return 0.5
        case .finished:                   return 0.3
        }
    }
}
