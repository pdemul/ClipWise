import Foundation

/// A transform turns a copied string into something more useful
/// (e.g. "4127*123" -> "507,621"). Return nil when it doesn't apply.
protocol Transformer {
    func transform(_ text: String) -> String?
}

/// Registered transforms, tried in order; the first non-nil result wins.
/// Empty in v1.
let transformers: [Transformer] = []

func applyTransformers(_ text: String) -> String? {
    for t in transformers {
        if let result = t.transform(text) { return result }
    }
    return nil
}
