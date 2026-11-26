import SwiftUI

/// PACE × Kodeo Obsidian — the product's unified surface system, as Swift.
///
/// One palette for every HeyApex surface. The web app, the HUD, the pill and
/// the Electron overlays read it from `electron/shared/core-themes.css` and
/// `electron/shared/pace.css` in the frontend repository; this is the unified
/// Kodeo Studio Graphite / Pace dark token set for macOS, iOS, Widgets and
/// Notification extensions so every surface speaks one language.
///
/// THE RULE: colour reports STATE, never identity. A surface is obsidian
/// graphite until something is happening, then exactly one tone says what.
/// Mint is rationed — ready, allow, done, verified, or active composer focus.
public enum Pace {

    // MARK: Surfaces (Kodeo Obsidian + Pace)

    /// Sidebar / outer window housing (`--c-sidebar` / `--pace-ground`).
    public static let ground = Color(hex: "#0B0B0D")
    /// Pure notch hardware blend (only where camera housing requires `#000000`).
    public static let notchBlack = Color.black
    /// Stage / canvas surface (`--c-bg`).
    public static let surface = Color(hex: "#131316")
    /// Alias matching `--c-bg`.
    public static let bg = surface
    /// Primary card surface (`--c-card`).
    public static let card = Color(hex: "#1B1B1F")
    /// Recessed field / sunk control surface (`--c-sunk`).
    public static let field = Color(hex: "#25252A")
    /// Alias matching `--c-sunk`.
    public static let sunk = field
    public static let raised = Color.white.opacity(0.055)
    public static let raised2 = Color.white.opacity(0.09)

    // MARK: Ink hierarchy

    /// Primary ink (`--c-ink`).
    public static let ink = Color(hex: "#F4F4F6")
    /// Body / readable prose ink.
    public static let body = Color(hex: "#DCE0E6")
    /// Secondary ink (`--c-ink2`).
    public static let ink2 = Color(hex: "#C8C8D0")
    /// Muted / tertiary ink (`--c-ink3`).
    public static let ink3 = Color(hex: "#9696A0")

    // MARK: Hairlines

    /// Primary 1pt specular hairline (`--c-line` / `--pace-line`).
    public static let line = Color.white.opacity(0.08)
    /// Subtle divider hairline (`--pace-line-2`).
    public static let line2 = Color.white.opacity(0.05)
    /// Interactive control border (`--c-line-ctrl`).
    public static let lineCtrl = Color.white.opacity(0.38)

    // MARK: State tones — colour reports state, never resting decoration

    /// Ready · allow · done · verified · active composer focus (`--c-focus-ring`).
    public static let mint = Color(hex: "#34D399")
    /// Bright readout / personal-best highlight (`--pace-mint`).
    public static let mint2 = Color(hex: "#55F4A6")
    /// Soft mint surface tint for selected chips / active focus glow.
    public static let mintSoft = Color(hex: "#34D399").opacity(0.14)
    /// Recording · hot mic · live capture (`--pace-live`).
    public static let live = Color(hex: "#FF2D43")
    /// The agent is acting (`--pace-act`).
    public static let act = Color(hex: "#3E8BFF")
    /// Thinking / reasoning (`--pace-think`).
    public static let think = Color(hex: "#A77CFF")
    /// Needs you — pending permission or user choice (`--pace-hold`).
    public static let hold = Color(hex: "#FFB020")
    /// Denied / failed / destructive state (`--pace-fail`).
    public static let fail = Color(hex: "#FF6A4D")

    /// Ink to place ON a tone. Never guessed per component.
    public static let onMint = Color(hex: "#04150C")
    public static let onLive = Color(hex: "#FFF2F3")
    public static let onHold = Color(hex: "#1A0F00")

    // MARK: Geometry (Kodeo architectural radii)

    /// Compact badge / kbd / group-box radius.
    public static let r: CGFloat = 6
    /// Interactive control / button / input radius (`--r-ctrl`).
    public static let rCtrl: CGFloat = 8
    /// Bento / panel card radius (`--r-card`).
    public static let rCard: CGFloat = 12
    /// Notch island inner card radius (tighter architectural inset inside the notch).
    public static let rIslandCard: CGFloat = 14
    /// True capsule / stadium pill radius (`--pace-r-pill`).
    public static let rPill: CGFloat = 999

    /// Maps a usage percentage (0...100) to a Pace state tone for UI rendering
    /// without mutating test-locked `ClaudePlanGauge.color(for:)` model strings.
    public static func gaugeTone(for pct: Double?) -> Color {
        guard let pct else { return ink3 }
        if pct >= 80 { return fail }
        if pct >= 50 { return hold }
        return mint
    }
}
