import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let history: History
    private let monitor: ClipboardMonitor
    var onSettings: (() -> Void)?

    init(history: History, monitor: ClipboardMonitor) {
        self.history = history
        self.monitor = monitor
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard history")
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if history.entries.isEmpty {
            let empty = NSMenuItem(title: "Nothing copied yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }

        for (i, entry) in history.entries.enumerated() {
            let key = i < 9 ? String(i + 1) : ""
            let item = NSMenuItem(title: Self.label(entry.original), action: #selector(pick(_:)), keyEquivalent: key)
            item.target = self
            item.tag = i
            item.toolTip = entry.original
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let clear = NSMenuItem(title: "Clear History", action: #selector(clear), keyEquivalent: "")
        clear.target = self
        if history.entries.isEmpty {
            clear.isEnabled = false
            clear.toolTip = "History is already empty"
        }
        menu.addItem(clear)
        menu.addItem(NSMenuItem(title: "Quit ClipHistory", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard history.entries.indices.contains(sender.tag) else { return }
        let text = history.entries[sender.tag].original
        monitor.write(text)
        history.add(text)
    }

    @objc private func clear() {
        history.clear()
    }

    @objc private func openSettings() {
        onSettings?()
    }

    /// Drop the menu down from the menubar icon, as if it had been clicked.
    func open() {
        statusItem.button?.performClick(nil)
    }

    /// First line, whitespace collapsed, truncated.
    private static func label(_ text: String) -> String {
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 60 ? String(collapsed.prefix(59)) + "…" : collapsed
    }
}
