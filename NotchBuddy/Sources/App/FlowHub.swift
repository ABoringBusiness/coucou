#if !APPSTORE
import AppKit
import Carbon
import SwiftUI

/// The pages of the Coucou window: Flow (the dictation, the Notetaker) and the notch's settings.
enum HubPage: String, CaseIterable, Identifiable {
    case dictation, notes, insights, dictionary, snippets, styles, settings
    case general, pills, agents, chat, integrations, voice, shortcuts

    var id: String { rawValue }

    static let flowPages: [HubPage] = [.dictation, .notes, .insights, .dictionary, .snippets, .styles, .settings]
    static let notchPages: [HubPage] = [.general, .pills, .agents, .chat, .integrations, .voice, .shortcuts]

    /// The section of Settings this page shows, for the notch's pages.
    var settingsSection: String? {
        switch self {
        case .general:      return "general"
        case .pills:        return "activepills"
        case .agents:       return "agents"
        case .chat:         return "chat"
        case .integrations: return "integrations"
        case .voice:        return "voice"
        case .shortcuts:    return "shortcuts"
        default:            return nil
        }
    }

    /// The page showing a section of Settings ("chat", "voice"…).
    static func forSettings(_ section: String) -> HubPage {
        notchPages.first { $0.settingsSection == section } ?? .general
    }

    var title: String {
        switch self {
        case .general:      return String(localized: "General")
        case .pills:        return String(localized: "Active pills")
        case .agents:       return String(localized: "Agents")
        case .chat:         return String(localized: "Chat")
        case .integrations: return String(localized: "Integrations")
        case .voice:        return String(localized: "Voice")
        case .shortcuts:    return String(localized: "Shortcuts")
        case .dictation:  return String(localized: "hub.page.dictation")
        case .notes:      return String(localized: "hub.page.notes")
        case .insights:   return String(localized: "hub.page.insights")
        case .dictionary: return String(localized: "hub.page.dictionary")
        case .snippets:   return String(localized: "hub.page.snippets")
        case .styles:     return String(localized: "hub.page.styles")
        case .settings:   return String(localized: "hub.page.settings")
        }
    }

    var symbol: String {
        switch self {
        case .dictation:  return "mic"
        case .notes:      return "record.circle"
        case .insights:   return "chart.bar"
        case .dictionary: return "book.closed"
        case .snippets:   return "bolt"
        case .styles:     return "textformat"
        case .settings:   return "slider.horizontal.3"
        case .general:      return "gearshape"
        case .pills:        return "square.grid.2x2"
        case .agents:       return "terminal"
        case .chat:         return "bubble.left.and.bubble.right"
        case .integrations: return "puzzlepiece.extension"
        case .voice:        return "waveform"
        case .shortcuts:    return "keyboard"
        }
    }
}

/// The window's surface system: PACE, the same one the HeyApex HUD, the pill
/// and the twelve web surfaces use (electron/shared/pace.css in the frontend
/// repository). The names here are unchanged so upstream merges keep applying;
/// only the values moved, from an orange-accented generic dark theme onto the
/// product's own palette.
///
/// THE RULE, carried over from pace.css: colour reports STATE, never identity.
/// The window is graphite until something is happening, then exactly one tone
/// says what. Mint is rationed — ready, done, you beat something. The old
/// `accent` orange was on every control at rest, which made it mean nothing;
/// orange survives as `hold`, which is the one thing it was ever saying.
enum HubTheme {
    /// Pace --pace-ground. Not pure black: the island's near-black.
    static let window = Pace.ground
    static let sidebar = Pace.ground
    /// The big card on the right, where the pages are. --pace-surface, opaque.
    static let panel = Pace.bg
    static let card = Pace.card
    static let field = Pace.sunk
    /// ONE hairline. --pace-line.
    static let line = Pace.line
    static let text = Pace.ink
    static let body = Pace.body
    static let secondary = Pace.ink2
    static let muted = Pace.ink3
    /// --pace-mint: ready · done · you beat something.
    static let accent = Pace.mint
    static let onAccent = Pace.onMint
    static let green = Pace.mint
    static let red = Pace.fail

    /// The state tones. Every one of them is a pace.css tone, and a control at
    /// rest wears none of them.
    /// Recording · hot mic · the agent has your cursor.
    static let live = Pace.live
    /// The agent is acting.
    static let act = Pace.act
    /// Working on it.
    static let think = Pace.think
    /// Needs you — a decision only you can make.
    static let hold = Pace.hold
    /// It did not work.
    static let fail = Pace.fail

    /// Kodeo architectural radii.
    static let r = Pace.r
    static let rCtrl = Pace.rCtrl
    static let rCard = Pace.rCard
    static let rPill = Pace.rPill

    /// One color per person in a call: you first, then the others. This is the
    /// one place identity, not state, picks the colour, so the tones are the
    /// pace set rather than a second palette.
    static let speakers: [Color] = [Pace.act, Pace.mint, Pace.think, Pace.hold, Pace.live, Pace.mint2]

    static func speaker(_ index: Int) -> Color { speakers[max(0, index) % speakers.count] }
}

