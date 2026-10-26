import Foundation

/// Evaluates a copied sum such as "4127*123" -> "507,621".
/// Supports + - * / × ÷ ^, parentheses, decimals and a trailing "=".
/// Text that is anything other than a calculation is left alone.
final class MathTransformer: Transformer {
    override class var title: String { "Math" }
    override class var summary: String {
        "Copy a sum like 4127*123 and get 507,621. Supports + − × ÷ ^ and brackets; dates and phone numbers are left alone."
    }

    override func transform(_ text: String) async -> String? {
        var expr = text.trimmingCharacters(in: .whitespaces)
        if expr.hasSuffix("=") { expr.removeLast() }
        guard expr.count <= 200, looksLikeMath(expr) else { return nil }

        var parser = Parser(Array(expr))
        guard let value = parser.parse(), value.isFinite else { return nil }
        return Self.format(value)
    }

    /// Needs a digit and an operator, and must not look like a date or a phone
    /// number: "2026-10-26", "10/26" and "020-7946" only use - or / with no spaces.
    private func looksLikeMath(_ s: String) -> Bool {
        guard s.contains(where: \.isNumber) else { return false }
        let ops = Set(s.filter { "+-*/×÷^".contains($0) })
        guard !ops.isEmpty else { return false }
        let onlyDashOrSlash = ops.isSubset(of: ["-", "/"])
        return !onlyDashOrSlash || s.contains(" ") || s.contains("(")
    }

    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 10
        return f
    }()

    static func format(_ value: Double) -> String? {
        formatter.string(from: NSNumber(value: value))
    }
}

/// Recursive descent: expr = term (('+'|'-') term)*, term = power (('*'|'/') power)*,
/// power = unary ('^' power)?, unary = '-' unary | primary, primary = number | '(' expr ')'.
private struct Parser {
    private let chars: [Character]
    private var pos = 0

    init(_ chars: [Character]) { self.chars = chars }

    mutating func parse() -> Double? {
        guard let v = expr() else { return nil }
        skipSpaces()
        return pos == chars.count ? v : nil  // trailing junk means it wasn't a sum
    }

    private mutating func expr() -> Double? {
        guard var v = term() else { return nil }
        while let op = peekOp(in: "+-") {
            pos += 1
            guard let rhs = term() else { return nil }
            v = op == "+" ? v + rhs : v - rhs
        }
        return v
    }

    private mutating func term() -> Double? {
        guard var v = power() else { return nil }
        while let op = peekOp(in: "*/×÷") {
            pos += 1
            guard let rhs = power() else { return nil }
            v = (op == "/" || op == "÷") ? v / rhs : v * rhs
        }
        return v
    }

    private mutating func power() -> Double? {
        guard let base = unary() else { return nil }
        if peekOp(in: "^") != nil {
            pos += 1
            guard let exp = power() else { return nil }
            return pow(base, exp)
        }
        return base
    }

    private mutating func unary() -> Double? {
        if peekOp(in: "-") != nil {
            pos += 1
            return unary().map { -$0 }
        }
        return primary()
    }

    private mutating func primary() -> Double? {
        skipSpaces()
        guard pos < chars.count else { return nil }
        if chars[pos] == "(" {
            pos += 1
            guard let v = expr() else { return nil }
            skipSpaces()
            guard pos < chars.count, chars[pos] == ")" else { return nil }
            pos += 1
            return v
        }
        let start = pos
        while pos < chars.count, chars[pos].isNumber || chars[pos] == "." { pos += 1 }
        return Double(String(chars[start..<pos]))
    }

    private mutating func peekOp(in ops: String) -> Character? {
        skipSpaces()
        guard pos < chars.count, ops.contains(chars[pos]) else { return nil }
        return chars[pos]
    }

    private mutating func skipSpaces() {
        while pos < chars.count, chars[pos] == " " { pos += 1 }
    }
}
