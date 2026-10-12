import Foundation
import CryptoKit

// Read-only crypto accounts: signatures against the exchanges' documented examples,
// the read-only rules, the balance parsers and the address checks.

@main
enum CryptoAccountsTests {
    nonisolated(unsafe) static var passed = 0

    static func check(_ condition: Bool, _ what: String, file: StaticString = #file, line: UInt = #line) {
        if !condition { fatalError("FAILED: \(what)", file: file, line: line) }
        passed += 1
    }

    static func json(_ text: String) -> Data { Data(text.utf8) }

    static func header(_ r: URLRequest, _ name: String) -> String { r.value(forHTTPHeaderField: name) ?? "" }

    static func main() {
        signatures()
        requests()
        coinbaseJWT()
        permissions()
        balances()
        assets()
        addresses()
        errors()
        clocks()
        storage()
        print("Crypto accounts: \(passed) checks passed")
    }

    // MARK: Documented signature examples

    static func signatures() {
        // Binance "SIGNED endpoint examples" (HMAC SHA256 of the query string).
        let binance = CryptoAPI.hmacHex(SHA256.self,
            key: Data("NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j".utf8),
            message: "symbol=LTCBTC&side=BUY&type=LIMIT&timeInForce=GTC&quantity=1&price=0.1&recvWindow=5000&timestamp=1499827319559")
        check(binance == "c8db56825ae71d6d79447849e617115f4a920fa2acdcab2b053c4b2838bd6b71", "Binance documented signature")

        // Kraken "Authentication" example (HMAC SHA512 of path + SHA256(nonce + body)).
        let krakenSecret = Data(base64Encoded: "kQH5HW/8p1uGOVjbgWA7FunAmGO8lsSUXNsu3eow76sz84Q18fWxnyRzBHCd3pd5nE9qa99HAZtuZuj6F1huXg==")!
        let kraken = CryptoAPI.krakenSignature(path: "/0/private/AddOrder", nonce: "1616492376594",
            body: "nonce=1616492376594&ordertype=limit&pair=XBTUSD&price=37500&type=buy&volume=1.25",
            secret: krakenSecret)
        check(kraken == "4/dpxb3iT4tp/ZCVEwSnEsLxx0bqyhLpdfOpc6fn7OR8+UClSV5n9E6aSS8MPtnRfp32bAb0nmbRn6H8ndwLUQ==",
              "Kraken documented signature")

        // Binance non-ASCII example: percent-encoded (upper-case hex) before signing.
        let nonASCII = CryptoAPI.formEncode([("symbol", "１２３４５６"), ("side", "BUY"), ("type", "LIMIT"), ("timeInForce", "GTC"),
                                             ("quantity", "1"), ("price", "0.1"), ("recvWindow", "5000"), ("timestamp", "1499827319559")])
        check(nonASCII.hasPrefix("symbol=%EF%BC%91%EF%BC%92%EF%BC%93%EF%BC%94%EF%BC%95%EF%BC%96&side=BUY"), "percent-encoding")
        check(CryptoAPI.hmacHex(SHA256.self, key: Data("NhqPtmdSJYdKjVHjA7PZj4Mge3R5YNiP1e3UZjInClVN65XAbvqqM6A7H5fATj0j".utf8), message: nonASCII)
              == "e1353ec6b14d888f1164ae9af8228a3dbd508bc82eb867db8ab6046442f33ef3", "Binance documented non-ASCII signature")

        // Binance Ed25519 example (FIX API Logon): the published key verifies the published signature.
        let fixPEM = "-----BEGIN PRIVATE KEY-----\\nMC4CAQAwBQYDK2VwBCIEIIJEYWtGBrhACmb9Dvy+qa8WEf0lQOl1s4CLIAB9m89u\\n-----END PRIVATE KEY-----"
        let fixKey = CryptoAPI.ed25519Key(fixPEM)
        check(fixKey != nil, "Binance documented Ed25519 key parses")
        let fixMessage = Data("A\u{01}EXAMPLE\u{01}SPOT\u{01}1\u{01}20240627-11:17:25.223".utf8)
        let fixSignature = Data(base64Encoded: "4MHXelVVcpkdwuLbl6n73HQUXUf1dse2PCgT1DYqW9w8AVZ1RACFGM+5UdlGPrQHrgtS3CvsRURC1oj73j8gCA==")!
        check(fixKey?.publicKey.isValidSignature(fixSignature, for: fixMessage) == true, "Binance documented Ed25519 signature")
    }

