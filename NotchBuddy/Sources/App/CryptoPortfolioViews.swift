import SwiftUI
import AppKit
import CryptoKit

// MARK: - Card: mode switch

/// "Prices | Portfolio" in the Crypto card header, once an account is connected.
struct CryptoModeSwitch: View {
    @Binding var mode: String

    var body: some View {
        HStack(spacing: 2) {
            item("prices", String(localized: "crypto.mode.prices"))
            item("portfolio", String(localized: "crypto.mode.portfolio"))
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
    }

    private func item(_ value: String, _ title: String) -> some View {
        Button { mode = value } label: {
            Text(verbatim: title)
                .font(.system(size: 10, weight: mode == value ? .semibold : .regular))
                .foregroundColor(Color(hex: mode == value ? "#F5F6F8" : "#8E939C"))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(Color.white.opacity(mode == value ? 0.10 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Card: portfolio

/// What the connected accounts hold: the total and its 24 h change, then each coin with
/// its amount, value and 24 h change, biggest first. Amounts can be hidden (eye button).
struct CryptoPortfolioList: View {
    @ObservedObject private var portfolio = CryptoPortfolio.shared
    @AppStorage("cryptoHideAmounts") private var hidden = false

    private var currency: String { CryptoSettings.currency }

    var body: some View {
        if portfolio.lines.isEmpty {
            Text(emptyText)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .padding(.top, 8)
                .padding(.leading, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                totalRow
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(portfolio.lines) { line in
                            PortfolioRow(line: line, hidden: hidden, currency: currency)
                        }
                        if let problem = problemText {
                            Text(verbatim: problem)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#4D5159"))
                                .lineLimit(1).truncationMode(.tail)
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        if !portfolio.loaded { return String(localized: "Loading…") }
        if portfolio.states.values.contains(where: { $0.error == nil && $0.blockedRights == nil }) {
            return String(localized: "crypto.portfolio.empty")
        }
        return String(localized: "crypto.portfolio.unavailable")
    }

    /// "Binance: Invalid API-key…" for the first account that couldn't be read.
    private var problemText: String? {
        for account in portfolio.accounts {
            guard let state = portfolio.states[account.id] else { continue }
            if state.blockedRights != nil {
                return String(format: String(localized: "crypto.portfolio.blocked %@"), account.displayName)
            }
            if let error = state.error { return "\(account.displayName) : \(error)" }
        }
        return nil
    }

    private var totalRow: some View {
        HStack(spacing: 6) {
            Text(verbatim: hidden ? "•••••" : CryptoController.format(portfolio.total, currency: currency))
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
            if let change = portfolio.totalChange {
                Text(verbatim: CryptoController.formatChange(change))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: change >= 0 ? "#22C55E" : "#F4505E"))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            Spacer(minLength: 2)
            Button { hidden.toggle() } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 18, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(hidden ? String(localized: "crypto.portfolio.show") : String(localized: "crypto.portfolio.hide"))
        }
        .padding(.horizontal, 8)
    }
}

/// One coin: symbol, amount held, value, 24 h change. A click opens its page on the exchange.
private struct PortfolioRow: View {
    let line: CryptoPortfolio.Line
    let hidden: Bool
    let currency: String
    @State private var hovered = false

    var body: some View {
        let change = line.change
        let tone = Color(hex: (change ?? 0) >= 0 ? "#22C55E" : "#F4505E")
        Button {
            let exchange = CryptoSettings.exchange
            if let url = exchange.tradeURL(exchange.pair(line.asset, currency)) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 6) {
                Text(verbatim: line.asset)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#E8E9EC"))
                    .lineLimit(1)
                    .frame(width: 38, alignment: .leading)
                Text(verbatim: hidden ? "•••" : CryptoPortfolio.formatAmount(line.amount))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .monospacedDigit()
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(verbatim: line.value.map { hidden ? "•••" : CryptoController.format($0, currency: currency) } ?? "—")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                Text(verbatim: change.map(CryptoController.formatChange) ?? "")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(tone)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white.opacity(hovered ? 0.05 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Settings: accounts

/// Settings → Integrations → Crypto: the connected accounts, and the form to add one.
/// An exchange key is checked before it is saved: it must only be able to read.
struct CryptoAccountsSettings: View {
    @ObservedObject private var portfolio = CryptoPortfolio.shared
    @State private var draft: CryptoAccount?
    @State private var checking = false
    @State private var message: String?
    @State private var messageIsWarning = false
    /// Binance: a key pair made by Coucou (Ed25519, recommended by Binance) or an HMAC key.
    @State private var binanceEd25519 = true
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(String(localized: "crypto.accounts.title"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                if draft == nil {
                    Menu(String(localized: "crypto.accounts.add")) {
                        Section(String(localized: "crypto.accounts.exchanges")) {
                            ForEach(CryptoVenue.exchanges, id: \.self) { venue in
                                Button(venue.name) { start(venue) }
                            }
                        }
                        Section(String(localized: "crypto.accounts.wallets")) {
                            ForEach(CryptoVenue.wallets, id: \.self) { venue in
                                Button(venue.name) { start(venue) }
                            }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            ForEach(portfolio.accounts) { account in
                accountRow(account)
            }

            if draft != nil {
                form
            }

            Text(String(localized: "crypto.accounts.hint"))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#8E939C"))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Rows

    private func accountRow(_ account: CryptoAccount) -> some View {
        let state = portfolio.states[account.id]
        return HStack(spacing: 6) {
            Image(systemName: account.venue.isWallet ? "wallet.bifold" : "building.columns")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: account.label.isEmpty ? account.venue.name : "\(account.label) · \(account.venue.name)")
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let rights = state?.blockedRights {
                    Text(String(format: String(localized: "crypto.accounts.blocked %@"), rights.joined(separator: ", ")))
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let error = state?.error {
                    Text(verbatim: error)
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                        .lineLimit(2)
                } else if account.venue.isWallet {
                    Text(verbatim: shortAddress(account.address))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                } else if account.venue == .kraken {
                    Text(String(localized: "crypto.accounts.kraken-unchecked"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                } else {
                    Text(String(localized: "crypto.accounts.read-only"))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Button(String(localized: "crypto.accounts.remove")) { portfolio.remove(account.id) }
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func shortAddress(_ address: String) -> String {
        address.count > 16 ? "\(address.prefix(8))…\(address.suffix(6))" : address
    }

    // MARK: Form

    @ViewBuilder private var form: some View {
        if let venue = draft?.venue {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(verbatim: venue.name).font(.system(size: 11, weight: .semibold))
                    if let url = venue.keyPageURL {
                        Link(venue.isWallet ? String(localized: "crypto.accounts.explorer")
                                            : String(localized: "crypto.accounts.open-api-page"),
                             destination: url)
                            .font(.system(size: 10))
                    }
                }
                Text(Self.help(venue))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                TextField(String(localized: "crypto.accounts.label-placeholder"), text: binding(\.label))
                    .textFieldStyle(.roundedBorder)
                if venue.regions.count > 1 {
                    Picker(String(localized: "crypto.accounts.region"), selection: binding(\.region)) {
                        ForEach(venue.regions, id: \.id) { r in
                            Text(verbatim: r.label).tag(r.id)
                        }
                    }
                }
                if venue.isWallet {
                    TextField(String(localized: "crypto.accounts.address"), text: binding(\.address))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                } else if venue == .binance && binanceEd25519 {
                    // Coucou made the key pair: the private key never leaves this Mac.
                    Picker(String(localized: "crypto.accounts.key-type"), selection: $binanceEd25519) {
                        Text(String(localized: "crypto.accounts.key-ed25519")).tag(true)
                        Text(String(localized: "crypto.accounts.key-hmac")).tag(false)
                    }
                    Text(String(localized: "crypto.accounts.public-key"))
                        .font(.system(size: 10, weight: .semibold))
                    HStack(alignment: .top, spacing: 6) {
                        Text(verbatim: publicKeyPEM)
                            .font(.system(size: 9.5, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(copied ? String(localized: "crypto.accounts.copied") : String(localized: "crypto.accounts.copy")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(publicKeyPEM, forType: .string)
                            copied = true
                        }
                        .controlSize(.small)
                    }
                    TextField(String(localized: "crypto.accounts.api-key"), text: binding(\.apiKey))
                        .textFieldStyle(.roundedBorder)
                } else {
                    if venue == .binance {
                        Picker(String(localized: "crypto.accounts.key-type"), selection: $binanceEd25519) {
                            Text(String(localized: "crypto.accounts.key-ed25519")).tag(true)
                            Text(String(localized: "crypto.accounts.key-hmac")).tag(false)
                        }
                    }
                    TextField(venue == .coinbase ? String(localized: "crypto.accounts.coinbase-key-name")
                                                 : String(localized: "crypto.accounts.api-key"),
                              text: binding(\.apiKey))
                        .textFieldStyle(.roundedBorder)
                    SecureField(venue == .coinbase ? String(localized: "crypto.accounts.coinbase-private-key")
                                                   : String(localized: "crypto.accounts.secret"),
                                text: binding(\.secret))
                        .textFieldStyle(.roundedBorder)
                    if venue.needsPassphrase {
                        SecureField(String(localized: "crypto.accounts.passphrase"), text: binding(\.passphrase))
                            .textFieldStyle(.roundedBorder)
                    }
                }

                if let message {
                    Text(verbatim: message)
                        .font(.system(size: 10))
                        .foregroundColor(messageIsWarning ? .orange : .red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    Button(venue.isWallet ? String(localized: "crypto.accounts.add-wallet")
                                          : String(localized: "crypto.accounts.check-and-add")) { submit() }
                        .buttonStyle(.borderedProminent)
                        .disabled(checking)
                    Button(String(localized: "Cancel")) { cancel() }
                        .disabled(checking)
                    if checking {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
            .onChange(of: binanceEd25519) { _, ed in
                guard draft?.venue == .binance else { return }
                draft?.secret = ed ? CryptoAPI.pkcs8PEM(Curve25519.Signing.PrivateKey()) : ""
                copied = false
            }
        }
    }

    private func binding(_ path: WritableKeyPath<CryptoAccount, String>) -> Binding<String> {
        Binding(get: { draft?[keyPath: path] ?? "" },
                set: { draft?[keyPath: path] = $0 })
    }

    private func start(_ venue: CryptoVenue) {
        draft = CryptoAccount(venue: venue, region: venue.defaultRegion(country: Locale.current.region?.identifier))
        message = nil
        copied = false
        binanceEd25519 = true
        if venue == .binance { draft?.secret = CryptoAPI.pkcs8PEM(Curve25519.Signing.PrivateKey()) }
    }

    /// The public half of the key pair Coucou made for Binance, to paste on binance.com.
    private var publicKeyPEM: String {
        guard let secret = draft?.secret, let key = CryptoAPI.ed25519Key(secret) else { return "" }
        return CryptoAPI.publicKeyPEM(key)
    }

    private func cancel() {
        draft = nil
        message = nil
    }

    private func submit() {
        guard let account = draft, !checking else { return }
        checking = true
        message = nil
        Task {
            let outcome = await portfolio.connect(account)
            checking = false
            switch outcome {
            case .added:
                draft = nil
                message = nil
            case .tooPowerful(let rights):
                messageIsWarning = true
                message = String(format: String(localized: "crypto.accounts.too-powerful %@"),
                                 rights.joined(separator: ", "))
            case .failed(let reason):
                messageIsWarning = false
                message = reason
            }
        }
    }

    /// How to make a read-only key on each exchange (or which address to paste).
    static func help(_ venue: CryptoVenue) -> String {
        switch venue {
        case .coinbase: return String(localized: "crypto.help.coinbase")
        case .binance:  return String(localized: "crypto.help.binance")
        case .bybit:    return String(localized: "crypto.help.bybit")
        case .okx:      return String(localized: "crypto.help.okx")
        case .kraken:   return String(localized: "crypto.help.kraken")
        case .bitcoin:  return String(localized: "crypto.help.bitcoin")
        case .ethereum: return String(localized: "crypto.help.ethereum")
        case .solana:   return String(localized: "crypto.help.solana")
        }
    }
}
