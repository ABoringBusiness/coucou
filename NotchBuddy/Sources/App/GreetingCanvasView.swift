import SwiftUI

// MARK: - HeyApex Eye × Vesper Ignition Sequence
//
// Bespoke launch boot sequence for HeyApex Eye (640×150 notch stage).
// Replaces the legacy Coucou character/music intro completely:
//   0.00 → 0.36s : Carved obsidian stage + Pace Mint specular horizon sweep from the camera bore
//   0.06 → 0.88s : Vesper Fibonacci fluid torus ignites at center (x=320) with concentric aurora
//                  iris rings, then glides smoothly into its companion cradle (x=60, y=92)
//   0.46 → 1.95s : Kodeo × Pace telemetry readout + crisp vector integration badges materialize
//   2.05s        : Fires .greetComplete so IslandStateMachine folds cleanly to compact notch

private enum VesperBootTiming {
    static let stageInEnd:   Double = 0.36
    static let glideStart:   Double = 0.34
    static let glideEnd:     Double = 0.88
    static let textInStart:  Double = 0.48
    static let textInEnd:    Double = 0.92
    static let end:          Double = 2.05
    static let autoLeave:    Double = 2.25
    static let collapseDur:  Double = 0.30
}

private func vbClamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
    max(lo, min(hi, v))
}

private func vbSeg(_ t: Double, _ a: Double, _ b: Double) -> Double {
    guard b > a else { return t >= b ? 1 : 0 }
    return vbClamp((t - a) / (b - a), 0, 1)
}

private func vbEaseOutCubic(_ x: Double) -> Double {
    1 - pow(1 - x, 3)
}

private func vbEaseInOutCubic(_ x: Double) -> Double {
    x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
}

struct GreetingCanvasView: View {
    @ObservedObject var state: AppState

    @State private var startDate = Date()
    @State private var collapseAt: Double = .infinity
    @State private var greetFired = false
    @State private var doneWork: DispatchWorkItem? = nil

    private var previewTasks: [AgentTask] {
        Array(state.tasks.prefix(4))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            let foldProgress: Double = collapseAt.isFinite
                ? vbEaseOutCubic(vbSeg(t, collapseAt, collapseAt + VesperBootTiming.collapseDur))
                : 0
            let visibility = 1.0 - foldProgress

            let stageAlpha = vbEaseOutCubic(vbSeg(t, 0.02, VesperBootTiming.stageInEnd)) * visibility
            let sweepProgress = vbSeg(t, 0.0, 0.72)
            let glide = vbEaseInOutCubic(vbSeg(t, VesperBootTiming.glideStart, VesperBootTiming.glideEnd))

            let orbScale = (0.42 + 0.58 * vbEaseOutCubic(vbSeg(t, 0.04, 0.44))) * (1.0 - 0.35 * foldProgress)
            let orbAlpha = vbEaseOutCubic(vbSeg(t, 0.02, 0.24)) * visibility
            let orbX = 320.0 + (62.0 - 320.0) * glide
            let orbY = 88.0 + (92.0 - 88.0) * glide
            let orbEnergy = 0.85 - 0.40 * glide

            let copyAlpha = vbEaseOutCubic(vbSeg(t, VesperBootTiming.textInStart, VesperBootTiming.textInEnd)) * visibility
            let copyOffset = (1.0 - vbEaseOutCubic(vbSeg(t, VesperBootTiming.textInStart, VesperBootTiming.textInEnd))) * 8.0

            ZStack(alignment: .topLeading) {
                // 1. Carved obsidian stage + concentric aurora ignition rings + specular rim sweep
                Canvas(opaque: false) { ctx, _ in
                    let cardRect = CGRect(x: 12, y: 38, width: 616, height: 100)
                    let cardPath = Path(roundedRect: cardRect, cornerRadius: Pace.rIslandCard)

                    if stageAlpha > 0.005 {
                        var stageCtx = ctx
                        stageCtx.opacity = stageAlpha
                        stageCtx.fill(cardPath, with: .color(Color.white.opacity(0.032)))
                        stageCtx.stroke(cardPath, with: .color(Pace.line), lineWidth: 1)

                        // Subtle bottom mint ambient wash during ignition
                        let washStrength = (1.0 - vbSeg(t, 0.65, 1.85)) * 0.14
                        if washStrength > 0.002 {
                            var washCtx = stageCtx
                            washCtx.clip(to: cardPath)
                            let grad = Gradient(stops: [
                                .init(color: Pace.mint.opacity(washStrength), location: 0),
                                .init(color: Pace.act.opacity(washStrength * 0.45), location: 0.48),
                                .init(color: .clear, location: 1)
                            ])
                            washCtx.fill(
                                Path(cardRect),
                                with: .radialGradient(
                                    grad,
                                    center: CGPoint(x: orbX, y: cardRect.maxY + 12),
                                    startRadius: 4,
                                    endRadius: 240
                                )
                            )
                        }
                    }

                    // Specular top-notch horizon sweep
                    if sweepProgress > 0 && sweepProgress < 1 {
                        let halfSpan = CGFloat(vbEaseOutCubic(sweepProgress)) * 296
                        let fade = (1.0 - sweepProgress) * visibility
                        var line = Path()
                        line.move(to: CGPoint(x: 320 - halfSpan, y: 38.5))
                        line.addLine(to: CGPoint(x: 320 + halfSpan, y: 38.5))
                        let rimGrad = Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Pace.act.opacity(0.55 * fade), location: 0.25),
                            .init(color: Pace.mint.opacity(0.85 * fade), location: 0.5),
                            .init(color: Pace.act.opacity(0.55 * fade), location: 0.75),
                            .init(color: .clear, location: 1)
                        ])
                        ctx.stroke(
                            line,
                            with: .linearGradient(
                                rimGrad,
                                startPoint: CGPoint(x: 320 - halfSpan, y: 38.5),
                                endPoint: CGPoint(x: 320 + halfSpan, y: 38.5)
                            ),
                            lineWidth: 1.25
                        )
                    }

