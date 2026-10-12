import Foundation
import Combine

// MARK: - Portfolio

/// What the connected accounts hold, added up per coin and valued with the Crypto pill's
/// public prices. Balances are read every 5 minutes and prices every minute, only while
/// the Crypto pill is on and at least one account is connected: nothing goes over the
/// network otherwise. Every request is a read (see CryptoAPI); keys stay in the Keychain.
@MainActor
final class CryptoPortfolio: ObservableObject {
    static let shared = CryptoPortfolio()

    /// One coin across every account.
    struct Line: Identifiable, Equatable {
        let asset: String
        let amount: Double
        /// Price now and 24 h ago in the chosen currency (nil: no market found for it).
        var price: Double?
        var open24h: Double?
        var id: String { asset }
        var value: Double? { price.map { $0 * amount } }
        var change: Double? {
            guard let p = price, let o = open24h, o > 0 else { return nil }
            return (p - o) / o * 100
        }
    }

    /// How an account is doing.
    struct AccountState: Equatable {
        var holdings: [CryptoHolding] = []
        /// Why its balances couldn't be read last time.
        var error: String?
        /// The key can do more than read: Coucou stopped using it.
        var blockedRights: [String]?
        var updated: Date?
    }

    enum ConnectOutcome: Equatable {
        case added
        case tooPowerful([String])
        case failed(String)
    }

    @Published private(set) var accounts: [CryptoAccount] = []
    @Published private(set) var states: [UUID: AccountState] = [:]
    @Published private(set) var lines: [Line] = []
    @Published private(set) var loaded = false
    @Published private(set) var lastUpdate: Date?

    var hasAccounts: Bool { !accounts.isEmpty }

    /// Sum of the coins that have a price.
    var total: Double { lines.compactMap(\.value).reduce(0, +) }
    /// Change over 24 h of the priced coins, in percent.
    var totalChange: Double? {
        let now = lines.compactMap { l -> Double? in l.open24h != nil ? l.value : nil }.reduce(0, +)
        let before = lines.compactMap { l -> Double? in l.open24h.map { $0 * l.amount } }.reduce(0, +)
        return before > 0 ? (now - before) / before * 100 : nil
    }

    private var timer: Timer?
    private var fetchingBalances = false
    private var fetchingPrices = false
    private var lastBalances: Date = .distantPast
    /// Keys whose rights were checked since launch (a key's rights can change on the exchange).
    private var checkedSinceLaunch = Set<UUID>()
    private var cancellables = Set<AnyCancellable>()

    private var isPillActive: Bool {
        AppState.shared.activeIntegrations.contains(CryptoController.pillId)
    }

