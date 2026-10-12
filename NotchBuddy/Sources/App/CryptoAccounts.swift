import Foundation
import CryptoKit

// Read-only crypto accounts: exchange API keys that can only READ balances, and
// self-custody wallets followed by their public address. Coucou never places an order,
// never transfers, never withdraws: it only calls the balance endpoints below, and it
// refuses an exchange key that could do more than read (where the exchange lets us check).
//
// Everything in this file is pure (Foundation + CryptoKit): request building, signing,
// the read-only rules and the parsers, so tests/CryptoAccountsTests.swift can run it
// against the exchanges' own documented examples.

// MARK: - Venues

enum CryptoVenue: String, Codable, CaseIterable, Sendable {
    case coinbase, binance, bybit, okx, kraken
    case bitcoin, ethereum, solana

    static let exchanges: [CryptoVenue] = [.coinbase, .binance, .bybit, .okx, .kraken]
    static let wallets: [CryptoVenue] = [.bitcoin, .ethereum, .solana]

    var name: String {
        switch self {
        case .coinbase: return "Coinbase"
        case .binance:  return "Binance"
        case .bybit:    return "Bybit"
        case .okx:      return "OKX"
        case .kraken:   return "Kraken"
        case .bitcoin:  return "Bitcoin"
        case .ethereum: return "Ethereum"
        case .solana:   return "Solana"
        }
    }

    var isWallet: Bool { Self.wallets.contains(self) }

    /// The coin a wallet holds.
    var walletAsset: String? {
        switch self {
        case .bitcoin:  return "BTC"
        case .ethereum: return "ETH"
        case .solana:   return "SOL"
        default:        return nil
        }
    }

    var needsPassphrase: Bool { self == .okx }

    /// Sites the exchange runs per region. The first one is the default.
    var regions: [CryptoRegion] {
        switch self {
        case .okx:
            return [CryptoRegion(id: "global", label: "okx.com", host: "www.okx.com"),
                    CryptoRegion(id: "eea", label: "my.okx.com (EEA)", host: "eea.okx.com"),
                    CryptoRegion(id: "us", label: "app.okx.com (US, AU)", host: "us.okx.com")]
        case .bybit:
            return [CryptoRegion(id: "global", label: "bybit.com", host: "api.bybit.com"),
                    CryptoRegion(id: "eu", label: "bybit.eu (EEA)", host: "api.bybit.eu"),
                    CryptoRegion(id: "nl", label: "bybit.nl", host: "api.bybit.nl"),
                    CryptoRegion(id: "tr", label: "bybit-tr.com", host: "api.bybit-tr.com"),
                    CryptoRegion(id: "kz", label: "bybit.kz", host: "api.bybit.kz"),
                    CryptoRegion(id: "ge", label: "bybitgeorgia.ge", host: "api.bybitgeorgia.ge"),
                    CryptoRegion(id: "ae", label: "bybit.ae", host: "api.bybit.ae")]
        case .coinbase: return [CryptoRegion(id: "global", label: "coinbase.com", host: "api.coinbase.com")]
        case .binance:  return [CryptoRegion(id: "global", label: "binance.com", host: "api.binance.com")]
        case .kraken:   return [CryptoRegion(id: "global", label: "kraken.com", host: "api.kraken.com")]
        case .bitcoin:  return [CryptoRegion(id: "global", label: "mempool.space", host: "mempool.space")]
        case .ethereum: return [CryptoRegion(id: "global", label: "publicnode.com", host: "ethereum-rpc.publicnode.com")]
        case .solana:   return [CryptoRegion(id: "global", label: "solana.com", host: "api.mainnet-beta.solana.com")]
        }
    }

    /// The site an account most likely lives on, from the Mac's country (EEA → OKX EEA, Bybit EU).
    func defaultRegion(country: String?) -> String {
        let eea: Set<String> = ["AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT",
                                "LV", "LT", "LU", "MT", "NL", "PL", "PT", "RO", "SK", "SI", "ES", "SE", "IS", "LI", "NO"]
        switch self {
        case .okx:
            if let c = country, eea.contains(c) { return "eea" }
            if country == "US" || country == "AU" { return "us" }
            return "global"
        default:
            return regions.first?.id ?? "global"
        }
    }

    func host(region: String) -> String {
        (regions.first { $0.id == region } ?? regions[0]).host
    }

    /// Where the user creates a read-only key (or checks an address).
    var keyPageURL: URL? {
        switch self {
        case .coinbase: return URL(string: "https://portal.cdp.coinbase.com/projects/api-keys")
        case .binance:  return URL(string: "https://www.binance.com/en/my/settings/api-management")
        case .bybit:    return URL(string: "https://www.bybit.com/app/user/api-management")
        case .okx:      return URL(string: "https://www.okx.com/account/my-api")
        case .kraken:   return URL(string: "https://pro.kraken.com/app/settings/api")
        case .bitcoin:  return URL(string: "https://mempool.space")
        case .ethereum: return URL(string: "https://etherscan.io")
        case .solana:   return URL(string: "https://solscan.io")
        }
    }

