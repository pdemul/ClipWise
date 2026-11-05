import AppKit

@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()
    private let history: History
    private let monitor: ClipboardMonitor
    private let players: AudioPlayers
    var onSettings: (() -> Void)?

    init(history: History, monitor: ClipboardMonitor, players: AudioPlayers) {
        self.history = history
        self.monitor = monitor
        self.players = players
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
            let audio = audioFileURL(entry.original)
            let title = audio.map { Self.label($0.lastPathComponent) } ?? Self.label(entry.original)
            let item = NSMenuItem(title: title, action: #selector(pick(_:)), keyEquivalent: key)
            if audio != nil { item.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "Audio file") }
            item.target = self
            item.tag = i
            item.toolTip = entry.original
            menu.addItem(item)
        }

        menu.addItem(.separator())
        let autoplay = NSMenuItem()
        autoplay.view = SwitchMenuRow(title: "Autoplay audio files", isOn: players.autoplay, target: self, action: #selector(autoplayToggled(_:)))
        menu.addItem(autoplay)
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
        menu.addItem(NSMenuItem(title: "Quit ClipWise", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func pick(_ sender: NSMenuItem) {
        guard history.entries.indices.contains(sender.tag) else { return }
        let text = history.entries[sender.tag].original
        monitor.write(text)
        history.add(text)
        if let audio = audioFileURL(text) { players.open(audio) }
    }

    @objc private func autoplayToggled(_ sender: NSSwitch) {
        players.autoplay = sender.state == .on
        NSLog("ClipWise: autoplay audio \(players.autoplay ? "on" : "off")")
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
        // Keep both ends of a path: the file name is at the end.
        if text.hasPrefix("/"), !text.contains("\n"), text.count > 60 {
            return String(text.prefix(29)) + "…" + String(text.suffix(30))
        }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.count > 60 ? String(collapsed.prefix(59)) + "…" : collapsed
    }
}

/// A menu row with a label and a real switch. Flipping it leaves the menu open.
private final class SwitchMenuRow: NSView {
    init(title: String, isOn: Bool, target: AnyObject, action: Selector) {
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 26))
        autoresizingMask = [.width]

        let label = NSTextField(labelWithString: title)
        label.font = .menuFont(ofSize: 0)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: 14, y: (bounds.height - label.frame.height) / 2)
        label.autoresizingMask = [.maxXMargin]
        addSubview(label)

        let toggle = NSSwitch()
        toggle.controlSize = .mini
        toggle.state = isOn ? .on : .off
        toggle.target = target
        toggle.action = action
        toggle.setAccessibilityLabel(title)
        toggle.sizeToFit()
        toggle.frame.origin = NSPoint(x: bounds.width - toggle.frame.width - 14, y: (bounds.height - toggle.frame.height) / 2)
        toggle.autoresizingMask = [.minXMargin]
        addSubview(toggle)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