    private init() {
        accounts = CryptoAccountStore.decode(KeychainStore.shared.get(CryptoAccountStore.keychainKey))
        AppState.shared.$activeIntegrations
            .map { $0.contains(CryptoController.pillId) }
            .removeDuplicates()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.updatePolling() }
            }
            .store(in: &cancellables)
    }

    func start() { updatePolling() }

    private func updatePolling() {
        if isPillActive && hasAccounts {
            if timer == nil {
                let t = Timer(timeInterval: 60, repeats: true) { _ in
                    MainActor.assumeIsolated { CryptoPortfolio.shared.tick() }
                }
                t.tolerance = 10
                RunLoop.main.add(t, forMode: .common)
                timer = t
            }
            tick()
        } else {
            timer?.invalidate()
            timer = nil
            if !isPillActive {
                lines = []
                states = [:]
                loaded = false
                lastUpdate = nil
                lastBalances = .distantPast
            }
        }
    }

    /// Every minute: prices; every 5 minutes: balances.
    private func tick() {
        if Date().timeIntervalSince(lastBalances) >= 300 { refreshBalances() } else { refreshPrices() }
    }

    func refreshIfStale() {
        guard isPillActive, hasAccounts else { return }
        if Date().timeIntervalSince(lastBalances) > 120 { refreshBalances() }
    }

    /// Currency or exchange changed in Settings: value everything again.
    func settingsChanged() {
        guard isPillActive, hasAccounts else { return }
        refreshPrices()
    }

    // MARK: - Accounts

    /// Checks the key (read-only, and it can read balances) or the address, then saves the
    /// account. Nothing is saved when the key can trade, transfer or withdraw.
    func connect(_ draft: CryptoAccount) async -> ConnectOutcome {
        var account = draft
        account.apiKey = account.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        account.secret = account.secret.trimmingCharacters(in: .whitespacesAndNewlines)
        account.passphrase = account.passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        account.address = account.address.trimmingCharacters(in: .whitespacesAndNewlines)
        account.label = account.label.trimmingCharacters(in: .whitespacesAndNewlines)

        if account.venue.isWallet {
            guard CryptoAPI.isValidAddress(account.address, venue: account.venue) else {
                return .failed(Self.describe(CryptoAccountError.badAddress))
            }
        } else if account.apiKey.isEmpty || account.secret.isEmpty
                    || (account.venue.needsPassphrase && account.passphrase.isEmpty) {
            return .failed(String(localized: "crypto.account.missing-fields"))
        }

        if account.venue.canCheckPermissions {
            switch await Self.checkKey(account) {
            case .success(.readOnly): break
            case .success(.tooPowerful(let rights)): return .tooPowerful(rights)
            case .failure(let error): return .failed(Self.describe(error))
            }
        }
        let holdings: [CryptoHolding]
        do { holdings = try await Self.balances(of: account) } catch { return .failed(Self.describe(error)) }

        accounts.append(account)
        save()
        checkedSinceLaunch.insert(account.id)
        states[account.id] = AccountState(holdings: holdings, updated: Date())
        updatePolling()
        rebuildLines()
        refreshPrices()
        return .added
    }

    func remove(_ id: UUID) {
        accounts.removeAll { $0.id == id }
        states[id] = nil
        checkedSinceLaunch.remove(id)
        save()
        rebuildLines()
        if !hasAccounts { updatePolling() }
    }

    func rename(_ id: UUID, to label: String) {
        guard let i = accounts.firstIndex(where: { $0.id == id }) else { return }
        accounts[i].label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        save()
    }

    private func save() {
        if accounts.isEmpty {
            KeychainStore.shared.remove(CryptoAccountStore.keychainKey)
        } else if let json = CryptoAccountStore.encode(accounts) {
            KeychainStore.shared.set(CryptoAccountStore.keychainKey, value: json)
        }
    }

    // MARK: - Balances

    func refreshBalances() {
        guard isPillActive, hasAccounts, !fetchingBalances else { return }
        fetchingBalances = true
        let accounts = accounts
        let recheck = Set(accounts.map(\.id)).subtracting(checkedSinceLaunch)
        Task {
            var results: [UUID: AccountState] = [:]
            await withTaskGroup(of: (UUID, AccountState, Bool).self) { group in
                for account in accounts {
                    let mustCheck = recheck.contains(account.id) && account.venue.canCheckPermissions
                    group.addTask {
                        var state = AccountState()
                        if mustCheck {
                            switch await Self.checkKey(account) {
                            case .success(.readOnly): break
                            case .success(.tooPowerful(let rights)):
                                state.blockedRights = rights
                                return (account.id, state, true)
                            case .failure(let error):
                                state.error = Self.describe(error)
                                return (account.id, state, false)
                            }
                        }
                        do {
                            state.holdings = try await Self.balances(of: account)
                            state.updated = Date()
                        } catch {
                            state.error = Self.describe(error)
                        }
                        return (account.id, state, mustCheck)
                    }
                }
                for await (id, state, checked) in group {
                    results[id] = state
                    if checked { checkedSinceLaunch.insert(id) }
                }
            }
            fetchingBalances = false
            lastBalances = Date()
            // An account removed while its balances were read stays removed.
            for (id, state) in results where self.accounts.contains(where: { $0.id == id }) {
                // A failed read keeps the last known holdings, with the error shown in Settings.
                if state.error != nil, let previous = states[id] {
                    states[id] = AccountState(holdings: previous.holdings, error: state.error,
                                              blockedRights: nil, updated: previous.updated)
                } else {
                    states[id] = state
                }
            }
            rebuildLines()
            refreshPrices(force: true)
        }
    }

    /// Coins held across accounts (blocked keys left out), biggest amount first until priced.
    private func rebuildLines() {
        var amounts: [String: Double] = [:]
        for account in accounts {
            guard let state = states[account.id], state.blockedRights == nil else { continue }
            for h in state.holdings { amounts[h.asset, default: 0] += h.amount }
        }
        let previous = Dictionary(uniqueKeysWithValues: lines.map { ($0.asset, $0) })
        lines = amounts.map { asset, amount in
            Line(asset: asset, amount: amount, price: previous[asset]?.price, open24h: previous[asset]?.open24h)
        }
        sortLines()
        loaded = !states.isEmpty
    }

    private func sortLines() {
        lines.sort { a, b in
            switch (a.value, b.value) {
            case let (x?, y?): return x > y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.asset < b.asset
            }
        }
    }

    // MARK: - Prices

    func refreshPrices(force: Bool = false) {
        guard isPillActive, !lines.isEmpty, !fetchingPrices || force else { return }
        fetchingPrices = true
        let assets = lines.map(\.asset)
        let currency = CryptoSettings.currency
        let exchange = CryptoSettings.exchange
        // Prices the Crypto pill already has for its own coins.
        let known = Dictionary(uniqueKeysWithValues: CryptoController.shared.quotes.map { ($0.symbol, $0) })
        Task {
            let prices = await Self.prices(for: assets, currency: currency, exchange: exchange, known: known)
            fetchingPrices = false
            lines = lines.map { line in
                var l = line
                if let p = prices[line.asset] { l.price = p.price; l.open24h = p.open }
                return l
            }
            sortLines()
            lastUpdate = Date()
        }
    }

    private static let usdLike: Set<String> = ["USD", "USDT", "USDC", "FDUSD", "DAI", "TUSD", "PYUSD", "USDE", "BUSD", "USDP"]
    private static let eurLike: Set<String> = ["EUR", "EURC", "EURI", "EURT"]

    /// Price now and 24 h ago for each coin: the chosen exchange first, then the other one.
    /// Dollar and euro stablecoins and cash are valued with the USDC rate.
    nonisolated private static func prices(for assets: [String], currency: String, exchange: CryptoExchange,
                                           known: [String: CryptoQuote]) async -> [String: (price: Double, open: Double)] {
        var out: [String: (price: Double, open: Double)] = [:]
        // USDC in the chosen currency: 1 in dollars, the euro rate otherwise.
        var usd: (price: Double, open: Double)?
        if currency == "USD" {
            usd = (1, 1)
        } else if let q = await quote("USDC", currency: currency, exchange: exchange) {
            usd = (q.price, q.open24h)
        }
        let others = assets.filter { asset in
            if asset == currency { out[asset] = (1, 1); return false }
            if usdLike.contains(asset) { if let usd { out[asset] = usd }; return false }
            if eurLike.contains(asset) {
                if currency == "EUR" { out[asset] = (1, 1) }
                else if let usd, usd.price > 0, usd.open > 0 { out[asset] = (1 / usd.price, 1 / usd.open) }
                return false
            }
            if let q = known[asset] { out[asset] = (q.price, q.open24h); return false }
            return true
        }
        await withTaskGroup(of: (String, CryptoQuote?).self) { group in
            for asset in others {
                group.addTask { (asset, await quote(asset, currency: currency, exchange: exchange)) }
            }
            for await (asset, q) in group {
                if let q { out[asset] = (q.price, q.open24h) }
            }
        }
        return out
    }

    nonisolated private static func quote(_ asset: String, currency: String, exchange: CryptoExchange) async -> CryptoQuote? {
        if let q = await CryptoController.fetch(asset, exchange: exchange, currency: currency, candles: false) { return q }
        let other: CryptoExchange = exchange == .coinbase ? .okx : .coinbase
        return await CryptoController.fetch(asset, exchange: other, currency: currency, candles: false)
    }

    // MARK: - Network

    /// The key's rights, from the exchange.
    nonisolated static func checkKey(_ account: CryptoAccount) async -> Result<CryptoKeyAccess, Error> {
        guard let endpoint = CryptoAPI.permissionEndpoint(account.venue) else { return .success(.readOnly) }
        do {
            let data = try await call(endpoint, account: account)
            return .success(try CryptoAPI.parsePermissions(account.venue, data))
        } catch {
            return .failure(error)
        }
    }

    /// Every balance call of the account, added up. At least one has to answer.
    nonisolated static func balances(of account: CryptoAccount) async throws -> [CryptoHolding] {
        var merged: [String: Double] = [:]
        var firstError: Error?
        var answered = false
        for endpoint in CryptoAPI.balanceEndpoints(account.venue, address: account.address) {
            var cursor: String?
            var pages = 0
            repeat {
                do {
                    let data = try await call(endpoint, account: account, cursor: cursor)
                    let page = try CryptoAPI.parseBalances(endpoint, venue: account.venue, data)
                    for h in page.holdings { merged[h.asset, default: 0] += h.amount }
                    answered = true
                    cursor = page.next
                } catch {
                    if firstError == nil { firstError = error }
                    cursor = nil
                }
                pages += 1
            } while cursor != nil && pages < 20
        }
        guard answered else { throw firstError ?? CryptoAccountError.unreadable }
        return merged.map { CryptoHolding(asset: $0.key, amount: $0.value) }.sorted { $0.asset < $1.asset }
    }

    nonisolated private static func call(_ endpoint: CryptoEndpoint, account: CryptoAccount,
                                         cursor: String? = nil) async throws -> Data {
        let now = await CryptoClock.shared.now(for: account)
        let request = try CryptoAPI.request(endpoint, account: account, now: now, cursor: cursor)
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            if let message = CryptoAPI.errorMessage(account.venue, data) { throw CryptoAccountError.rejected(message) }
            throw CryptoAccountError.http(status)
        }
        return data
    }

    /// A short reason for Settings.
    nonisolated static func describe(_ error: Error) -> String {
        switch error {
        case CryptoAccountError.badSecret:       return String(localized: "crypto.account.bad-secret")
        case CryptoAccountError.badAddress:      return String(localized: "crypto.account.bad-address")
        case CryptoAccountError.legacyCoinbaseKey: return String(localized: "crypto.account.coinbase-legacy")
        case CryptoAccountError.unreadable:      return String(localized: "crypto.account.unreadable")
        case CryptoAccountError.http(let code):  return "HTTP \(code)"
        case CryptoAccountError.rejected(let m): return String(m.prefix(160))
        default:                                 return error.localizedDescription
        }
    }

    // MARK: - Formatting

    /// "0,5", "1 234,12", "0,00012345": up to 8 significant decimals, no trailing zeros.
    static func formatAmount(_ value: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = value >= 1000 ? 2 : value >= 1 ? 4 : 8
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }
}