    /// Can Coucou ask the exchange what the key is allowed to do?
    var canCheckPermissions: Bool { self != .kraken && !isWallet }
}

struct CryptoRegion: Hashable, Sendable {
    let id: String
    let label: String
    let host: String
}

// MARK: - Accounts

/// One connected account. Saved, secrets included, as one item in the macOS Keychain.
struct CryptoAccount: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var venue: CryptoVenue
    /// Name the user gave it ("Binance perso", "Ledger").
    var label: String = ""
    var region: String = "global"
    /// Exchanges: the API key (Coinbase: the key name "organizations/…/apiKeys/…").
    var apiKey: String = ""
    /// Exchanges: the secret (Coinbase: the private key, PEM or base64).
    var secret: String = ""
    /// OKX only.
    var passphrase: String = ""
    /// Wallets: the public address.
    var address: String = ""

    var displayName: String { label.isEmpty ? venue.name : label }
}

enum CryptoAccountStore {
    static let keychainKey = "crypto-accounts"

    static func decode(_ json: String?) -> [CryptoAccount] {
        guard let data = json?.data(using: .utf8),
              let accounts = try? JSONDecoder().decode([CryptoAccount].self, from: data) else { return [] }
        return accounts
    }

    static func encode(_ accounts: [CryptoAccount]) -> String? {
        guard let data = try? JSONEncoder().encode(accounts) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Results

struct CryptoHolding: Equatable, Sendable {
    let asset: String
    let amount: Double
}

/// What a key is allowed to do.
enum CryptoKeyAccess: Equatable, Sendable {
    case readOnly
    /// It could do more than read: the rights it has, as the exchange names them.
    case tooPowerful([String])
}

enum CryptoAccountError: Error, Equatable, Sendable {
    /// The secret can't be read (bad base64, bad PEM…).
    case badSecret
    /// The exchange refused the key or the request; its own message.
    case rejected(String)
    case http(Int)
    case unreadable
    case badAddress
    /// A Coinbase key from before February 2025 (16-character key, 32-character secret).
    case legacyCoinbaseKey
}

// MARK: - Endpoints

/// One read call. Every call Coucou makes is in this list: nothing else is ever sent.
struct CryptoEndpoint: Equatable, Sendable {
    enum Purpose: Equatable, Sendable { case permissions, balances }

    let id: String
    let purpose: Purpose
    let method: String
    let path: String
    var query: [(String, String)] = []
    /// JSON-RPC body for the wallets.
    var body: Data? = nil

    static func == (a: CryptoEndpoint, b: CryptoEndpoint) -> Bool {
        a.id == b.id && a.method == b.method && a.path == b.path && a.body == b.body
            && a.query.map { $0.0 + "=" + $0.1 } == b.query.map { $0.0 + "=" + $0.1 }
    }
}

enum CryptoAPI {
    /// Binance and Bybit: how long a signed request stays valid, in ms.
    static let recvWindow = "10000"

    static func permissionEndpoint(_ venue: CryptoVenue) -> CryptoEndpoint? {
        switch venue {
        case .coinbase: return CryptoEndpoint(id: "coinbase.permissions", purpose: .permissions, method: "GET",
                                              path: "/api/v3/brokerage/key_permissions")
        case .binance:  return CryptoEndpoint(id: "binance.permissions", purpose: .permissions, method: "GET",
                                              path: "/sapi/v1/account/apiRestrictions")
        case .bybit:    return CryptoEndpoint(id: "bybit.permissions", purpose: .permissions, method: "GET",
                                              path: "/v5/user/query-api")
        case .okx:      return CryptoEndpoint(id: "okx.permissions", purpose: .permissions, method: "GET",
                                              path: "/api/v5/account/config")
        case .kraken, .bitcoin, .ethereum, .solana: return nil
        }
    }

    /// The balance calls of a venue. Each one covers a wallet of the account (spot, funding…).
    static func balanceEndpoints(_ venue: CryptoVenue, address: String = "") -> [CryptoEndpoint] {
        switch venue {
        case .coinbase:
            return [CryptoEndpoint(id: "coinbase.accounts", purpose: .balances, method: "GET",
                                   path: "/api/v3/brokerage/accounts", query: [("limit", "250")])]
        case .binance:
            return [CryptoEndpoint(id: "binance.spot", purpose: .balances, method: "POST",
                                   path: "/sapi/v3/asset/getUserAsset"),
                    CryptoEndpoint(id: "binance.funding", purpose: .balances, method: "POST",
                                   path: "/sapi/v1/asset/get-funding-asset"),
                    CryptoEndpoint(id: "binance.earn.flexible", purpose: .balances, method: "GET",
                                   path: "/sapi/v1/simple-earn/flexible/position", query: [("size", "100")]),
                    CryptoEndpoint(id: "binance.earn.locked", purpose: .balances, method: "GET",
                                   path: "/sapi/v1/simple-earn/locked/position", query: [("size", "100")])]
        case .bybit:
            return [CryptoEndpoint(id: "bybit.unified", purpose: .balances, method: "GET",
                                   path: "/v5/account/wallet-balance", query: [("accountType", "UNIFIED")]),
                    CryptoEndpoint(id: "bybit.fund", purpose: .balances, method: "GET",
                                   path: "/v5/asset/transfer/query-account-coins-balance",
                                   query: [("accountType", "FUND")])]
        case .okx:
            return [CryptoEndpoint(id: "okx.trading", purpose: .balances, method: "GET",
                                   path: "/api/v5/account/balance"),
                    CryptoEndpoint(id: "okx.funding", purpose: .balances, method: "GET",
                                   path: "/api/v5/asset/balances"),
                    CryptoEndpoint(id: "okx.savings", purpose: .balances, method: "GET",
                                   path: "/api/v5/finance/savings/balance"),
                    CryptoEndpoint(id: "okx.onchain-earn", purpose: .balances, method: "GET",
                                   path: "/api/v5/finance/staking-defi/orders-active")]
        case .kraken:
            return [CryptoEndpoint(id: "kraken.balance", purpose: .balances, method: "POST",
                                   path: "/0/private/BalanceEx")]
        case .bitcoin:
            return [CryptoEndpoint(id: "bitcoin.address", purpose: .balances, method: "GET",
                                   path: "/api/address/\(address)")]
        case .ethereum:
            return [CryptoEndpoint(id: "ethereum.balance", purpose: .balances, method: "POST", path: "/",
                                   body: jsonRPC("eth_getBalance", [address, "latest"]))]
        case .solana:
            return [CryptoEndpoint(id: "solana.balance", purpose: .balances, method: "POST", path: "/",
                                   body: jsonRPC("getBalance", [address]))]
        }
    }

    private static func jsonRPC(_ method: String, _ params: [String]) -> Data? {
        try? JSONSerialization.data(withJSONObject: ["jsonrpc": "2.0", "id": 1, "method": method, "params": params],
                                    options: [.sortedKeys])
    }

    // MARK: Server time

    /// Public clock of the exchange, so a Mac whose clock drifts still signs valid requests.
    static func serverTimeEndpoint(_ venue: CryptoVenue) -> CryptoEndpoint? {
        switch venue {
        case .binance:  return CryptoEndpoint(id: "binance.time", purpose: .permissions, method: "GET", path: "/api/v3/time")
        case .bybit:    return CryptoEndpoint(id: "bybit.time", purpose: .permissions, method: "GET", path: "/v5/market/time")
        case .okx:      return CryptoEndpoint(id: "okx.time", purpose: .permissions, method: "GET", path: "/api/v5/public/time")
        case .coinbase: return CryptoEndpoint(id: "coinbase.time", purpose: .permissions, method: "GET", path: "/api/v3/brokerage/time")
        default:        return nil
        }
    }

    /// Seconds since 1970 from the exchange's time answer.
    static func parseServerTime(_ venue: CryptoVenue, _ data: Data) -> Double? {
        guard let d = (try? object(data)) as? [String: Any] else { return nil }
        switch venue {
        case .binance:  return number(d["serverTime"]).map { $0 / 1000 }
        case .bybit:    return (d["result"] as? [String: Any]).flatMap { number($0["timeNano"]).map { $0 / 1e9 } ?? number($0["timeSecond"]) }
        case .okx:      return ((d["data"] as? [[String: Any]])?.first).flatMap { number($0["ts"]) }.map { $0 / 1000 }
        case .coinbase: return number(d["epochMillis"]).map { $0 / 1000 } ?? number(d["epochSeconds"])
        default:        return nil
        }
    }

    // MARK: Building and signing

    /// The signed request for an endpoint. `now` and `nonce` come from outside so tests
    /// can replay the exchanges' documented examples.
    static func request(_ endpoint: CryptoEndpoint, account: CryptoAccount, now: Date = Date(),
                        nonce: String? = nil, cursor: String? = nil) throws -> URLRequest {
        let venue = account.venue
        var query = endpoint.query
        if let cursor, !cursor.isEmpty { query.append(("cursor", cursor)) }
        let host = venue.host(region: account.region)
        let ms = String(Int64((now.timeIntervalSince1970 * 1000).rounded(.down)))

        func url(_ queryString: String) -> URL? {
            URL(string: "https://\(host)\(endpoint.path)\(queryString.isEmpty ? "" : "?" + queryString)")
        }
        func base(_ queryString: String) throws -> URLRequest {
            guard let u = url(queryString) else { throw CryptoAccountError.unreadable }
            var r = URLRequest(url: u, timeoutInterval: 15)
            r.httpMethod = endpoint.method
            r.setValue("application/json", forHTTPHeaderField: "Accept")
            return r
        }

        switch venue {
        case .binance:
            // The whole query string, signed and sent as the last parameter: Ed25519 (base64,
            // percent-encoded) for self-generated keys, HMAC SHA256 (hex) for system-generated ones.
            let params = query + [("recvWindow", recvWindow), ("timestamp", ms)]
            let qs = formEncode(params)
            let signature: String
            if let key = ed25519Key(account.secret) {
                guard let sig = try? key.signature(for: Data(qs.utf8)) else { throw CryptoAccountError.badSecret }
                signature = percentEncode(sig.base64EncodedString())
            } else if account.secret.contains("-----BEGIN") {
                throw CryptoAccountError.badSecret   // an RSA key: not supported
            } else {
                signature = hmacHex(SHA256.self, key: Data(account.secret.utf8), message: qs)
            }
            var r = try base(qs + "&signature=" + signature)
            r.setValue(account.apiKey, forHTTPHeaderField: "X-MBX-APIKEY")
            return r

        case .bybit:
            // HMAC SHA256 (hex) of timestamp + key + recvWindow + query string.
            let qs = formEncode(query)
            let signature = hmacHex(SHA256.self, key: Data(account.secret.utf8),
                                    message: ms + account.apiKey + recvWindow + qs)
            var r = try base(qs)
            r.setValue(account.apiKey, forHTTPHeaderField: "X-BAPI-API-KEY")
            r.setValue(ms, forHTTPHeaderField: "X-BAPI-TIMESTAMP")
            r.setValue(recvWindow, forHTTPHeaderField: "X-BAPI-RECV-WINDOW")
            r.setValue(signature, forHTTPHeaderField: "X-BAPI-SIGN")
            return r

        case .okx:
            // base64 HMAC SHA256 of ISO timestamp + method + path with query + body.
            let qs = formEncode(query)
            let timestamp = isoMillis(now)
            let requestPath = endpoint.path + (qs.isEmpty ? "" : "?" + qs)
            let signature = hmacBase64(SHA256.self, key: Data(account.secret.utf8),
                                       message: timestamp + endpoint.method + requestPath)
            var r = try base(qs)
            r.setValue(account.apiKey, forHTTPHeaderField: "OK-ACCESS-KEY")
            r.setValue(signature, forHTTPHeaderField: "OK-ACCESS-SIGN")
            r.setValue(timestamp, forHTTPHeaderField: "OK-ACCESS-TIMESTAMP")
            r.setValue(account.passphrase, forHTTPHeaderField: "OK-ACCESS-PASSPHRASE")
            return r

        case .kraken:
            // API-Sign = base64(HMAC SHA512(base64-decoded secret, path + SHA256(nonce + body))).
            let n = nonce ?? ms
            let body = formEncode([("nonce", n)] + query)
            guard let secret = Data(base64Encoded: account.secret.trimmingCharacters(in: .whitespacesAndNewlines))
            else { throw CryptoAccountError.badSecret }
            let signature = krakenSignature(path: endpoint.path, nonce: n, body: body, secret: secret)
            var r = try base("")
            r.httpBody = Data(body.utf8)
            r.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
            r.setValue(account.apiKey, forHTTPHeaderField: "API-Key")
            r.setValue(signature, forHTTPHeaderField: "API-Sign")
            return r

        case .coinbase:
            // A JWT per request, signed with the CDP key (ES256 or Ed25519), for "GET host/path".
            let qs = formEncode(query)
            let jwt = try coinbaseJWT(keyName: account.apiKey, secret: account.secret,
                                      method: endpoint.method, host: host, path: endpoint.path,
                                      now: now, nonce: nonce ?? randomHex(16))
            var r = try base(qs)
            r.setValue("Bearer " + jwt, forHTTPHeaderField: "Authorization")
            return r

        case .bitcoin:
            return try base("")

        case .ethereum, .solana:
            var r = try base("")
            r.httpBody = endpoint.body
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return r
        }
    }

    // MARK: Crypto helpers

    static func hmacHex<H: HashFunction>(_ hash: H.Type, key: Data, message: String) -> String {
        let mac = HMAC<H>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
        return Data(mac).map { String(format: "%02x", $0) }.joined()
    }

    static func hmacBase64<H: HashFunction>(_ hash: H.Type, key: Data, message: String) -> String {
        let mac = HMAC<H>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: key))
        return Data(mac).base64EncodedString()
    }

