import SwiftUI

/// PACE — the product's surface system, as Swift.
///
/// One palette for every HeyApex surface. The web app, the HUD, the pill and
/// the twelve Electron overlays read it from `electron/shared/pace.css` in the
/// frontend repository; this is the same set of values for the Mac app, so a
/// tone means the same thing in both places. Nothing here is new: it is that
/// file's `:root` block, dark set.
///
/// THE RULE: colour reports STATE, never identity. A surface is graphite until
/// something is happening, then exactly one tone says what. Mint is rationed —
/// it means done, or ready, or you beat something. If mint is on every surface
/// it means nothing.
///
/// Lives in CoucouKit rather than beside the window so every target can reach
/// it; `HubTheme` (macOS only, behind `#if !APPSTORE`) reads from here.
public enum Pace {

    // MARK: Ground and ink

    public static let ground = Color(hex: "#07090A")
    public static let surface = Color(hex: "#0C100F")
    public static let card = Color(hex: "#121615")
    public static let field = Color(hex: "#171B1A")
    public static let raised = Color.white.opacity(0.055)
    public static let raised2 = Color.white.opacity(0.09)
    public static let ink = Color(hex: "#F2F6F4")
    public static let ink2 = Color(hex: "#8B9792")
    public static let ink3 = Color(hex: "#59635E")
    /// ONE hairline. Every border in the system is this or a tone.
    public static let line = Color.white.opacity(0.10)
    public static let line2 = Color.white.opacity(0.055)

    // MARK: Tone — the only colour on screen

    /// Ready · done · you beat something.
    public static let mint = Color(hex: "#55F4A6")
    /// The personal-best stamp only.
    public static let mint2 = Color(hex: "#2DE38B")
    /// Recording · hot mic · the agent has your cursor.
    public static let live = Color(hex: "#FF2D43")
    /// The agent is acting.
    public static let act = Color(hex: "#3E8BFF")
    /// Working on it.
    public static let think = Color(hex: "#A77CFF")
    /// Needs you — a decision only you can make.
    public static let hold = Color(hex: "#FFB020")
    /// It did not work.
    public static let fail = Color(hex: "#FF6A4D")

    /// Ink to place ON a tone. Never guessed per component.
    public static let onMint = Color(hex: "#04150C")
    public static let onLive = Color(hex: "#FFF2F3")

    // MARK: Geometry

    /// ONE radius.
    public static let r: CGFloat = 5
    public static let rPill: CGFloat = 999
}
