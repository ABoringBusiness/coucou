import SwiftUI
import AppKit

// Full 640×176 canvas that drives the upload sequence animation.
// Replaces the header + content area when the upload engine is active.

struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    @State private var fileIcon: NSImage? = nil

    private var engine: UploadSequenceEngine { .shared }

    var body: some View {
        TimelineView(.animation) { tl in
            let f = engine.frame(at: tl.date)
            let wallTime = tl.date.timeIntervalSinceReferenceDate

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawScene(ctx: ctx, f: f, wallTime: wallTime)
                }
                .frame(width: 640, height: 176)

                // Interactive choose buttons (invisible hit areas at reference positions)
                if f.chooseAlpha > 0 {
                    chooseOverlay(f: f)
                        .frame(width: 640, height: 176)
                }
            }
        }
        .onChange(of: state.droppedFile?.url) { _, url in
            if let url { loadIcon(url: url) }
        }
        .onAppear {
            if let url = state.droppedFile?.url { loadIcon(url: url) }
        }
        .frame(width: 640, height: 176)
    }

    // MARK: - File icon

    private func loadIcon(url: URL) {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 64, height: 64)
        fileIcon = img
    }

    // MARK: - Choose overlay (transparent SwiftUI buttons over canvas)

    @ViewBuilder
    private func chooseOverlay(f: USFrame) -> some View {
        // Reference positions: button1 x=100 w=176 y=113 h=26, button2 x=284 w=128
        ZStack(alignment: .topLeading) {
            // Primary: "Ask a question about it"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { state.view = .prompt }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                Color.clear
                    .frame(width: 168, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 168, height: 26)
            .position(x: 114 + 84, y: 113 + 13)   // center = (198, 126)

            // Secondary: "Send by email"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { state.view = .mail }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                Color.clear
                    .frame(width: 120, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 120, height: 26)
            .position(x: 290 + 60, y: 113 + 13)   // center = (350, 126)
        }
        .opacity(f.chooseAlpha)
        .allowsHitTesting(f.chooseAlpha > 0.5)
    }

    // MARK: - Main draw

    private func drawScene(ctx: GraphicsContext, f: USFrame, wallTime: Double = 0) {
        var c = ctx

        // ── Island background ──────────────────────────────────────
        c.fill(Path(CGRect(x:0, y:0, width:640, height:176)), with: .color(Pace.notchBlack))

        // ── Card ──────────────────────────────────────────────────
        let cardPath = roundedRect(CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H), r: USC.CARD_R)

        var cardCtx = c
        cardCtx.clip(to: cardPath)
        cardCtx.fill(Path(CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H)),
                     with: .color(Pace.card))

        // Mint glow from card bottom — grows slowly with upload progress
        if f.greenWash > 0 {
            // Center at card bottom edge; gradient fans upward through the card
            let gx = USC.CARD_X + USC.CARD_W/2
            let gy = USC.CARD_Y + USC.CARD_H   // bottom of card
            let gGrad = Gradient(stops: [
                .init(color: Pace.mint.opacity(f.greenWash * 0.90), location:0),
                .init(color: Pace.mint.opacity(f.greenWash * 0.30), location:0.55),
                .init(color: Pace.mint.opacity(0), location:1)
            ])
            cardCtx.fill(Path(CGRect(x:USC.CARD_X,y:USC.CARD_Y,width:USC.CARD_W,height:USC.CARD_H)),
                         with: .radialGradient(gGrad, center:CGPoint(x:gx,y:gy),
                                              startRadius:0, endRadius:USC.CARD_H*1.5))
        }

        // ── Dashed border (animates left→right while on drop zone) ────
        if f.zoneAlpha > 0 {
            var borderCtx = c
            borderCtx.opacity = f.zoneAlpha
            let borderColor = f.zoneOver
                ? Pace.mint.opacity(0.55)
                : Pace.line
            let inset = CGRect(x: USC.CARD_X+0.75, y: USC.CARD_Y+0.75,
                               width: USC.CARD_W-1.5, height: USC.CARD_H-1.5)
            // dashPhase increases → pattern marches left-to-right at ~20 pt/s
            let dashPhase = CGFloat(wallTime * 20)
            borderCtx.stroke(roundedRect(inset, r: USC.CARD_R-0.5),
                             with: .color(borderColor),
                             style: StrokeStyle(lineWidth:1.5, dash:[6,5], dashPhase: dashPhase))
        }

        // ── Drop zone text ─────────────────────────────────────────
        if f.zoneAlpha > 0 && f.textAlpha > 0 {
            drawDropText(ctx: &c, f: f)
        }

        // ── Progress bar ──────────────────────────────────────────
        if f.barAlpha > 0 || f.barReveal > 0 {
            drawProgressBar(ctx: &c, f: f)
        }

        // ── Choose view text ─────────────────────────────────────
        if f.chooseAlpha > 0 {
            drawChooseView(ctx: &c, f: f)
        }

        // ── Vesper gravitational portal ───────────────────────────
        drawVesperPortal(ctx: &c, f: f, wallTime: wallTime)

        // ── File / orbital absorption ─────────────────────────────
        if f.fileVisible { drawFile(ctx: &c, f: f) }
    }

    // MARK: - Drop zone text + chips

    private func drawDropText(ctx: inout GraphicsContext, f: USFrame) {
        var tCtx = ctx
        tCtx.opacity = f.textAlpha

        let label = Text("Drop your files here")
            .font(.system(size:13, weight:.medium))
            .foregroundColor(Pace.body)
        tCtx.draw(label, at: CGPoint(x: USC.TEXT_X, y: USC.TEXT_Y - 4), anchor: .leading)

        let chips = ["PDF","Images","Code","Docs"]
        var cx = USC.TEXT_X
        for chip in chips {
            let chipText = Text(chip).font(.system(size:11, weight:.medium)).foregroundColor(Pace.ink2)
            // measure approximate width
            let estW = Double(chip.count) * 6.5 + 16
            tCtx.fill(roundedRect(CGRect(x:cx, y:USC.TEXT_Y+9, width:estW, height:18), r:9),
                      with: .color(Pace.raised))
            tCtx.draw(chipText, at: CGPoint(x: cx + 8, y: USC.TEXT_Y + 18), anchor: .leading)
            cx += estW + 6
        }
    }

    // MARK: - Progress bar

    private func drawProgressBar(ctx: inout GraphicsContext, f: USFrame) {
        var pCtx = ctx
        pCtx.opacity = max(f.barAlpha, 0.001)

        let x0 = USC.BAR_X0, x1 = USC.BAR_X1, by = USC.BAR_Y
        let barLen = (x1-x0) * f.barReveal

        // Filename label
        let name = state.droppedFile?.name ?? "file"
        let label = Text("Uploading \(name)")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Pace.ink2)
        pCtx.draw(label, at: CGPoint(x: x0, y: by-30), anchor: .leading)

        // Checkmark or percentage
        if f.check > 0 {
            var ckCtx = pCtx
            ckCtx.concatenate(CGAffineTransform(translationX: CGFloat(x1-8), y: CGFloat(by-30)))
            ckCtx.concatenate(CGAffineTransform(scaleX: CGFloat(f.check), y: CGFloat(f.check)))
            var circle = Path(); circle.addEllipse(in: CGRect(x:-8,y:-8,width:16,height:16))
            ckCtx.fill(circle, with: .color(Pace.mint))
            var ck = Path()
            ck.move(to: CGPoint(x:-3.6,y:0.2)); ck.addLine(to: CGPoint(x:-1,y:2.8)); ck.addLine(to: CGPoint(x:3.8,y:-2.6))
            ckCtx.stroke(ck, with: .color(Pace.onMint),
                         style: StrokeStyle(lineWidth:2, lineCap:.round, lineJoin:.round))
        } else {
            let pct = Text("\(Int(f.progress*100)) %")
                .font(.system(size:12.5, weight:.medium).monospacedDigit())
                .foregroundColor(Pace.ink2)
            pCtx.draw(pct, at: CGPoint(x: x1, y: by-30), anchor: .trailing)
        }

        // Bar track
        if barLen > 0 {
            pCtx.fill(roundedRect(CGRect(x:x0, y:by-3, width:barLen, height:6), r:3),
                      with: .color(Pace.line))
        }

        // Bar fill
        let fx = usLerp(USC.BAR_X0, USC.BAR_X1, f.progress)
        if fx > x0 + 1 {
            let fillGrad = Gradient(stops: [
                .init(color: Pace.mint, location:0),
                .init(color: f.flash > 0.25 ? Pace.mint2 : Pace.mint, location:1)
            ])
            pCtx.fill(roundedRect(CGRect(x:x0, y:by-3, width:fx-x0, height:6), r:3),
                      with: .linearGradient(fillGrad,
                                           startPoint: CGPoint(x:x0, y:0),
                                           endPoint:   CGPoint(x:fx,  y:0)))
        }

        // Glow trail
        if f.progress > 0.01 && f.progress < 1 {
            let v = (usProgressAt(f.t+0.01, progStart:USC.T_PROG_START, progEnd:f.progEnd)
                   - usProgressAt(f.t,      progStart:USC.T_PROG_START, progEnd:f.progEnd)) / 0.01
            let tl = max(8, min(34, 8 + v*40))
            let tGrad = Gradient(stops:[
                .init(color: Pace.mint.opacity(0), location:0),
                .init(color: Pace.mint2.opacity(0.6), location:1)
            ])
            var glowCtx = pCtx
            glowCtx.addFilter(.blur(radius:3))
            glowCtx.fill(roundedRect(CGRect(x:fx-tl, y:by-4, width:tl, height:8), r:4),
                         with: .linearGradient(tGrad,
                                              startPoint:CGPoint(x:fx-tl,y:0),
                                              endPoint:  CGPoint(x:fx,y:0)))
        }
    }

    // MARK: - Choose view text + buttons (canvas layer)

    private func drawChooseView(ctx: inout GraphicsContext, f: USFrame) {
        var cCtx = ctx
        cCtx.opacity = f.chooseAlpha
        // Slide up: translate down by (1-alpha)*4
        cCtx.concatenate(CGAffineTransform(translationX: 0, y: CGFloat((1-f.chooseAlpha)*4)))

        let name = state.droppedFile?.name ?? "file"
        let titleText = Text("\(name) is ready.")
            .font(.system(size:14, weight:.semibold))
            .foregroundColor(Pace.ink)
        cCtx.draw(titleText, at: CGPoint(x:114, y:80), anchor: .leading)

        let subText = Text("What do you want to do with it?")
            .font(.system(size:12.5))
            .foregroundColor(Pace.ink3)
        cCtx.draw(subText, at: CGPoint(x:114, y:100), anchor: .leading)

        // Primary button (mint fill)
        cCtx.fill(roundedRect(CGRect(x:114,y:113,width:168,height:26), r:Double(Pace.rCtrl)),
                  with: .color(Pace.mint))
        let btn1 = Text("Ask a question about it")
            .font(.system(size:12.5, weight:.semibold))
            .foregroundColor(Pace.onMint)
        cCtx.draw(btn1, at: CGPoint(x:198, y:126), anchor: .center)

        // Secondary button (dim fill)
        cCtx.fill(roundedRect(CGRect(x:290,y:113,width:120,height:26), r:Double(Pace.rCtrl)),
                  with: .color(Pace.raised2))
        let btn2 = Text("Send by email")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Pace.ink)
        cCtx.draw(btn2, at: CGPoint(x:350, y:126), anchor: .center)
    }

    // MARK: - Vesper gravitational portal (replaces legacy Mochi mouth-suction)

    private func drawVesperPortal(ctx: inout GraphicsContext, f: USFrame, wallTime: Double) {
        let baseR = max(14.0, f.d * 0.50)
        let apertureBoost = 1.0 + 0.24 * max(0, min(1, f.mouth)) + 0.08 * max(0, min(1, f.morph))
        let maxR = CGFloat(baseR * apertureBoost)
        let center = CGPoint(
            x: CGFloat(f.x + f.lookX * 3.5),
            y: CGFloat(f.y + f.hop + f.lookY * 2.5)
        )

        let topColor = Color(red: 0.08, green: 0.94, blue: 0.52)
        let midColor = Color(red: 0.12, green: 0.82, blue: 0.96)
        let botColor = Color(red: 0.24, green: 0.18, blue: 0.96)
        let gradStart = CGPoint(x: center.x, y: center.y - maxR)
        let gradEnd   = CGPoint(x: center.x, y: center.y + maxR)

        // 1. Ambient aurora halo
        var halo = Path()
        halo.addEllipse(in: CGRect(
            x: center.x - maxR * 0.86,
            y: center.y - maxR * 0.86,
            width: maxR * 1.72,
            height: maxR * 1.72
        ))
        ctx.stroke(
            halo,
            with: .linearGradient(
                Gradient(stops: [
                    .init(color: topColor.opacity(0.28), location: 0),
                    .init(color: midColor.opacity(0.22), location: 0.5),
                    .init(color: botColor.opacity(0.28), location: 1)
                ]),
                startPoint: gradStart,
                endPoint: gradEnd
            ),
            lineWidth: max(2.0, maxR * 0.30)
        )

        // 2. Undulating Vesper wave-ribbons around the dark axial bore
        let ringCount = 6
        let segs = 56
        let t = wallTime * (1.2 + 0.9 * max(0, min(1, f.mouth + f.suck)))
        let deform = 0.09 + 0.06 * max(0, min(1, f.mouth))

        for band in 0..<ringCount {
            let frac = Double(band) / Double(ringCount - 1)
            let baseFrac = 0.44 + frac * 0.42
            let phase = Double(band) * 0.75
            var wavePath = Path()
            for s in 0...segs {
                let ang = (Double(s) / Double(segs)) * Double.pi * 2.0
                let w1 = sin(ang * 3.0 + t * 1.15 + phase) * 0.52
                let w2 = cos(ang * 5.0 - t * 0.88 - phase * 0.7) * 0.32
                let w3 = sin(ang * 7.0 + t * 1.62 + phase * 1.3) * 0.16
                let r = Double(maxR) * min(0.96, baseFrac * (1.0 + (w1 + w2 + w3) * deform))
                let px = Double(center.x) + cos(ang) * r
                let py = Double(center.y) + sin(ang) * r
                if s == 0 {
                    wavePath.move(to: CGPoint(x: px, y: py))
                } else {
                    wavePath.addLine(to: CGPoint(x: px, y: py))
                }
            }
            wavePath.closeSubpath()
            let alpha = 0.26 + sin(frac * Double.pi) * 0.42
            ctx.stroke(
                wavePath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: topColor.opacity(alpha), location: 0),
                        .init(color: midColor.opacity(alpha * 0.95), location: 0.5),
                        .init(color: botColor.opacity(alpha), location: 1)
                    ]),
                    startPoint: gradStart,
                    endPoint: gradEnd
                ),
                style: StrokeStyle(lineWidth: max(1.1, maxR * 0.10), lineCap: .round, lineJoin: .round)
            )
        }

        // 3. Deep obsidian bore center
        let boreR = maxR * 0.34
        let bore = Path(ellipseIn: CGRect(
            x: center.x - boreR,
            y: center.y - boreR,
            width: boreR * 2,
            height: boreR * 2
        ))
        ctx.fill(bore, with: .color(Pace.notchBlack.opacity(0.92)))
    }

    // MARK: - File / Vesper bore absorption

    private func drawFile(ctx: inout GraphicsContext, f: USFrame) {
        let cx = f.cursorX, cy = f.cursorY + 14
        if f.suck <= 0 {
            var fc = ctx
            fc.opacity = 0.94
            drawDoc(ctx: &fc, cx: cx, cy: cy, wsc: 1, hsc: 1)
            return
        }

        let k = max(0, min(1, f.suck))
        let ease = usEInOut(k)
        let fx = usLerp(cx, f.x, ease)
        let fy = usLerp(cy, f.y + f.hop, ease)
        let scale = max(0.08, 1.0 - 0.88 * usEIn(k))
        let fade = max(0, 1.0 - pow(k, 1.6))

        var fc = ctx
        fc.opacity = fade
        fc.translateBy(x: CGFloat(fx), y: CGFloat(fy))
        fc.rotate(by: .radians(k * 0.55))
        fc.translateBy(x: CGFloat(-fx), y: CGFloat(-fy))
        drawDoc(ctx: &fc, cx: fx, cy: fy, wsc: scale, hsc: scale)

        // Orbital Pace Mint & Cyan energy motes converging into the Vesper bore
        for i in 0..<6 {
            let a = Double(i) / 6.0 * .pi * 2.0 + k * 2.4
            let r0 = 28.0
            let pk = max(0, min(1, (k - Double(i) * 0.06) / 0.72))
            guard pk > 0 && pk < 1 else { continue }
            let sx0 = cx + cos(a) * r0
            let sy0 = cy + sin(a) * r0
            let kk = pow(pk, 0.72)
            let px = usLerp(sx0, f.x, kk)
            let py = usLerp(sy0, f.y + f.hop, kk) - sin(.pi * pk) * 5
            let rad = 2.1 * (1 - pk * 0.5)
            let dot = Path(ellipseIn: CGRect(x: px - rad, y: py - rad, width: rad * 2, height: rad * 2))
            let tone = i.isMultiple(of: 2) ? Pace.mint : Pace.act
            ctx.fill(dot, with: .color(tone.opacity(1 - pk)))
        }
    }

    // MARK: - Doc icon (SwiftUI wrapper)

    private func drawDoc(ctx: inout GraphicsContext, cx: Double, cy: Double, wsc: Double, hsc: Double) {
        let w = 34*wsc, h = 42*hsc
        let x = cx-w/2, y = cy-h/2
        let fold = 8*min(wsc,hsc)

        var bodyCtx = ctx
        bodyCtx.addFilter(.shadow(color:.black.opacity(0.45), radius:8, x:0, y:3))
        var body = Path()
        body.move(to: CGPoint(x:x+2,y:y))
        body.addLine(to: CGPoint(x:x+w-fold,y:y))
        body.addLine(to: CGPoint(x:x+w,y:y+fold))
        body.addLine(to: CGPoint(x:x+w,y:y+h-2))
        body.addQuadCurve(to: CGPoint(x:x+w-2,y:y+h), control:CGPoint(x:x+w,y:y+h))
        body.addLine(to: CGPoint(x:x+2,y:y+h))
        body.addQuadCurve(to: CGPoint(x:x,y:y+h-2), control:CGPoint(x:x,y:y+h))
        body.addLine(to: CGPoint(x:x,y:y+2))
        body.addQuadCurve(to: CGPoint(x:x+2,y:y), control:CGPoint(x:x,y:y))
        body.closeSubpath()
        bodyCtx.fill(body, with: .color(Color(red:0.957,green:0.957,blue:0.965)))

        var foldPath = Path()
        foldPath.move(to: CGPoint(x:x+w-fold,y:y))
        foldPath.addLine(to: CGPoint(x:x+w-fold,y:y+fold))
        foldPath.addLine(to: CGPoint(x:x+w,y:y+fold))
        ctx.fill(foldPath, with: .color(Color(red:0.835,green:0.839,blue:0.859)))

        ctx.fill(roundedRect(CGRect(x:x+w*0.18,y:y+h*0.58,width:w*0.64,height:h*0.16),r:2),
                 with: .color(Color(red:0.231,green:0.510,blue:0.961)))
    }
}

// MARK: - Rounded rect helper (mirrors reference rr())

func roundedRect(_ rect: CGRect, r rr: Double) -> Path {
    let r = max(0, min(rr, Double(rect.width)/2, Double(rect.height)/2))
    var p = Path()
    p.addRoundedRect(in: rect, cornerSize: CGSize(width:r, height:r))
    return p
}
