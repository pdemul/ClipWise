import Foundation

/// Converts "1.23 GBP in USD" -> "1.64 USD", using the day's European Central Bank
/// rates from frankfurter.dev (free, no key, ~30 major currencies).
/// Also accepts "to"/"as"/"into"/"=", lowercase codes and £ $ € ¥: "£1.23 to usd", "€50 in GBP".
struct CurrencyTransformer: Transformer {
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([£$€¥])?\s*(\d[\d,]*(?:\.\d+)?|\.\d+)\s*([A-Za-z]{3})?\s+(?:in|to|as|into|=)\s+([£$€¥]|[A-Za-z]{3})\s*\??$"#,
        options: [.caseInsensitive])

    private static let symbols: [String: String] = ["£": "GBP", "$": "USD", "€": "EUR", "¥": "JPY"]

    func transform(_ text: String) async -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = Self.pattern.firstMatch(in: text, range: range) else { return nil }
        func group(_ i: Int) -> String? { Range(m.range(at: i), in: text).map { String(text[$0]) } }

        // Need a source currency from either the symbol or the code, not two different ones.
        let fromSymbol = group(1).flatMap { Self.symbols[$0] }
        let fromCode = group(3)?.uppercased()
        if let fromSymbol, let fromCode, fromSymbol != fromCode { return nil }
        guard let from = fromCode ?? fromSymbol,
              let amountText = group(2), let amount = Double(amountText.replacingOccurrences(of: ",", with: "")),
              let toRaw = group(4) else { return nil }
        let to = Self.symbols[toRaw] ?? toRaw.uppercased()
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
                NSLog("ClipHistory: no rates for \(from) (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0))")
                return nil
            }
            let rates = try JSONDecoder().decode(Response.self, from: data).rates
            tables[from] = (Date(), rates)
            if rates[to] == nil { NSLog("ClipHistory: no \(from)→\(to) rate available") }
            return rates[to]
        } catch {
            NSLog("ClipHistory: rate lookup \(from)→\(to) failed: \(error.localizedDescription)")
            return nil
        }
    }
}
