import SwiftUI

enum VesperTone {
    case normal
    case approval
    case error

    init(botState: BotState) {
        switch botState {
        case .approval, .question, .ratelimit:
            self = .approval
        case .error, .dizzy:
            self = .error
        default:
            self = .normal
        }
    }
}

struct NovaAvatarView: View {
    var energy: Double = 0
    var gaze: CGPoint = .zero
    var detailed: Bool = false
    var particleOverhang: CGFloat = 0
    var bodyScale: CGFloat = 0.86
    var tone: VesperTone = .normal
    var fpsCap: Double = 60
    var paused: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.9 / max(15, fpsCap), paused: paused)) { timeline in
            Canvas(opaque: false, rendersAsynchronously: false) { context, size in
                drawVesper(
                    context: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate
                )
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private struct Sample {
        let x: Double
        let y: Double
        let z: Double
    }

    private static let detailedSamples: [Sample] = makeFibonacci(count: 680)
    private static let compactSamples: [Sample] = makeFibonacci(count: 180)

    private static func makeFibonacci(count: Int) -> [Sample] {
        var list: [Sample] = []
        list.reserveCapacity(count)
        let golden = Double.pi * (3.0 - sqrt(5.0))
        let denom = Double(max(1, count - 1))
        for i in 0..<count {
            let y = 1.0 - (Double(i) / denom) * 2.0
            let r = sqrt(max(0.0, 1.0 - y * y))
            let theta = golden * Double(i)
            let x = cos(theta) * r
            let z = sin(theta) * r
            list.append(Sample(x: x, y: y, z: z))
        }
        return list
    }

    private func palette() -> (top: (Double, Double, Double), mid: (Double, Double, Double), bottom: (Double, Double, Double)) {
        switch tone {
        case .normal:
            return (
                top: (0.08, 0.94, 0.52),
                mid: (0.12, 0.82, 0.96),
                bottom: (0.24, 0.18, 0.96)
            )
        case .approval:
            return (
                top: (1.00, 0.84, 0.28),
                mid: (1.00, 0.62, 0.16),
                bottom: (0.92, 0.28, 0.22)
            )
        case .error:
            return (
                top: (1.00, 0.46, 0.38),
                mid: (0.96, 0.22, 0.30),
                bottom: (0.58, 0.08, 0.24)
            )
        }
    }

    private func drawVesper(context: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let availH = max(1.0, size.height - particleOverhang)
        let boxSide = min(size.width, availH)
        let diameter = boxSide * bodyScale
        guard diameter > 2 else { return }

        let cx = size.width * 0.5
        let cy = particleOverhang + availH * 0.5
        let maxR = diameter * 0.5

        let speed = 0.85 + energy * 1.35
        let t = time * speed
        let pal = palette()

        let topColor = Color(red: pal.top.0, green: pal.top.1, blue: pal.top.2)
        let midColor = Color(red: pal.mid.0, green: pal.mid.1, blue: pal.mid.2)
        let botColor = Color(red: pal.bottom.0, green: pal.bottom.1, blue: pal.bottom.2)

        let shiftX = gaze.x * maxR * 0.08
        let shiftY = -gaze.y * maxR * 0.08
        let ringCenter = CGPoint(x: cx + shiftX, y: cy + shiftY)

        // 1. Soft ambient aurora halo behind the torus
        let haloRect = CGRect(
            x: ringCenter.x - maxR * 0.96,
            y: ringCenter.y - maxR * 0.96,
            width: maxR * 1.92,
            height: maxR * 1.92
        )
        let gradStart = CGPoint(x: ringCenter.x, y: ringCenter.y - maxR * 0.88)
        let gradEnd = CGPoint(x: ringCenter.x, y: ringCenter.y + maxR * 0.88)
        let verticalGrad = Gradient(stops: [
            .init(color: topColor.opacity(0.26), location: 0.0),
            .init(color: midColor.opacity(0.22), location: 0.52),
            .init(color: botColor.opacity(0.26), location: 1.0)
        ])
        var haloPath = Path()
        haloPath.addEllipse(in: haloRect.insetBy(dx: maxR * 0.14, dy: maxR * 0.14))
        context.stroke(
            haloPath,
            with: .linearGradient(verticalGrad, startPoint: gradStart, endPoint: gradEnd),
            lineWidth: max(1.6, maxR * 0.34)
        )

        // 2. Continuous undulating Vesper wave-ribbons around the hollow axial bore
        let ringCount = detailed ? 7 : 4
        let segs = detailed ? 64 : 36
        let deform = 0.085 + energy * 0.065

        for band in 0..<ringCount {
            let frac = Double(band) / Double(max(1, ringCount - 1))
            let baseFrac = 0.46 + frac * 0.38
            let phase = Double(band) * 0.72
            var wavePath = Path()
            for s in 0...segs {
                let ang = (Double(s) / Double(segs)) * Double.pi * 2.0
                let w1 = sin(ang * 3.0 + t * 1.15 + phase) * 0.52
                let w2 = cos(ang * 5.0 - t * 0.88 - phase * 0.7) * 0.32
                let w3 = sin(ang * 7.0 + t * 1.62 + phase * 1.3) * 0.16
                let disp = (w1 + w2 + w3) * deform
                let r = Double(maxR) * min(0.95, baseFrac * (1.0 + disp))
                let px = Double(ringCenter.x) + cos(ang) * r
                let py = Double(ringCenter.y) + sin(ang) * r
                if s == 0 {
                    wavePath.move(to: CGPoint(x: px, y: py))
                } else {
                    wavePath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            wavePath.closeSubpath()

            let alpha = 0.24 + sin(frac * Double.pi) * 0.38
            let ribbonGrad = Gradient(stops: [
                .init(color: topColor.opacity(alpha), location: 0.0),
                .init(color: midColor.opacity(alpha * 0.95), location: 0.5),
                .init(color: botColor.opacity(alpha), location: 1.0)
            ])
            let strokeW = max(1.0, maxR * (detailed ? 0.095 : 0.14))
            context.stroke(
                wavePath,
                with: .linearGradient(ribbonGrad, startPoint: gradStart, endPoint: gradEnd),
                style: StrokeStyle(lineWidth: strokeW, lineCap: .round, lineJoin: .round)
            )
        }

        // 3. Volumetric Fibonacci cloud (exact VESPER_ORB_VERT bore & displacement)
        let samples = detailed ? Self.detailedSamples : Self.compactSamples
        let yaw = Double(gaze.x) * 0.42 + t * 0.22
        let pitch = Double(-gaze.y) * 0.34 + sin(t * 0.18) * 0.28
        let cyaw = cos(yaw), syaw = sin(yaw)
        let cpitch = cos(pitch), spitch = sin(pitch)

        let orbDeform = 0.14 + energy * 0.18
        let boreBase = 0.36 + energy * 0.08
        let bucketCount = 6
        var buckets = Array(repeating: Path(), count: bucketCount)
        let puffR = max(0.85, Double(maxR) * (detailed ? 0.068 : 0.105))

        for p in samples {
            let n1 = sin(p.x * 2.3 + t * 0.92) * cos(p.y * 2.3 - t * 0.74) * sin(p.z * 2.3 + t * 0.61)
            let n2 = sin((p.x + p.y) * 4.2 - t * 1.4) * 0.32
            let disp = n1 * 0.72 + n2 * 0.28
            let sc = 1.0 + orbDeform * disp

            let sx = p.x * sc
            let sy = p.y * sc
            let sz = p.z * sc

            let rx = sx * cyaw + sz * syaw
            let rz0 = -sx * syaw + sz * cyaw
            let ry = sy * cpitch - rz0 * spitch
            let rz = sy * spitch + rz0 * cpitch

            let radial = hypot(rx, ry)
            let bore = boreBase * (1.0 + disp * 0.38)
            if radial < bore { continue }

            let clampedScale = min(0.95 / max(0.001, radial), 0.78)
            let px = Double(ringCenter.x) + rx * Double(maxR) * clampedScale
            let py = Double(ringCenter.y) - ry * Double(maxR) * clampedScale

            let vt = max(0.0, min(1.0, ry * 0.5 + 0.5))
            let idx = min(bucketCount - 1, max(0, Int(vt * Double(bucketCount))))
            let depthScale = 0.75 + max(0.0, (rz + 1.0) * 0.25)
            let pr = puffR * depthScale
            buckets[idx].addEllipse(in: CGRect(x: px - pr, y: py - pr, width: pr * 2.0, height: pr * 2.0))
        }

        for idx in 0..<bucketCount where !buckets[idx].isEmpty {
            let vt = (Double(idx) + 0.5) / Double(bucketCount)
            let c: (Double, Double, Double)
            if vt >= 0.5 {
                let k = (vt - 0.5) * 2.0
                c = (
                    pal.mid.0 + (pal.top.0 - pal.mid.0) * k,
                    pal.mid.1 + (pal.top.1 - pal.mid.1) * k,
                    pal.mid.2 + (pal.top.2 - pal.mid.2) * k
                )
            } else {
                let k = vt * 2.0
                c = (
                    pal.bottom.0 + (pal.mid.0 - pal.bottom.0) * k,
                    pal.bottom.1 + (pal.mid.1 - pal.bottom.1) * k,
                    pal.bottom.2 + (pal.mid.2 - pal.bottom.2) * k
                )
            }
            let puffAlpha = detailed ? 0.24 : 0.32
            context.fill(buckets[idx], with: .color(Color(red: c.0, green: c.1, blue: c.2).opacity(puffAlpha)))
        }
    }
}

#Preview {
    HStack(spacing: 18) {
        NovaAvatarView().frame(width: 30, height: 30)
        NovaAvatarView(energy: 0.85, tone: .approval).frame(width: 30, height: 30)
        NovaAvatarView(energy: 0.45, detailed: true).frame(width: 96, height: 96)
    }
    .padding(26)
    .background(Color.black)
}

extension BotState {
    var novaEnergy: Double {
        switch self {
        case .idle, .sleeping:
            return 0.08
        case .approval, .question:
            return 0.78
        case .working, .thinking, .searching:
            return 0.45
        case .error, .dizzy, .ratelimit:
            return 0.52
        case .finished:
            return 0.25
        }
    }
}