    static func krakenSignature(path: String, nonce: String, body: String, secret: Data) -> String {
        let inner = Data(SHA256.hash(data: Data((nonce + body).utf8)))
        let message = Data(path.utf8) + inner
        let mac = HMAC<SHA512>.authenticationCode(for: message, using: SymmetricKey(data: secret))
        return Data(mac).base64EncodedString()
    }

    /// Coinbase CDP JWT. The key is either an EC P-256 private key (PEM, the "EC PRIVATE KEY"
    /// or "PRIVATE KEY" kind) signed with ES256, or a base64 Ed25519 key signed with EdDSA.
    static func coinbaseJWT(keyName: String, secret: String, method: String, host: String, path: String,
                            now: Date, nonce: String) throws -> String {
        let key = try coinbaseKey(keyName: keyName, secret: secret)
        let seconds = Int(now.timeIntervalSince1970)
        // The uri never carries the query string.
        let claims: [String: Any] = ["sub": keyName, "iss": "cdp", "nbf": seconds, "exp": seconds + 120,
                                     "uri": "\(method) \(host)\(path)"]
        let alg: String
        switch key {
        case .p256: alg = "ES256"
        case .ed25519: alg = "EdDSA"
        }
        let header: [String: Any] = ["alg": alg, "kid": keyName, "nonce": nonce, "typ": "JWT"]
        guard let h = try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys, .withoutEscapingSlashes]),
              let c = try? JSONSerialization.data(withJSONObject: claims, options: [.sortedKeys, .withoutEscapingSlashes])
        else { throw CryptoAccountError.unreadable }
        let signingInput = base64URL(h) + "." + base64URL(c)
        let signature: Data
        switch key {
        case .p256(let k):
            // ES256 wants the raw 64-byte R||S, not DER.
            guard let sig = try? k.signature(for: Data(signingInput.utf8)) else { throw CryptoAccountError.badSecret }
            signature = sig.rawRepresentation
        case .ed25519(let k):
            guard let sig = try? k.signature(for: Data(signingInput.utf8)) else { throw CryptoAccountError.badSecret }
            signature = sig
        }
        return signingInput + "." + base64URL(signature)
    }

    enum CoinbaseKey {
        case p256(P256.Signing.PrivateKey)
        case ed25519(Curve25519.Signing.PrivateKey)
    }

    /// The private key of a CDP key, in any of the forms Coinbase hands out: an EC PEM
    /// ("EC PRIVATE KEY" SEC1 or "PRIVATE KEY" PKCS#8), an Ed25519 PKCS#8 PEM, or base64
    /// Ed25519 (64 bytes seed + public key, or the 32-byte seed).
    static func coinbaseKey(keyName: String, secret: String) throws -> CoinbaseKey {
        let text = normalizedPEM(secret)
        if text.contains("-----BEGIN") {
            if let k = ed25519Key(text) { return .ed25519(k) }
            let body = text.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
            guard let der = Data(base64Encoded: body) else { throw CryptoAccountError.badSecret }
            let bytes = [UInt8](der)
            if let k = try? P256.Signing.PrivateKey(pemRepresentation: text) { return .p256(k) }
            if let k = try? P256.Signing.PrivateKey(derRepresentation: der) { return .p256(k) }
            // SEC1 ECPrivateKey (also inside PKCS#8): version 1, then OCTET STRING of 32 bytes.
            if let at = find([0x02, 0x01, 0x01, 0x04, 0x20], in: bytes), at + 5 + 32 <= bytes.count,
               let k = try? P256.Signing.PrivateKey(rawRepresentation: Data(bytes[(at + 5)..<(at + 37)])) {
                return .p256(k)
            }
            throw CryptoAccountError.badSecret
        }
        let compact = text.filter { !$0.isWhitespace }
        if let raw = Data(base64Encoded: compact), raw.count == 64 || raw.count == 32,
           let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw.prefix(32)) {
            // With the public half given, it must match the seed.
            if raw.count == 64, k.publicKey.rawRepresentation != raw.suffix(32) { throw CryptoAccountError.badSecret }
            return .ed25519(k)
        }
        // Keys made before February 2025: 16-character key and 32-character secret, no longer accepted.
        if keyName.count == 16, compact.count == 32, (keyName + compact).allSatisfy({ $0.isLetter || $0.isNumber }) {
            throw CryptoAccountError.legacyCoinbaseKey
        }
        throw CryptoAccountError.badSecret
    }

    /// An Ed25519 private key given as PKCS#8 PEM ("PRIVATE KEY", OID 1.3.101.112).
    static func ed25519Key(_ secret: String) -> Curve25519.Signing.PrivateKey? {
        let text = normalizedPEM(secret)
        guard text.contains("-----BEGIN PRIVATE KEY-----") else { return nil }
        let body = text.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        guard let der = Data(base64Encoded: body) else { return nil }
        let bytes = [UInt8](der)
        guard let oid = find([0x06, 0x03, 0x2B, 0x65, 0x70], in: bytes),
              let at = find([0x04, 0x22, 0x04, 0x20], in: bytes, from: oid), at + 36 <= bytes.count else { return nil }
        return try? Curve25519.Signing.PrivateKey(rawRepresentation: Data(bytes[(at + 4)..<(at + 36)]))
    }

    /// PKCS#8 PEM of an Ed25519 private key (what Coucou keeps for a key pair it generated).
    static func pkcs8PEM(_ key: Curve25519.Signing.PrivateKey) -> String {
        let der = Data([0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20])
            + key.rawRepresentation
        return "-----BEGIN PRIVATE KEY-----\n" + der.base64EncodedString() + "\n-----END PRIVATE KEY-----"
    }

    /// The public key to register on the exchange, as an SPKI PEM ("PUBLIC KEY").
    static func publicKeyPEM(_ key: Curve25519.Signing.PrivateKey) -> String {
        let der = Data([0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00])
            + key.publicKey.rawRepresentation
        return "-----BEGIN PUBLIC KEY-----\n" + der.base64EncodedString() + "\n-----END PUBLIC KEY-----"
    }

    private static func find(_ pattern: [UInt8], in bytes: [UInt8], from start: Int = 0) -> Int? {
        guard pattern.count <= bytes.count else { return nil }
        var i = start
        while i + pattern.count <= bytes.count {
            if Array(bytes[i..<(i + pattern.count)]) == pattern { return i }
            i += 1
        }
        return nil
    }

    /// A private key as pasted: from the downloaded JSON (with "\n" escapes), or from a
    /// one-line field that dropped the line breaks. PEM keys are rebuilt with 64-character lines.
    static func normalizedPEM(_ raw: String) -> String {
        let text = raw.replacingOccurrences(of: "\\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let begin = text.range(of: "-----BEGIN "),
              let beginEnd = text.range(of: "-----", range: begin.upperBound..<text.endIndex),
              let end = text.range(of: "-----END ", range: beginEnd.upperBound..<text.endIndex),
              text.range(of: "-----", range: end.upperBound..<text.endIndex) != nil else { return text }
        let label = text[begin.upperBound..<beginEnd.lowerBound]
        let body = text[beginEnd.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        var lines: [String] = []
        var rest = Substring(body)
        while !rest.isEmpty {
            lines.append(String(rest.prefix(64)))
            rest = rest.dropFirst(64)
        }
        return "-----BEGIN \(label)-----\n" + lines.joined(separator: "\n") + "\n-----END \(label)-----"
    }

    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func randomHex(_ bytes: Int) -> String {
        var g = SystemRandomNumberGenerator()
        return (0..<bytes).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &g)) }.joined()
    }

    /// "2020-12-08T09:08:57.715Z"
    static func isoMillis(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: date)
    }

    /// key=value&key=value, each part percent-encoded (RFC 3986 unreserved characters kept).
    static func formEncode(_ items: [(String, String)]) -> String {
        items.map { percentEncode($0.0) + "=" + percentEncode($0.1) }.joined(separator: "&")
    }

    static func percentEncode(_ s: String) -> String {
        // ASCII letters and digits only: CharacterSet.alphanumerics would keep non-ASCII letters.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: Read-only rules

    /// What the key can do, from the exchange's own answer.
    static func parsePermissions(_ venue: CryptoVenue, _ data: Data) throws -> CryptoKeyAccess {
        let json = try object(data)
        try checkError(venue, json)
        switch venue {
        case .coinbase:
            // {"can_view": true, "can_trade": false, "can_transfer": false, …}. Fail closed:
            // can_trade and can_transfer must be there and false, and any other can_* off.
            guard let d = json as? [String: Any] else { throw CryptoAccountError.unreadable }
            var rights: [String] = []
            for key in ["can_trade", "can_transfer"] where (d[key] as? Bool) != false {
                rights.append(key)
            }
            for key in d.keys.sorted() where key.hasPrefix("can_") && !["can_view", "can_trade", "can_transfer"].contains(key)
                && bool(d[key]) {
                rights.append(key)
            }
            guard (d["can_view"] as? Bool) == true else { throw CryptoAccountError.rejected("can_view: false") }
            return rights.isEmpty ? .readOnly : .tooPowerful(rights)

        case .binance:
            // {"enableReading": true, "enableWithdrawals": false, "enableSpotAndMarginTrading": false, …}
            // Every right other than reading must be off, including ones added after this was written.
            // Fail closed: the known rights must be there and false.
            guard let d = json as? [String: Any] else { throw CryptoAccountError.unreadable }
            guard (d["enableReading"] as? Bool) == true else { throw CryptoAccountError.rejected("enableReading: false") }
            let required = ["enableWithdrawals", "enableInternalTransfer", "permitsUniversalTransfer",
                            "enableSpotAndMarginTrading", "enableMargin", "enableFutures", "enableVanillaOptions",
                            "enablePortfolioMarginTrading", "enableFixApiTrade"]
            let reading: Set<String> = ["enableReading", "enableFixReadOnly"]
            var rights = Set(required.filter { (d[$0] as? Bool) != false })
            for key in d.keys where (key.hasPrefix("enable") || key.hasPrefix("permits")) && !reading.contains(key) && bool(d[key]) {
                rights.insert(key)
            }
            return rights.isEmpty ? .readOnly : .tooPowerful(rights.sorted())

        case .bybit:
            // {"result": {"readOnly": 1, "permissions": {"Wallet": [], "Spot": [], …}}}
            guard let result = (json as? [String: Any])?["result"] as? [String: Any] else {
                throw CryptoAccountError.unreadable
            }
            if int(result["readOnly"]) == 1 { return .readOnly }
            let perms = result["permissions"] as? [String: Any] ?? [:]
            let rights = perms.keys.sorted().flatMap { group in
                ((perms[group] as? [Any]) ?? []).compactMap { $0 as? String }.map { "\(group).\($0)" }
            }
            return .tooPowerful(rights.isEmpty ? ["readOnly=0"] : rights)

        case .okx:
            // {"code": "0", "data": [{"perm": "read_only,trade", …}]}
            guard let row = ((json as? [String: Any])?["data"] as? [[String: Any]])?.first,
                  let perm = row["perm"] as? String else { throw CryptoAccountError.unreadable }
            // Only exactly {read_only} passes: trade, withdraw and any newer right are refused.
            let tokens = perm.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
                .filter { !$0.isEmpty }
            guard tokens.contains("read_only") else { throw CryptoAccountError.rejected("perm: \(perm)") }
            let rights = tokens.filter { $0 != "read_only" }
            return rights.isEmpty ? .readOnly : .tooPowerful(rights)

        case .kraken, .bitcoin, .ethereum, .solana:
            return .readOnly
        }
    }

    // MARK: Balances

    /// Holdings from one balance call, and the cursor of the next page (Coinbase).
    static func parseBalances(_ endpoint: CryptoEndpoint, venue: CryptoVenue, _ data: Data) throws
        -> (holdings: [CryptoHolding], next: String?) {
        let json = try object(data)
        try checkError(venue, json)
        var out: [String: Double] = [:]
        func add(_ asset: String?, _ amount: Double) {
            guard let asset, amount > 0, let a = normalizeAsset(asset, venue: venue) else { return }
            out[a, default: 0] += amount
        }
        var next: String?

        switch endpoint.id {
        case "coinbase.accounts":
            guard let d = json as? [String: Any] else { throw CryptoAccountError.unreadable }
            for acc in d["accounts"] as? [[String: Any]] ?? [] {
                if acc["active"] as? Bool == false || !(acc["deleted_at"] is NSNull || acc["deleted_at"] == nil) { continue }
                let available = (acc["available_balance"] as? [String: Any]).flatMap { number($0["value"]) } ?? 0
                let hold = (acc["hold"] as? [String: Any]).flatMap { number($0["value"]) } ?? 0
                add(acc["currency"] as? String, available + hold)
            }
            if bool(d["has_next"]), let c = d["cursor"] as? String, !c.isEmpty { next = c }

        case "binance.spot", "binance.funding":
            for row in json as? [[String: Any]] ?? [] {
                let amount = ["free", "locked", "freeze", "withdrawing"].compactMap { number(row[$0]) }.reduce(0, +)
                add(row["asset"] as? String, amount)
            }

        case "binance.earn.flexible":
            for row in (json as? [String: Any])?["rows"] as? [[String: Any]] ?? [] {
                add(row["asset"] as? String, number(row["totalAmount"]) ?? 0)
            }

        case "binance.earn.locked":
            for row in (json as? [String: Any])?["rows"] as? [[String: Any]] ?? [] {
                add(row["asset"] as? String, number(row["amount"]) ?? 0)
            }

        case "bybit.unified":
            let list = ((json as? [String: Any])?["result"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
            for account in list {
                for coin in account["coin"] as? [[String: Any]] ?? [] {
                    add(coin["coin"] as? String, number(coin["walletBalance"]) ?? 0)
                }
            }

        case "bybit.fund":
            let rows = ((json as? [String: Any])?["result"] as? [String: Any])?["balance"] as? [[String: Any]] ?? []
            for coin in rows {
                add(coin["coin"] as? String, number(coin["walletBalance"]) ?? 0)
            }

        case "okx.trading":
            let rows = ((json as? [String: Any])?["data"] as? [[String: Any]])?.first?["details"] as? [[String: Any]] ?? []
            for row in rows {
                add(row["ccy"] as? String, number(row["eq"]) ?? number(row["cashBal"]) ?? 0)
            }

        case "okx.funding":
            for row in (json as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                add(row["ccy"] as? String, number(row["bal"]) ?? 0)
            }

        case "okx.savings":
            for row in (json as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                add(row["ccy"] as? String, number(row["amt"]) ?? 0)
            }

        case "okx.onchain-earn":
            // Staked positions: [{"investData": [{"ccy": "SOL", "amt": "10"}], …}]
            for order in (json as? [String: Any])?["data"] as? [[String: Any]] ?? [] {
                for invest in order["investData"] as? [[String: Any]] ?? [] {
                    add(invest["ccy"] as? String, number(invest["amt"]) ?? 0)
                }
            }

        case "kraken.balance":
            // {"error": [], "result": {"XXBT": {"balance": "0.5", "hold_trade": "0"}, …}}
            let result = (json as? [String: Any])?["result"] as? [String: Any] ?? [:]
            for (asset, value) in result {
                if let v = value as? [String: Any] { add(asset, number(v["balance"]) ?? 0) }
                else { add(asset, number(value) ?? 0) }
            }

        case "bitcoin.address":
            // Satoshis: confirmed (chain) and pending (mempool) funded minus spent.
            guard let d = json as? [String: Any] else { throw CryptoAccountError.unreadable }
            var sats: Double = 0
            for key in ["chain_stats", "mempool_stats"] {
                let s = d[key] as? [String: Any] ?? [:]
                sats += (number(s["funded_txo_sum"]) ?? 0) - (number(s["spent_txo_sum"]) ?? 0)
            }
            add("BTC", sats / 100_000_000)

        case "ethereum.balance":
            guard let hex = (json as? [String: Any])?["result"] as? String, let wei = hexToDouble(hex)
            else { throw CryptoAccountError.unreadable }
            add("ETH", wei / 1e18)

        case "solana.balance":
            guard let value = ((json as? [String: Any])?["result"] as? [String: Any]).flatMap({ number($0["value"]) })
            else { throw CryptoAccountError.unreadable }
            add("SOL", value / 1e9)

        default:
            throw CryptoAccountError.unreadable
        }
        return (out.map { CryptoHolding(asset: $0.key, amount: $0.value) }.sorted { $0.asset < $1.asset }, next)
    }

    /// One name per coin across exchanges: Kraken's XXBT and XBT.F are BTC, ZEUR is EUR.
    static func normalizeAsset(_ raw: String, venue: CryptoVenue) -> String? {
        var a = raw.uppercased().trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return nil }
        if venue == .kraken {
            // Earn and staking variants: XBT.F, ETH2.S, DOT.S, USDC.M, ETH.B…
            if let dot = a.firstIndex(of: ".") { a = String(a[..<dot]) }
            let legacy: [String: String] = [
                "XXBT": "BTC", "XBT": "BTC", "XXDG": "DOGE", "XDG": "DOGE", "XETH": "ETH", "ETH2": "ETH",
                "XETC": "ETC", "XLTC": "LTC", "XXLM": "XLM", "XXMR": "XMR", "XXRP": "XRP", "XZEC": "ZEC",
                "XREP": "REP", "XMLN": "MLN", "ZEUR": "EUR", "ZUSD": "USD", "ZGBP": "GBP", "ZCAD": "CAD",
                "ZJPY": "JPY", "ZAUD": "AUD", "ZCHF": "CHF",
            ]
            a = legacy[a] ?? a
        }
        guard a.count <= 12, a.allSatisfy({ $0.isLetter || $0.isNumber }) else { return nil }
        return a
    }

    // MARK: Errors

    /// The exchange's own error message, when its answer is an error.
    static func checkError(_ venue: CryptoVenue, _ json: Any) throws {
        guard let d = json as? [String: Any] else { return }
        switch venue {
        case .binance:
            if let code = int(d["code"]), code < 0 { throw CryptoAccountError.rejected(d["msg"] as? String ?? "\(code)") }
        case .bybit:
            if let code = int(d["retCode"]), code != 0 { throw CryptoAccountError.rejected(d["retMsg"] as? String ?? "\(code)") }
        case .okx:
            if let code = d["code"] as? String, code != "0" { throw CryptoAccountError.rejected(d["msg"] as? String ?? code) }
        case .kraken:
            if let errors = d["error"] as? [String], let first = errors.first { throw CryptoAccountError.rejected(first) }
        case .coinbase:
            if let error = d["error"] as? String {
                throw CryptoAccountError.rejected(d["message"] as? String ?? d["error_details"] as? String ?? error)
            }
        case .ethereum, .solana:
            if let error = d["error"] as? [String: Any] {
                throw CryptoAccountError.rejected(error["message"] as? String ?? "RPC error")
            }
        case .bitcoin:
            break
        }
    }

    /// The error text of a non-200 answer, when the exchange sent one.
    static func errorMessage(_ venue: CryptoVenue, _ data: Data) -> String? {
        guard let json = try? object(data) else {
            let text = String(data: data.prefix(200), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return text?.isEmpty == false ? text : nil
        }
        do { try checkError(venue, json) } catch CryptoAccountError.rejected(let message) { return message } catch {}
        if let d = json as? [String: Any] {
            return d["message"] as? String ?? d["msg"] as? String ?? d["error"] as? String
        }
        return nil
    }

    // MARK: Addresses

    /// A plausible public address for the chain (format only: the chain says if it exists).
    static func isValidAddress(_ address: String, venue: CryptoVenue) -> Bool {
        let a = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let base58 = Set("123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz")
        switch venue {
        case .bitcoin:
            let lower = a.lowercased()
            if lower.hasPrefix("bc1") {
                // bech32 / bech32m, one case only.
                let charset = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
                guard a == lower || a == a.uppercased() else { return false }
                return (14...90).contains(a.count) && lower.dropFirst(3).allSatisfy { charset.contains($0) }
            }
            guard let first = a.first, first == "1" || first == "3" else { return false }
            return (26...35).contains(a.count) && a.allSatisfy { base58.contains($0) }
        case .ethereum:
            return a.count == 42 && a.hasPrefix("0x") && a.dropFirst(2).allSatisfy { $0.isHexDigit }
        case .solana:
            return (32...44).contains(a.count) && a.allSatisfy { base58.contains($0) }
        default:
            return false
        }
    }

    // MARK: Small parsers

    static func object(_ data: Data) throws -> Any {
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw CryptoAccountError.unreadable }
        return json
    }

    static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let s = v as? String { return Double(s) }
        if let n = v as? NSNumber { return n.doubleValue }
        return nil
    }

    static func int(_ v: Any?) -> Int? {
        if let i = v as? Int { return i }
        if let s = v as? String { return Int(s) }
        if let n = v as? NSNumber { return n.intValue }
        return nil
    }

    static func bool(_ v: Any?) -> Bool {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "true" || s == "1" }
        return false
    }

    /// "0x1bc16d674ec80000" → 2e18. Wei don't fit in 64 bits, so the digits are added up as Double.
    static func hexToDouble(_ hex: String) -> Double? {
        let digits = hex.hasPrefix("0x") ? hex.dropFirst(2) : Substring(hex)
        guard !digits.isEmpty else { return 0 }
        var value: Double = 0
        for c in digits {
            guard let d = c.hexDigitValue else { return nil }
            value = value * 16 + Double(d)
        }
        return value
    }
}