/// Every `GroupBox` in the window, reskinned in one place.
///
/// The settings pages build 32 of them and upstream keeps adding more; styling
/// them through the environment means a new one is on Pace the day it lands,
/// with no diff of ours in the file that declares it.
struct PaceGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(HubTheme.secondary)
            configuration.content
                .foregroundColor(HubTheme.body)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous).fill(HubTheme.card))
        .overlay(
            RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous)
                .strokeBorder(HubTheme.line)
        )
    }
}

private struct HubPageKey: EnvironmentKey {
    static let defaultValue: HubPage = .dictation
}

extension EnvironmentValues {
    /// The page shown, for the colour and the Mochis of its top band.
    var hubPage: HubPage {
        get { self[HubPageKey.self] }
        set { self[HubPageKey.self] = newValue }
    }
}

extension HubPage {
    /// The line under the title of the notch's pages.
    static func notchSubtitle(_ page: HubPage) -> String? {
        switch page {
        case .general:      return String(localized: "hub.notch.general")
        case .pills:        return String(localized: "hub.notch.pills")
        case .agents:       return String(localized: "hub.notch.agents")
        case .chat:         return String(localized: "hub.notch.chat")
        case .integrations: return String(localized: "hub.notch.integrations")
        case .voice:        return String(localized: "hub.notch.voice")
        case .shortcuts:    return String(localized: "hub.notch.shortcuts")
        default:            return nil
        }
    }
}

@MainActor
final class HubRouter: ObservableObject {
    @Published var page: HubPage = .dictation
}

/// Opens the Coucou Flow window: the history of the dictations, the Notetaker, the numbers, the
/// dictionary, the snippets, the styles and the settings of the dictation.
@MainActor
final class FlowHubController {
    static let shared = FlowHubController()
    let router = HubRouter()
    let windowState = HubWindowState()
    private var window: NSWindow?

    static let showInDockKey = "coucouShowInDock"
    static let openAtLaunchKey = "coucouOpenAtLaunch"

    /// HeyApex Eye in the Dock: off by default when HeyApex Desktop is installed so only one
    /// HeyApex icon occupies the Dock and HeyApex Eye runs cleanly as an accessory companion.
    static var showInDock: Bool {
        get {
            if let stored = UserDefaults.standard.object(forKey: showInDockKey) as? Bool {
                return stored
            }
            return !HeyApexHost.isDesktopInstalled
        }
        set {
            UserDefaults.standard.set(newValue, forKey: showInDockKey)
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
            if newValue { NSApp.activate(ignoringOtherApps: true) }
        }
    }

    /// Off by default so launching HeyApex Eye does not pop open a second desktop window over HeyApex.
    static var openAtLaunch: Bool {
        get { UserDefaults.standard.object(forKey: openAtLaunchKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: openAtLaunchKey) }
    }

    /// Whether macOS opened Coucou at login, rather than you from the Finder, the Dock or Spotlight.
    static func launchedAtLogin() -> Bool {
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue == OSType(keyAELaunchedAsLogInItem) {
            return true
        }
        // A login item started by launchd may come without that flag: the first minutes after
        // the Mac starts count as a login.
        return ProcessInfo.processInfo.systemUptime < 180
    }

    func show(_ page: HubPage? = nil) {
        if let page { router.page = page }
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                           backing: .buffered, defer: false)
        win.title = "HeyApex Eye"
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.appearance = NSAppearance(named: .darkAqua)
        win.backgroundColor = NSColor(Pace.ground)
        win.contentView = NSHostingView(rootView: FlowHubView(router: router, windowState: windowState))
        windowState.watch(win)
        win.contentMinSize = NSSize(width: 940, height: 600)
        win.isReleasedWhenClosed = false
        win.setFrameAutosaveName("CoucouFlowWindow")
        if !win.setFrameUsingName("CoucouFlowWindow") { win.center() }
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct FlowHubView: View {
    @ObservedObject var router: HubRouter
    @ObservedObject var windowState: HubWindowState

    var body: some View {
        HStack(spacing: 0) {
            HubSidebar(router: router)
            // The pages sit in one big card, like Wispr Flow's window.
            page
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous)
                        .fill(HubTheme.panel)
                )
                .clipShape(RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous).strokeBorder(Pace.line))
                .padding(.top, 10)
                .padding(.bottom, 10)
                .padding(.trailing, 10)
        }
        .background(HubTheme.window)
        .foregroundColor(HubTheme.text)
        .preferredColorScheme(.dark)
        .tint(HubTheme.accent)
        .groupBoxStyle(PaceGroupBoxStyle())
        .environment(\.hubVisible, windowState.visible)
        .environment(\.hubPage, router.page)
    }

    @ViewBuilder private var page: some View {
        switch router.page {
        case .dictation:  HubHomePage(router: router)
        case .notes:      HubNotesPage()
        case .insights:   HubInsightsPage()
        case .dictionary: HubDictionaryPage()
        case .snippets:   HubSnippetsPage()
        case .styles:     HubStylesPage(router: router)
        case .settings:   HubSettingsPage()
        default:
            if let section = router.page.settingsSection {
                VStack(alignment: .leading, spacing: 0) {
                    HubHero(page: router.page, title: router.page.title, subtitle: HubPage.notchSubtitle(router.page))
                        .padding(.horizontal, 28)
                        .padding(.top, 24)
                    SettingsView(embeddedSection: section)
                        .id(section)
                }
            }
        }
    }
}