// MARK: - Exchange clocks

/// The offset between the Mac's clock and each exchange's, read from the exchange's public
/// time endpoint every 30 minutes: signed requests carry a timestamp the exchange checks
/// (Binance refuses one that is even a second ahead).
actor CryptoClock {
    static let shared = CryptoClock()

    private var offsets: [String: (offset: Double, at: Date)] = [:]

    func now(for account: CryptoAccount) async -> Date {
        guard let endpoint = CryptoAPI.serverTimeEndpoint(account.venue) else { return Date() }
        let host = account.venue.host(region: account.region)
        if let known = offsets[host], Date().timeIntervalSince(known.at) < 1800 {
            return Date().addingTimeInterval(known.offset)
        }
        var offset: Double = 0
        if let url = URL(string: "https://\(host)\(endpoint.path)") {
            var request = URLRequest(url: url, timeoutInterval: 8)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            let sent = Date()
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               let server = CryptoAPI.parseServerTime(account.venue, data) {
                let received = Date()
                let local = (sent.timeIntervalSince1970 + received.timeIntervalSince1970) / 2
                // A quarter of a second behind the exchange rather than ahead of it.
                offset = server - local - 0.25
            }
        }
        offsets[host] = (offset, Date())
        return Date().addingTimeInterval(offset)
    }
}
