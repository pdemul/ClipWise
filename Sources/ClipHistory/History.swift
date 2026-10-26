import Foundation

struct ClipEntry: Codable, Equatable {
    var original: String
    var result: String?

    /// What gets shown and copied back: the transform result if there is one.
    var value: String { result ?? original }
}

@MainActor
final class History {
    private(set) var entries: [ClipEntry] = []
    private let fileURL: URL

    var maxItems: Int {
        let n = UserDefaults.standard.integer(forKey: "maxItems")
        return n > 0 ? n : 20
    }

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("history.json")
        load()
    }

    func add(_ text: String) {
        // Trim surrounding whitespace so "foo" and "foo\n" are one entry,
        // and a re-copy never brings back a stray trailing newline.
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        entries.removeAll { $0.original == text }
        entries.insert(ClipEntry(original: text, result: applyTransformers(text)), at: 0)
        if entries.count > maxItems { entries.removeLast(entries.count - maxItems) }
        save()
    }

    /// Lowering the limit drops the oldest entries straight away.
    func setMaxItems(_ n: Int) {
        UserDefaults.standard.set(n, forKey: "maxItems")
        if entries.count > n {
            entries.removeLast(entries.count - n)
            save()
        }
    }

    func clear() {
        entries.removeAll()
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            // Trim and de-duplicate here too, so history saved before trimming existed is cleaned up.
            var seen = Set<String>()
            for var entry in try JSONDecoder().decode([ClipEntry].self, from: data) {
                entry.original = entry.original.trimmingCharacters(in: .whitespacesAndNewlines)
                entry.result = applyTransformers(entry.original)  // pick up transforms added since it was saved
                guard !entry.original.isEmpty, seen.insert(entry.original).inserted else { continue }
                entries.append(entry)
            }
            entries = Array(entries.prefix(maxItems))
        } catch {
            NSLog("ClipHistory: could not read \(fileURL.path), starting empty: \(error)")
        }
    }

    private func save() {
        do {
            try JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("ClipHistory: could not save history: \(error)")
        }
    }
}
