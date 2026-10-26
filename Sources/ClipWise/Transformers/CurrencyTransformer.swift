import Foundation

/// Converts "1.23 GBP in USD" -> "1.64 USD", using the day's European Central Bank
/// rates from frankfurter.dev (free, no key, ~30 major currencies).
/// Currencies can be codes, symbols or names: "£1.23 to usd", "100 Swedish to GBP=",
/// "50 swiss francs in euros". Linked by in/to/as/into/=, with an optional trailing = or ?.
final class CurrencyTransformer: Transformer {
    override class var title: String { "Currency conversion" }
    override class var summary: String {
        "Copy 1.23 GBP in USD, £50 to eur or 100 Swedish to GBP= and get the amount at today's European Central Bank rate."
    }

    // symbol? amount currency-words? (in|to|as|into|=) currency-words [=?]?
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([£$€¥])?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)\s*(.*?)\s*\b(?:in|to|as|into)\b\s*(.+?)\s*[=?]?$|^([£$€¥])?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)\s*(.*?)\s*=\s*(.+?)\s*[=?]?$"#,
        options: [.caseInsensitive])

    private static let symbols: [String: String] = ["£": "GBP", "$": "USD", "€": "EUR", "¥": "JPY"]

    /// The currencies frankfurter.dev has rates for.
    private static let codes: Set<String> = [
        "AUD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EUR", "GBP", "HKD", "HUF", "IDR", "ILS", "INR", "ISK",
        "JPY", "KRW", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "RON", "SEK", "SGD", "THB", "TRY", "USD", "ZAR",
    ]

    /// Names and adjectives, lowercase. A trailing "s" is also tried, so "euros" and "francs" work.
    /// Ambiguous words ("krone", "peso", "franc" alone) are left out on purpose.
    private static let names: [String: String] = [
        "australian": "AUD", "australian dollar": "AUD", "aussie dollar": "AUD",
        "brazilian": "BRL", "real": "BRL", "reais": "BRL", "brazilian real": "BRL",
        "canadian": "CAD", "canadian dollar": "CAD",
        "swiss": "CHF", "swiss franc": "CHF",
        "chinese": "CNY", "yuan": "CNY", "renminbi": "CNY", "rmb": "CNY",
        "czech": "CZK", "koruna": "CZK", "czech koruna": "CZK",
        "danish": "DKK", "danish krone": "DKK", "danish kroner": "DKK",
        "euro": "EUR",
        "british": "GBP", "pound": "GBP", "sterling": "GBP", "pound sterling": "GBP", "british pound": "GBP", "quid": "GBP",
        "hong kong": "HKD", "hong kong dollar": "HKD",
        "hungarian": "HUF", "forint": "HUF",
        "indonesian": "IDR", "rupiah": "IDR",
        "israeli": "ILS", "shekel": "ILS", "shekalim": "ILS",
        "indian": "INR", "rupee": "INR", "indian rupee": "INR",
        "icelandic": "ISK", "icelandic krona": "ISK",
        "japanese": "JPY", "yen": "JPY", "japanese yen": "JPY",
        "korean": "KRW", "south korean": "KRW", "won": "KRW",
        "mexican": "MXN", "mexican peso": "MXN",
        "malaysian": "MYR", "ringgit": "MYR",
        "norwegian": "NOK", "norwegian krone": "NOK", "norwegian kroner": "NOK",
        "new zealand": "NZD", "new zealand dollar": "NZD", "kiwi dollar": "NZD",
        "philippine": "PHP", "philippine peso": "PHP",
        "polish": "PLN", "zloty": "PLN", "zlotys": "PLN",
        "romanian": "RON", "leu": "RON", "lei": "RON",
        "swedish": "SEK", "krona": "SEK", "kronor": "SEK", "swedish krona": "SEK", "swedish kronor": "SEK",
        "swedish krone": "SEK", "swedish kroner": "SEK",  // common misspelling, unambiguous with "swedish"
        "singapore": "SGD", "singaporean": "SGD", "singapore dollar": "SGD",
        "thai": "THB", "baht": "THB",
        "turkish": "TRY", "lira": "TRY", "turkish lira": "TRY",
        "dollar": "USD", "us dollar": "USD", "american": "USD", "american dollar": "USD", "buck": "USD",
        "south african": "ZAR", "rand": "ZAR",
    ]

    /// Extra words only accepted when the other side is an exact code, where a guess is safe.
    private static let looseNames: [String: String] = [
        "franc": "CHF", "peso": "MXN", "crown": "SEK", "kr": "SEK",
    ]

    private static func normalise(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespaces).lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// True for an exact ISO code ("GBP", "sek") or a symbol.
    private static func isExactCode(_ raw: String) -> Bool {
        let s = normalise(raw)
        return symbols[s] != nil || codes.contains(s.uppercased())
    }

    /// A code, symbol or name -> ISO code, or nil if it isn't a currency we know.
    /// `tolerant` (the other side is an exact code) also accepts prefixes ("swe"),
    /// typos ("sweedish") and extra words ("swedish crowns").
    private static func currency(_ raw: String, tolerant: Bool = false) -> String? {
        let s = normalise(raw)
        if let code = symbols[s] { return code }
        if codes.contains(s.uppercased()) { return s.uppercased() }
        if let code = names[s] { return code }
        if s.hasSuffix("s"), let code = names[String(s.dropLast())] { return code }
        guard tolerant else { return nil }

        // Danish or Norwegian? Only resolved with a country word ("danish krone").
        if ["krone", "kroner"].contains(s) { return nil }
        let all = names.merging(looseNames) { a, _ in a }
        let singular = s.hasSuffix("s") ? String(s.dropLast()) : s
        if let code = all[singular] { return code }
        // Any of several words, as long as they all point the same way.
        let words = s.split(separator: " ").map(String.init)
        if words.count > 1 {
            let found = Set(words.compactMap { currency($0, tolerant: true) })
            return found.count == 1 ? found.first : nil
        }
        // A prefix of exactly one currency's names: "swe", "norw", "jap".
        if s.count >= 3 {
            let found = Set(all.filter { $0.key.hasPrefix(s) }.values)
            if found.count == 1 { return found.first }
        }
        // A typo: the closest name within 2 edits, if only one currency is that close.
        if s.count >= 5 {
            let scored = all.map { (code: $0.value, distance: editDistance(s, $0.key)) }
            if let best = scored.map(\.distance).min(), best <= 2 {
                let found = Set(scored.filter { $0.distance == best }.map(\.code))
                if found.count == 1 { return found.first }
            }
        }
        return nil
    }

    private static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        var row = Array(0...b.count)  // Levenshtein, one row at a time
        for i in a.indices {
            var diagonal = row[0]
            row[0] = i + 1
            for j in b.indices {
                let above = row[j + 1]
                row[j + 1] = a[i] == b[j] ? diagonal : min(diagonal, above, row[j]) + 1
                diagonal = above
            }
        }
        return row[b.count]
    }

    override func transform(_ text: String) async -> String? {
        let text = text.trimmingCharacters(in: .whitespaces)
        let range = NSRange(text.startIndex..., in: text)
        guard let m = Self.pattern.firstMatch(in: text, range: range) else { return nil }
        // Groups 1-4 for the in/to/as/into form, 5-8 for the "=" form.
        let base = m.range(at: 2).location != NSNotFound ? 0 : 4
        func group(_ i: Int) -> String? {
            Range(m.range(at: base + i), in: text).map { String(text[$0]) }.flatMap { $0.isEmpty ? nil : $0 }
        }

        guard let amountText = group(2), let amount = Double(amountText.replacingOccurrences(of: ",", with: "")),
              let toWords = group(4) else { return nil }
        let symbol = group(1)
        let fromWords = group(3)

        // If one side is an exact code or symbol, the other side may be loose ("100 sweedish to GBP").
        // Otherwise both must be exact names, so "5 people in London" is left alone.
        let sourceIsExact = symbol != nil || fromWords.map(Self.isExactCode) == true
        let targetIsExact = Self.isExactCode(toWords)

        // The source comes from the symbol, the words after the amount, or both if they agree.
        let fromSymbol = symbol.flatMap { Self.symbols[$0] }
        var fromCode: String?
        if let fromWords {
            guard let code = Self.currency(fromWords, tolerant: targetIsExact) else { return nil }
            fromCode = code
        }
        if let fromSymbol, let fromCode, fromSymbol != fromCode { return nil }
        guard let from = fromCode ?? fromSymbol,
              let to = Self.currency(toWords, tolerant: sourceIsExact) else { return nil }
        guard from != to else { return nil }

        guard let rate = await RateCache.shared.rate(from: from, to: to) else { return nil }
        return Self.format(amount * rate, currency: to)
    }

    private static func format(_ value: Double, currency: String) -> String? {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)).map { "\($0) \(currency)" }
    }
}

/// One fetch per base currency per hour; ECB rates only change once a day.
private actor RateCache {
    static let shared = RateCache()
    private var tables: [String: (fetched: Date, rates: [String: Double])] = [:]

    private struct Response: Decodable { let rates: [String: Double] }

    func rate(from: String, to: String) async -> Double? {
        if let cached = tables[from], Date().timeIntervalSince(cached.fetched) < 3600 {
            return cached.rates[to]
        }
        guard let url = URL(string: "https://api.frankfurter.dev/v1/latest?base=\(from)") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                // An unknown currency code lands here (404), as does an outage.
                NSLog("ClipWise: no rates for \(from) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return nil
            }
            let rates = try JSONDecoder().decode(Response.self, from: data).rates
            tables[from] = (Date(), rates)
            if rates[to] == nil { NSLog("ClipWise: no \(from)→\(to) rate available") }
            return rates[to]
        } catch {
            NSLog("ClipWise: rate lookup \(from)→\(to) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