                    // Concentric Vesper iris shock-rings on ignition (0.08 → 0.95s)
                    for ringIdx in 0..<2 {
                        let delay = Double(ringIdx) * 0.14
                        let p = vbSeg(t, 0.08 + delay, 0.92 + delay)
                        guard p > 0 && p < 1 else { continue }
                        let eased = vbEaseOutCubic(p)
                        let rx = CGFloat(22.0 + eased * 145.0)
                        let ry = rx * 0.58
                        let alpha = (1.0 - p) * 0.34 * visibility
                        let tone = ringIdx == 0 ? Pace.mint : Pace.act
                        let ellipse = Path(ellipseIn: CGRect(
                            x: CGFloat(orbX) - rx,
                            y: CGFloat(orbY) - ry,
                            width: rx * 2,
                            height: ry * 2
                        ))
                        var ringCtx = ctx
                        ringCtx.clip(to: cardPath)
                        ringCtx.stroke(ellipse, with: .color(tone.opacity(alpha)), lineWidth: 1.1)
                    }
                }
                .frame(width: 640, height: 150)

                // 2. Crisp Kodeo × Pace telemetry readout (right of Vesper cradle)
                if copyAlpha > 0.005 {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 7) {
                                Circle()
                                    .fill(Pace.mint)
                                    .frame(width: 6, height: 6)
                                    .shadow(color: Pace.mint.opacity(0.65), radius: 5)
                                Text("HeyApex Eye")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(Pace.ink)
                                Text("ONLINE")
                                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Pace.mint)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Pace.mintSoft)
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                                            .stroke(Pace.mint.opacity(0.28), lineWidth: 1)
                                    )
                            }
                            Text("Agent & workspace telemetry ready · Click notch or hold 3s")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Pace.ink3)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        // Vector task badges (zero mini-blobs)
                        HStack(spacing: 6) {
                            ForEach(Array(previewTasks.enumerated()), id: \.1.id) { idx, task in
                                let badgeReveal = vbEaseOutCubic(
                                    vbSeg(t, VesperBootTiming.textInStart + 0.08 + Double(idx) * 0.055,
                                          VesperBootTiming.textInEnd + 0.12 + Double(idx) * 0.055)
                                )
                                MiniBotCanvasView(task: task, size: 24)
                                    .opacity(badgeReveal)
                                    .scaleEffect(0.82 + 0.18 * badgeReveal)
                            }
                        }
                    }
                    .padding(.leading, 114)
                    .padding(.trailing, 28)
                    .frame(width: 640, height: 100, alignment: .leading)
                    .offset(x: copyOffset, y: 38)
                    .opacity(copyAlpha)
                }

                // 3. Vesper Fibonacci Fluid Torus companion
                NovaAvatarView(
                    energy: orbEnergy,
                    detailed: true,
                    bodyScale: 0.86,
                    tone: VesperTone(botState: state.effectiveState),
                    fpsCap: 60
                )
                .frame(width: 68, height: 68)
                .scaleEffect(orbScale)
                .opacity(orbAlpha)
                .position(x: orbX, y: orbY)
            }
            .frame(width: 640, height: 150)
            .onChange(of: !greetFired && t >= VesperBootTiming.end && collapseAt >= VesperBootTiming.autoLeave) { _, trigger in
                if trigger { fireGreetComplete() }
            }
        }
        .onAppear {
            startDate = Date()
            collapseAt = .infinity
            greetFired = false
            if state.soundEnabled {
                SoundEngine.shared.play("peek")
            }
            let item = DispatchWorkItem { fireGreetComplete() }
            doneWork = item
            DispatchQueue.main.asyncAfter(deadline: .now() + VesperBootTiming.end + 0.05, execute: item)
        }
        .onDisappear {
            doneWork?.cancel()
            doneWork = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            if collapseAt >= VesperBootTiming.autoLeave { collapseAt = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            let t = Date().timeIntervalSince(startDate)
            if collapseAt.isInfinite || collapseAt > t { collapseAt = t }
            doneWork?.cancel()
            doneWork = nil
        }
    }

    private func fireGreetComplete() {
        guard !greetFired else { return }
        greetFired = true
        doneWork?.cancel()
        doneWork = nil
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }
}
