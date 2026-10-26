import Foundation

/// A transform turns a copied string into something more useful
/// (e.g. "4127*123" -> "507,621"). Return nil when it doesn't apply.
///
/// When one applies, its result is added to the history above the copy and put
/// on the clipboard. To add one: create a file in this folder that implements
/// `Transformer`, and add an instance to `transformers` below.
///
/// `transform` is async so a transform may look things up online; keep it quick,
/// since the result only replaces the clipboard if nothing else was copied meanwhile.
protocol Transformer {
    func transform(_ text: String) async -> String?
}

/// Registered transforms, tried in order; the first non-nil result wins.
let transformers: [Transformer] = [
    MathTransformer(),
    CurrencyTransformer(),
]

func applyTransformers(_ text: String) async -> String? {
    for t in transformers {
        if let result = await t.transform(text) { return result }
    }
    return nil
}