// MARK: - Sidebar

private struct HubSidebar: View {
    @ObservedObject var router: HubRouter
    @ObservedObject private var flow = FlowDictation.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                HubMochi(size: 26)
                Text(verbatim: "HeyApex Eye")
                    .font(.system(size: 17, weight: .bold))
            }
            .padding(.horizontal, 8)
            .padding(.top, 25)
            .padding(.bottom, 31)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    HubSidebarHeader(text: "Flow")
                    ForEach(HubPage.flowPages) { page in
                        HubSidebarItem(page: page, selected: router.page == page) { router.page = page }
                    }
                    HubSidebarHeader(text: String(localized: "hub.section.notch"))
                        .padding(.top, 14)
                    ForEach(HubPage.notchPages) { page in
                        HubSidebarItem(page: page, selected: router.page == page) { router.page = page }
                    }
                }
            }
            .scrollIndicators(.never)
            status
                .padding(.top, 8)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 228)
        .frame(maxHeight: .infinity)
        .background(HubTheme.sidebar)
    }

    @ViewBuilder private var status: some View {
        let ready = flow.isEnabled && flow.trusted
        Button { router.page = .settings } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(ready ? HubTheme.green : (flow.isEnabled ? HubTheme.hold : HubTheme.muted))
                    .frame(width: 7, height: 7)
                Text(ready ? String(format: String(localized: "hub.status-ready %@"), flow.key.label)
                     : (flow.isEnabled ? String(localized: "hub.status-access") : String(localized: "hub.status-off")))
                    .font(.system(size: 12))
                    .foregroundColor(HubTheme.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous).fill(HubTheme.card))
            .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous).strokeBorder(Pace.line))
        }
        .buttonStyle(.plain)
    }
}

/// Calm sentence-case section header above a group of pages.
private struct HubSidebarHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundColor(HubTheme.muted)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }
}

private struct HubSidebarItem: View {
    let page: HubPage
    let selected: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: page.symbol)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                Text(page.title)
                    .font(.system(size: 14, weight: selected ? .semibold : .regular))
                Spacer(minLength: 0)
            }
            .foregroundColor(selected ? HubTheme.text : HubTheme.secondary)
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                .fill(selected ? Pace.raised2 : (hover ? Pace.raised : Color.clear)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - Shared pieces

/// HeyApex Eye emblem rendered via the shared `MochiStill` / `HeyApexEyeGlyph` specular glyph.
struct HubMochi: View {
    var size: CGFloat = 28

    var body: some View {
        MochiStill(state: .idle, showBadge: false)
            .frame(width: size, height: size)
    }
}

/// A page: its title, an optional line under it, and the content, scrolling.
struct HubPageScaffold<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    @Environment(\.hubPage) private var page

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HubHero(page: page, title: title, subtitle: subtitle, trailing: trailing)
                content()
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .scrollIndicators(.automatic)
    }
}

extension HubPageScaffold where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = { EmptyView() }
        self.content = content
    }
}

/// A dark rounded card.
struct HubCard<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content() }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous).fill(HubTheme.card))
            .overlay(RoundedRectangle(cornerRadius: Pace.rCard, style: .continuous).strokeBorder(HubTheme.line))
    }
}

/// Calm sentence-case label above a section or list.
struct HubLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(HubTheme.secondary)
    }
}

/// A row of a settings card: the label on the left, the control on the right.
struct HubRow<Control: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder var control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(HubTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.vertical, 2)
    }
}

struct HubDivider: View {
    var body: some View { Rectangle().fill(Pace.line2).frame(height: 1) }
}

/// Mint (primary) or sunken obsidian (secondary) button.
struct HubButtonStyle: ButtonStyle {
    var primary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: primary ? .bold : .semibold))
            .foregroundColor(primary ? HubTheme.onAccent : HubTheme.text)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                .fill(primary ? HubTheme.accent : Pace.sunk))
            .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                .strokeBorder(primary ? Color.clear : Pace.line))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
    }
}

/// A small square icon button (copy, delete).
struct HubIconButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(hover ? HubTheme.text : HubTheme.muted)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous)
                    .fill(hover ? Pace.raised2 : Pace.raised))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .onHover { hover = $0 }
    }
}

/// A text field drawn like the rest of the window.
struct HubField: View {
    let placeholder: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 13))
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous).fill(HubTheme.field))
            .overlay(RoundedRectangle(cornerRadius: Pace.rCtrl, style: .continuous).strokeBorder(Pace.line))
            .onSubmit(onSubmit)
    }
}

/// Lays its children out in rows, wrapping to the next row when one is full (the dictionary's words).
struct HubWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

extension NSPasteboard {
    /// Copies plain text, as the copy buttons of the window do.
    @MainActor static func copyText(_ text: String) {
        general.clearContents()
        general.setString(text, forType: .string)
    }
}
#endif
