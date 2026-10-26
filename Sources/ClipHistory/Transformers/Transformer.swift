import Foundation
import ObjectiveC

/// A transform turns a copied string into something more useful
/// (e.g. "4127*123" -> "507,621"). When one applies, its result is added to the
/// history above the copy and put on the clipboard.
///
/// To add one, create a file in this folder with a subclass that overrides
/// `title`, `summary` and `transform`, and rebuild. Every subclass is found at
/// launch and listed in Settings, where it can be switched off; there is no list
/// to register it in.
class Transformer: NSObject {
    /// Name shown in Settings.
    class var title: String { String(describing: self) }
    /// One or two short sentences for Settings: what it matches and what it gives.
    class var summary: String { "" }

    required override init() {}

    /// Return the new text, or nil when the copy isn't for this transform.
    /// Async so a transform may look things up online; its result is dropped
    /// if something else was copied in the meantime.
    func transform(_ text: String) async -> String? { nil }
}

@MainActor
final class TransformerRegistry {
    static let shared = TransformerRegistry()

    /// Every Transformer subclass in the app, alphabetical by title. They are
    /// tried in this order and the first result wins, so match strictly.
    let all: [Transformer]
    private var disabled: Set<String>

    private init() {
        all = Self.discover().map { $0.init() }
            .sorted { type(of: $0).title.localizedCaseInsensitiveCompare(type(of: $1).title) == .orderedAscending }
        disabled = Set(UserDefaults.standard.stringArray(forKey: "disabledTransformers") ?? [])
        NSLog("ClipHistory: transformers found: \(all.map { "\(type(of: $0).title)\(isEnabled($0) ? "" : " (off)")" }.joined(separator: ", "))")
    }

    static func id(_ t: Transformer) -> String { NSStringFromClass(type(of: t)) }

    func isEnabled(_ t: Transformer) -> Bool { !disabled.contains(Self.id(t)) }

    func setEnabled(_ t: Transformer, _ on: Bool) {
        if on { disabled.remove(Self.id(t)) } else { disabled.insert(Self.id(t)) }
        UserDefaults.standard.set(Array(disabled).sorted(), forKey: "disabledTransformers")
    }

    func apply(_ text: String) async -> String? {
        for t in all where isEnabled(t) {
            if let result = await t.transform(text) { return result }
        }
        return nil
    }

    /// Walk the Objective-C class list for subclasses of Transformer.
    private static func discover() -> [Transformer.Type] {
        var count: UInt32 = 0
        guard let classes = objc_copyClassList(&count) else { return [] }
        defer { free(UnsafeMutableRawPointer(classes)) }
        let base = ObjectIdentifier(Transformer.self)
        var found: [Transformer.Type] = []
        for cls in UnsafeBufferPointer(start: classes, count: Int(count)) {
            var parent: AnyClass? = class_getSuperclass(cls)
            while let p = parent {
                if ObjectIdentifier(p) == base, let t = cls as? Transformer.Type {
                    found.append(t)
                    break
                }
                parent = class_getSuperclass(p)
            }
        }
        return found
    }
}

func applyTransformers(_ text: String) async -> String? {
    await TransformerRegistry.shared.apply(text)
}