    // MARK: Requests

    static let now = Date(timeIntervalSince1970: 1_700_000_000.5)   // 2023-11-14T22:13:20.500Z
    static let ms = "1700000000500"

    static func requests() {
        // Binance: recvWindow and timestamp, then the signature of everything before it.
        let binance = CryptoAccount(venue: .binance, apiKey: "KEY", secret: "SECRET")
        let rb = try! CryptoAPI.request(CryptoAPI.permissionEndpoint(.binance)!, account: binance, now: now)
        let qs = "recvWindow=10000&timestamp=\(ms)"
        let sig = CryptoAPI.hmacHex(SHA256.self, key: Data("SECRET".utf8), message: qs)
        check(rb.url?.absoluteString == "https://api.binance.com/sapi/v1/account/apiRestrictions?\(qs)&signature=\(sig)",
              "Binance URL")
        check(header(rb, "X-MBX-APIKEY") == "KEY", "Binance key header")
        check(rb.httpMethod == "GET", "Binance method")
        // Binance Ed25519 key made by Coucou: base64 signature, percent-encoded, that verifies.
        let generated = Curve25519.Signing.PrivateKey()
        check(CryptoAPI.ed25519Key(CryptoAPI.pkcs8PEM(generated))?.publicKey.rawRepresentation == generated.publicKey.rawRepresentation,
              "PKCS#8 round trip")
        check(CryptoAPI.publicKeyPEM(generated).contains("MCowBQYDK2VwAyEA"), "SPKI public key PEM")
        let edBinance = CryptoAccount(venue: .binance, apiKey: "KEY", secret: CryptoAPI.pkcs8PEM(generated))
        let edURL = try! CryptoAPI.request(CryptoAPI.permissionEndpoint(.binance)!, account: edBinance, now: now).url!.absoluteString
        let edSig = edURL.components(separatedBy: "&signature=")[1]
        check(!edSig.contains("+") && !edSig.contains("/") && !edSig.contains("="), "Ed25519 signature percent-encoded")
        check(generated.publicKey.isValidSignature(Data(base64Encoded: edSig.removingPercentEncoding!)!, for: Data(qs.utf8)),
              "Ed25519 signature verifies")

        let spot = CryptoAPI.balanceEndpoints(.binance)[0]
        check(try! CryptoAPI.request(spot, account: binance, now: now).httpMethod == "POST", "Binance getUserAsset is a POST")

        // Bybit: HMAC of timestamp + key + recvWindow + query string, in headers.
        let bybit = CryptoAccount(venue: .bybit, region: "eu", apiKey: "KEY", secret: "SECRET")
        let unified = CryptoAPI.balanceEndpoints(.bybit)[0]
        let ry = try! CryptoAPI.request(unified, account: bybit, now: now)
        check(ry.url?.absoluteString == "https://api.bybit.eu/v5/account/wallet-balance?accountType=UNIFIED", "Bybit URL, EU host")
        check(header(ry, "X-BAPI-SIGN") == CryptoAPI.hmacHex(SHA256.self, key: Data("SECRET".utf8),
              message: ms + "KEY" + "10000" + "accountType=UNIFIED"), "Bybit signature")
        check(header(ry, "X-BAPI-TIMESTAMP") == ms && header(ry, "X-BAPI-RECV-WINDOW") == "10000"
              && header(ry, "X-BAPI-API-KEY") == "KEY", "Bybit headers")

        // OKX: base64 HMAC of ISO timestamp + method + path, with the passphrase header.
        let okx = CryptoAccount(venue: .okx, region: "eea", apiKey: "KEY", secret: "SECRET", passphrase: "PASS")
        let ro = try! CryptoAPI.request(CryptoAPI.permissionEndpoint(.okx)!, account: okx, now: now)
        check(ro.url?.absoluteString == "https://eea.okx.com/api/v5/account/config", "OKX URL, EEA host")
        check(header(ro, "OK-ACCESS-TIMESTAMP") == "2023-11-14T22:13:20.500Z", "OKX timestamp")
        check(header(ro, "OK-ACCESS-SIGN") == CryptoAPI.hmacBase64(SHA256.self, key: Data("SECRET".utf8),
              message: "2023-11-14T22:13:20.500ZGET/api/v5/account/config"), "OKX signature")
        check(header(ro, "OK-ACCESS-PASSPHRASE") == "PASS" && header(ro, "OK-ACCESS-KEY") == "KEY", "OKX headers")

        // Kraken: form body with the nonce, signed.
        let secret = Data("0123456789abcdef0123456789abcdef".utf8).base64EncodedString()
        let kraken = CryptoAccount(venue: .kraken, apiKey: "KEY", secret: secret)
        let rk = try! CryptoAPI.request(CryptoAPI.balanceEndpoints(.kraken)[0], account: kraken, now: now, nonce: "42")
        check(rk.url?.absoluteString == "https://api.kraken.com/0/private/BalanceEx" && rk.httpMethod == "POST", "Kraken URL")
        check(String(data: rk.httpBody ?? Data(), encoding: .utf8) == "nonce=42", "Kraken body")
        check(header(rk, "API-Sign") == CryptoAPI.krakenSignature(path: "/0/private/BalanceEx", nonce: "42",
              body: "nonce=42", secret: Data(base64Encoded: secret)!), "Kraken signature")
        let badKraken = CryptoAccount(venue: .kraken, apiKey: "KEY", secret: "not base64!")
        check((try? CryptoAPI.request(CryptoAPI.balanceEndpoints(.kraken)[0], account: badKraken)) == nil,
              "Kraken refuses a secret that isn't base64")

        // Wallets: plain public calls, no key.
        let eth = CryptoAccount(venue: .ethereum, address: "0x00000000219ab540356cBB839Cbe05303d7705Fa")
        let re = try! CryptoAPI.request(CryptoAPI.balanceEndpoints(.ethereum, address: eth.address)[0], account: eth)
        let body = try! JSONSerialization.jsonObject(with: re.httpBody!) as! [String: Any]
        check(body["method"] as? String == "eth_getBalance"
              && (body["params"] as? [String]) == [eth.address, "latest"], "Ethereum JSON-RPC body")
        let btc = CryptoAccount(venue: .bitcoin, address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")
        let rbtc = try! CryptoAPI.request(CryptoAPI.balanceEndpoints(.bitcoin, address: btc.address)[0], account: btc)
        check(rbtc.url?.absoluteString == "https://mempool.space/api/address/bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh",
              "Bitcoin address URL")

        // Only reads: every endpoint Coucou can call is one of these documented read calls.
        let reads: [String: String] = [
            "coinbase.permissions": "GET /api/v3/brokerage/key_permissions",
            "coinbase.accounts": "GET /api/v3/brokerage/accounts",
            "binance.permissions": "GET /sapi/v1/account/apiRestrictions",
            "binance.spot": "POST /sapi/v3/asset/getUserAsset",
            "binance.funding": "POST /sapi/v1/asset/get-funding-asset",
            "binance.earn.flexible": "GET /sapi/v1/simple-earn/flexible/position",
            "binance.earn.locked": "GET /sapi/v1/simple-earn/locked/position",
            "bybit.permissions": "GET /v5/user/query-api",
            "bybit.unified": "GET /v5/account/wallet-balance",
            "bybit.fund": "GET /v5/asset/transfer/query-account-coins-balance",
            "okx.permissions": "GET /api/v5/account/config",
            "okx.trading": "GET /api/v5/account/balance",
            "okx.funding": "GET /api/v5/asset/balances",
            "okx.savings": "GET /api/v5/finance/savings/balance",
            "okx.onchain-earn": "GET /api/v5/finance/staking-defi/orders-active",
            "kraken.balance": "POST /0/private/BalanceEx",
            "bitcoin.address": "GET /api/address/x",
            "ethereum.balance": "POST /",
            "solana.balance": "POST /",
        ]
        var seen = 0
        for venue in CryptoVenue.allCases {
            let all = CryptoAPI.balanceEndpoints(venue, address: "x") + [CryptoAPI.permissionEndpoint(venue)].compactMap { $0 }
            for e in all {
                check(reads[e.id] == "\(e.method) \(e.path)", "\(e.id) is a known read call")
                seen += 1
            }
        }
        check(seen == reads.count, "every read call is listed")
    }

    // MARK: Coinbase

    static func decodeSegment(_ s: Substring) -> [String: Any] {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return (try? JSONSerialization.jsonObject(with: Data(base64Encoded: b)!)) as? [String: Any] ?? [:]
    }

    static func rawSignature(_ s: Substring) -> Data {
        var b = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b.count % 4 != 0 { b += "=" }
        return Data(base64Encoded: b)!
    }

    static func coinbaseJWT() {
        let keyName = "organizations/org-id/apiKeys/key-id"
        // ES256 key, pasted as one line (line breaks lost) as a SecureField does.
        let ec = P256.Signing.PrivateKey()
        let oneLine = ec.pemRepresentation.replacingOccurrences(of: "\n", with: "")
        let account = CryptoAccount(venue: .coinbase, apiKey: keyName, secret: oneLine)
        let r = try! CryptoAPI.request(CryptoAPI.balanceEndpoints(.coinbase)[0], account: account, now: now, nonce: "abcd")
        check(r.url?.absoluteString == "https://api.coinbase.com/api/v3/brokerage/accounts?limit=250", "Coinbase URL")
        let token = header(r, "Authorization").replacingOccurrences(of: "Bearer ", with: "")
        let parts = token.split(separator: ".")
        check(parts.count == 3, "JWT has three parts")
        let h = decodeSegment(parts[0]), c = decodeSegment(parts[1])
        check(h["alg"] as? String == "ES256" && h["kid"] as? String == keyName && h["nonce"] as? String == "abcd", "JWT header")
        check(c["sub"] as? String == keyName && c["iss"] as? String == "cdp"
              && c["uri"] as? String == "GET api.coinbase.com/api/v3/brokerage/accounts"
              && (c["nbf"] as? Int) == 1_700_000_000 && (c["exp"] as? Int) == 1_700_000_120, "JWT claims")
        let signed = Data((parts[0] + "." + parts[1]).utf8)
        let sig = try! P256.Signing.ECDSASignature(rawRepresentation: rawSignature(parts[2]))
        check(ec.publicKey.isValidSignature(sig, for: signed), "ES256 signature verifies")

        // The same key with "\n" escapes, as in the downloaded JSON file.
        let escaped = ec.pemRepresentation.replacingOccurrences(of: "\n", with: "\\n")
        check(CryptoAPI.normalizedPEM(escaped) == ec.pemRepresentation.trimmingCharacters(in: .whitespacesAndNewlines),
              "PEM with \\n escapes")

        // Ed25519 key: base64 of seed + public key.
        let ed = Curve25519.Signing.PrivateKey()
        let edSecret = (ed.rawRepresentation + ed.publicKey.rawRepresentation).base64EncodedString()
        let edAccount = CryptoAccount(venue: .coinbase, apiKey: keyName, secret: edSecret)
        let re = try! CryptoAPI.request(CryptoAPI.permissionEndpoint(.coinbase)!, account: edAccount, now: now, nonce: "ef")
        let edParts = header(re, "Authorization").replacingOccurrences(of: "Bearer ", with: "").split(separator: ".")
        check(decodeSegment(edParts[0])["alg"] as? String == "EdDSA", "EdDSA header")
        check(ed.publicKey.isValidSignature(rawSignature(edParts[2]), for: Data((edParts[0] + "." + edParts[1]).utf8)),
              "EdDSA signature verifies")

        // Coinbase's own SDK test key (SEC1 "EC PRIVATE KEY"): parsed, and its public key matches the DER.
        let sdkPEM = "-----BEGIN EC PRIVATE KEY-----\\nMHcCAQEEIKwf3Uox30cRWzRBOPoPOH5p0Gpb0Dt8zUKXUEM5fMkGoAoGCCqGSM49\\nAwEHoUQDQgAEbAtpLlSZYVOwYICz+uEyxcS29vRIujiES/gQ1DC7FV4zK4JuYE9v\\nqDyGZQYjdXHLM7I6f/QnnOITL+dXYWBHRA==\\n-----END EC PRIVATE KEY-----\\n"
        let sdkDER = Data(base64Encoded: "MHcCAQEEIKwf3Uox30cRWzRBOPoPOH5p0Gpb0Dt8zUKXUEM5fMkGoAoGCCqGSM49AwEHoUQDQgAEbAtpLlSZYVOwYICz+uEyxcS29vRIujiES/gQ1DC7FV4zK4JuYE9vqDyGZQYjdXHLM7I6f/QnnOITL+dXYWBHRA==")!
        if case .p256(let k)? = try? CryptoAPI.coinbaseKey(keyName: "organizations/test-organization/apiKeys/test-api-key", secret: sdkPEM) {
            check(k.publicKey.x963Representation == sdkDER.suffix(65), "SEC1 key from Coinbase's SDK tests")
        } else {
            check(false, "SEC1 key from Coinbase's SDK tests parses")
        }

        // Ed25519 as PKCS#8 PEM.
        let pkcs8 = Data([0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20])
            + ed.rawRepresentation
        let edPEM = "-----BEGIN PRIVATE KEY-----\n" + pkcs8.base64EncodedString() + "\n-----END PRIVATE KEY-----"
        if case .ed25519(let k)? = try? CryptoAPI.coinbaseKey(keyName: keyName, secret: edPEM) {
            check(k.publicKey.rawRepresentation == ed.publicKey.rawRepresentation, "Ed25519 PKCS#8 PEM")
        } else {
            check(false, "Ed25519 PKCS#8 PEM parses")
        }

        // A 64-byte key whose public half doesn't match its seed is refused.
        let mismatched = (ed.rawRepresentation + Curve25519.Signing.PrivateKey().publicKey.rawRepresentation).base64EncodedString()
        check((try? CryptoAPI.coinbaseKey(keyName: keyName, secret: mismatched)) == nil, "mismatched Ed25519 halves")

        // Keys from before February 2025 get their own message.
        do { _ = try CryptoAPI.coinbaseKey(keyName: "g3BLnUYMOQsIo9V5", secret: "M4009eFnOoPwhNoMwJlsAHgIgleGVFPl"); check(false, "legacy") }
        catch { check(error as? CryptoAccountError == .legacyCoinbaseKey, "legacy Coinbase key") }

        let bad = CryptoAccount(venue: .coinbase, apiKey: keyName, secret: "-----BEGIN EC PRIVATE KEY-----nope-----END EC PRIVATE KEY-----")
        check((try? CryptoAPI.request(CryptoAPI.permissionEndpoint(.coinbase)!, account: bad)) == nil, "bad PEM refused")
    }

    // MARK: Read-only rules

    static func permissions() {
        check(try! CryptoAPI.parsePermissions(.coinbase, json(#"{"can_view":true,"can_trade":false,"can_transfer":false,"portfolio_uuid":"x","portfolio_type":"DEFAULT"}"#)) == .readOnly,
              "Coinbase view-only")
        check(try! CryptoAPI.parsePermissions(.coinbase, json(#"{"can_view":true,"can_trade":true,"can_transfer":false}"#)) == .tooPowerful(["can_trade"]),
              "Coinbase trade")
        check(try! CryptoAPI.parsePermissions(.coinbase, json(#"{"can_view":true,"can_transfer":false}"#)) == .tooPowerful(["can_trade"]),
              "Coinbase: a missing can_trade fails closed")
        check((try? CryptoAPI.parsePermissions(.coinbase, json(#"{"can_view":false,"can_trade":false,"can_transfer":false}"#))) == nil,
              "Coinbase: a key that can't view is refused")

        let binanceReadOnly = #"{"ipRestrict":false,"createTime":1698645219000,"enableReading":true,"enableWithdrawals":false,"enableInternalTransfer":false,"enableMargin":false,"enableFutures":false,"permitsUniversalTransfer":false,"enableVanillaOptions":false,"enableFixApiTrade":false,"enableFixReadOnly":true,"enableSpotAndMarginTrading":false,"enablePortfolioMarginTrading":false}"#
        check(try! CryptoAPI.parsePermissions(.binance, json(binanceReadOnly)) == .readOnly, "Binance read-only")
        let binanceTrade = binanceReadOnly.replacingOccurrences(of: #""enableSpotAndMarginTrading":false"#, with: #""enableSpotAndMarginTrading":true"#)
            .replacingOccurrences(of: #""enableWithdrawals":false"#, with: #""enableWithdrawals":true"#)
        check(try! CryptoAPI.parsePermissions(.binance, json(binanceTrade)) == .tooPowerful(["enableSpotAndMarginTrading", "enableWithdrawals"]),
              "Binance trade + withdraw")
        let binanceNew = binanceReadOnly.replacingOccurrences(of: #""ipRestrict":false"#, with: #""ipRestrict":false,"enableNewThing":true"#)
        check(try! CryptoAPI.parsePermissions(.binance, json(binanceNew)) == .tooPowerful(["enableNewThing"]),
              "Binance: an unknown right counts as too much")
        let binanceMissing = binanceReadOnly.replacingOccurrences(of: #""enableFutures":false,"#, with: "")
        check(try! CryptoAPI.parsePermissions(.binance, json(binanceMissing)) == .tooPowerful(["enableFutures"]),
              "Binance: a missing right fails closed")
        // The docs' own example response has transfers and portfolio margin on: refused.
        let binanceDocs = #"{"ipRestrict":false,"createTime":1623840271000,"enableReading":true,"enableWithdrawals":false,"enableInternalTransfer":true,"enableMargin":false,"enableFutures":false,"permitsUniversalTransfer":true,"enableVanillaOptions":false,"enableFixApiTrade":false,"enableFixReadOnly":true,"enableSpotAndMarginTrading":false,"enablePortfolioMarginTrading":true}"#
        check(try! CryptoAPI.parsePermissions(.binance, json(binanceDocs))
              == .tooPowerful(["enableInternalTransfer", "enablePortfolioMarginTrading", "permitsUniversalTransfer"]),
              "Binance documented example is refused")

        check(try! CryptoAPI.parsePermissions(.bybit, json(#"{"retCode":0,"retMsg":"","result":{"readOnly":1,"permissions":{"Wallet":[],"Spot":[]}}}"#)) == .readOnly,
              "Bybit read-only")
        check(try! CryptoAPI.parsePermissions(.bybit, json(#"{"retCode":0,"retMsg":"","result":{"readOnly":0,"permissions":{"Spot":["SpotTrade"],"Wallet":["AccountTransfer"]}}}"#))
              == .tooPowerful(["Spot.SpotTrade", "Wallet.AccountTransfer"]), "Bybit trade")

        check(try! CryptoAPI.parsePermissions(.okx, json(#"{"code":"0","msg":"","data":[{"perm":"read_only","uid":"1"}]}"#)) == .readOnly,
              "OKX read-only")
        check(try! CryptoAPI.parsePermissions(.okx, json(#"{"code":"0","msg":"","data":[{"perm":"read_only,withdraw,trade"}]}"#)) == .tooPowerful(["withdraw", "trade"]),
              "OKX withdraw + trade")
    }

    // MARK: Balances

    static func amounts(_ venue: CryptoVenue, _ id: String, _ text: String) -> [String: Double] {
        let endpoint = (CryptoAPI.balanceEndpoints(venue, address: "x") ).first { $0.id == id }!
        let page = try! CryptoAPI.parseBalances(endpoint, venue: venue, json(text))
        return Dictionary(uniqueKeysWithValues: page.holdings.map { ($0.asset, $0.amount) })
    }

    static func close(_ a: Double?, _ b: Double) -> Bool { a.map { abs($0 - b) < 1e-9 * max(1, abs(b)) } ?? false }

    static func balances() {
        let cb = try! CryptoAPI.parseBalances(CryptoAPI.balanceEndpoints(.coinbase)[0], venue: .coinbase, json(#"""
        {"accounts":[{"uuid":"1","currency":"BTC","available_balance":{"value":"0.5","currency":"BTC"},"hold":{"value":"0.25","currency":"BTC"}},
                     {"uuid":"2","currency":"EUR","available_balance":{"value":"100","currency":"EUR"},"hold":{"value":"0","currency":"EUR"}},
                     {"uuid":"3","currency":"ETH","available_balance":{"value":"0","currency":"ETH"},"hold":{"value":"0","currency":"ETH"}}],
         "has_next":true,"cursor":"next-page","size":3}
        """#))
        check(cb.next == "next-page", "Coinbase cursor")
        let cbAmounts = Dictionary(uniqueKeysWithValues: cb.holdings.map { ($0.asset, $0.amount) })
        check(close(cbAmounts["BTC"], 0.75) && close(cbAmounts["EUR"], 100) && cbAmounts["ETH"] == nil, "Coinbase holdings")

        let spot = amounts(.binance, "binance.spot", #"[{"asset":"BTC","free":"1","locked":"0.5","freeze":"0","withdrawing":"0","ipoable":"0","btcValuation":"0"}]"#)
        check(close(spot["BTC"], 1.5), "Binance spot")
        let flexible = amounts(.binance, "binance.earn.flexible", #"{"rows":[{"asset":"USDT","totalAmount":"75.46000000"}],"total":1}"#)
        check(close(flexible["USDT"], 75.46), "Binance Simple Earn flexible")

        let unified = amounts(.bybit, "bybit.unified", #"{"retCode":0,"retMsg":"OK","result":{"list":[{"accountType":"UNIFIED","coin":[{"coin":"BTC","walletBalance":"0.1"},{"coin":"USDT","walletBalance":"12.5"}]}]}}"#)
        check(close(unified["BTC"], 0.1) && close(unified["USDT"], 12.5), "Bybit unified")
        let fund = amounts(.bybit, "bybit.fund", #"{"retCode":0,"retMsg":"success","result":{"memberId":"1","accountType":"FUND","balance":[{"coin":"SOL","walletBalance":"3","transferBalance":"3"}]}}"#)
        check(close(fund["SOL"], 3), "Bybit funding")

        let trading = amounts(.okx, "okx.trading", #"{"code":"0","msg":"","data":[{"totalEq":"100","details":[{"ccy":"ETH","eq":"2.5","cashBal":"2.5"}]}]}"#)
        check(close(trading["ETH"], 2.5), "OKX trading")
        let staked = amounts(.okx, "okx.onchain-earn", #"{"code":"0","msg":"","data":[{"ordId":"1","ccy":"SOL","investData":[{"ccy":"SOL","amt":"10"}],"earningData":[{"ccy":"SOL","earningType":"0","earnings":"0.1"}]}]}"#)
        check(close(staked["SOL"], 10), "OKX on-chain earn, earnings not counted")
        let funding = amounts(.okx, "okx.funding", #"{"code":"0","msg":"","data":[{"ccy":"BTC","bal":"0.01","availBal":"0.01","frozenBal":"0"}]}"#)
        check(close(funding["BTC"], 0.01), "OKX funding")

        let kraken = amounts(.kraken, "kraken.balance", #"{"error":[],"result":{"XXBT":{"balance":"0.2","hold_trade":"0"},"XBT.F":{"balance":"0.05","hold_trade":"0"},"ZEUR":{"balance":"50","hold_trade":"0"},"DOT.S":{"balance":"10","hold_trade":"0"}}}"#)
        check(close(kraken["BTC"], 0.25) && close(kraken["EUR"], 50) && close(kraken["DOT"], 10), "Kraken holdings, earn merged")

        let btc = amounts(.bitcoin, "bitcoin.address", #"{"address":"x","chain_stats":{"funded_txo_count":2,"funded_txo_sum":150000000,"spent_txo_count":1,"spent_txo_sum":50000000,"tx_count":3},"mempool_stats":{"funded_txo_count":0,"funded_txo_sum":1000,"spent_txo_count":0,"spent_txo_sum":0,"tx_count":1}}"#)
        check(close(btc["BTC"], 1.00001), "Bitcoin confirmed + pending")
        let eth = amounts(.ethereum, "ethereum.balance", #"{"jsonrpc":"2.0","id":1,"result":"0x1bc16d674ec80000"}"#)
        check(close(eth["ETH"], 2), "Ethereum wei")
        let big = amounts(.ethereum, "ethereum.balance", #"{"jsonrpc":"2.0","id":1,"result":"0x3635c9adc5dea00000"}"#)
        check(close(big["ETH"], 1000), "Ethereum balance above 2^64 wei")
        let sol = amounts(.solana, "solana.balance", #"{"jsonrpc":"2.0","result":{"context":{"slot":1},"value":2500000000},"id":1}"#)
        check(close(sol["SOL"], 2.5), "Solana lamports")
    }

    static func assets() {
        check(CryptoAPI.normalizeAsset("XXBT", venue: .kraken) == "BTC", "XXBT")
        check(CryptoAPI.normalizeAsset("XBT.M", venue: .kraken) == "BTC", "XBT.M")
        check(CryptoAPI.normalizeAsset("ETH2.S", venue: .kraken) == "ETH", "ETH2.S")
        check(CryptoAPI.normalizeAsset("ZUSD", venue: .kraken) == "USD", "ZUSD")
        check(CryptoAPI.normalizeAsset("XXDG", venue: .kraken) == "DOGE", "XXDG")
        check(CryptoAPI.normalizeAsset("sol", venue: .binance) == "SOL", "upper-case")
        check(CryptoAPI.normalizeAsset("LDO", venue: .binance) == "LDO", "LDO stays LDO")
        check(CryptoAPI.normalizeAsset("BAD COIN", venue: .okx) == nil, "odd names dropped")
        check(CryptoAPI.hexToDouble("0x0") == 0 && CryptoAPI.hexToDouble("0xzz") == nil, "hex parsing")
    }

    static func addresses() {
        check(CryptoAPI.isValidAddress("bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", venue: .bitcoin), "bech32")
        check(CryptoAPI.isValidAddress("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa", venue: .bitcoin), "legacy P2PKH")
        check(CryptoAPI.isValidAddress("3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy", venue: .bitcoin), "P2SH")
        check(!CryptoAPI.isValidAddress("bc1qXy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh", venue: .bitcoin), "mixed-case bech32")
        check(!CryptoAPI.isValidAddress("0x00000000219ab540356cBB839Cbe05303d7705Fa", venue: .bitcoin), "ETH address isn't BTC")
        check(CryptoAPI.isValidAddress("0x00000000219ab540356cBB839Cbe05303d7705Fa", venue: .ethereum), "ETH")
        check(!CryptoAPI.isValidAddress("0x00000000219ab540356cBB839Cbe05303d7705F", venue: .ethereum), "ETH too short")
        check(CryptoAPI.isValidAddress("Vote111111111111111111111111111111111111111", venue: .solana), "SOL")
        check(!CryptoAPI.isValidAddress("0OIl", venue: .solana), "SOL bad characters")
    }

    static func errors() {
        let bybitError = json(#"{"retCode":10003,"retMsg":"API key is invalid.","result":{}}"#)
        do { _ = try CryptoAPI.parsePermissions(.bybit, bybitError); check(false, "Bybit error should throw") }
        catch { check(error as? CryptoAccountError == .rejected("API key is invalid."), "Bybit error message") }
        check(CryptoAPI.errorMessage(.binance, json(#"{"code":-2015,"msg":"Invalid API-key, IP, or permissions for action."}"#))
              == "Invalid API-key, IP, or permissions for action.", "Binance error message")
        check(CryptoAPI.errorMessage(.kraken, json(#"{"error":["EAPI:Invalid key"]}"#)) == "EAPI:Invalid key", "Kraken error")
        check(CryptoAPI.errorMessage(.okx, json(#"{"code":"50111","msg":"Invalid OK-ACCESS-KEY","data":[]}"#)) == "Invalid OK-ACCESS-KEY", "OKX error")
    }

    static func clocks() {
        check(CryptoAPI.parseServerTime(.binance, json(#"{"serverTime":1499827319559}"#)) == 1499827319.559, "Binance time")
        check(CryptoAPI.parseServerTime(.okx, json(#"{"code":"0","msg":"","data":[{"ts":"1597026383085"}]}"#)) == 1597026383.085, "OKX time")
        check(CryptoAPI.parseServerTime(.bybit, json(#"{"retCode":0,"retMsg":"OK","result":{"timeSecond":"1688639403","timeNano":"1688639403423213947"},"time":1688639403423}"#))
              .map { abs($0 - 1688639403.423) < 0.01 } == true, "Bybit time")
        check(CryptoAPI.parseServerTime(.coinbase, json(#"{"iso":"2023-05-18T12:34:56Z","epochSeconds":"1684413296","epochMillis":"1684413296123"}"#))
              == 1684413296.123, "Coinbase time")
    }

    static func storage() {
        let a = [CryptoAccount(venue: .okx, label: "Main", region: "eea", apiKey: "k", secret: "s", passphrase: "p"),
                 CryptoAccount(venue: .bitcoin, address: "bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh")]
        check(CryptoAccountStore.decode(CryptoAccountStore.encode(a)) == a, "accounts round-trip")
        check(CryptoAccountStore.decode(nil).isEmpty && CryptoAccountStore.decode("garbage").isEmpty, "empty store")
    }
}
