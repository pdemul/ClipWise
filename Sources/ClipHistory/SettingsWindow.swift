import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let hotKey: GlobalHotKey
    private let history: History
    private var window: NSWindow?
    private let sizeField = NSTextField()
    private let sizeStepper = NSStepper()
    private static let sizeRange = 5...200
    private let loginCheckbox = NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil)
    private let loginHint = NSTextField(wrappingLabelWithString: "")
    private let loginItemsButton = NSButton(title: "Open Login Items", target: nil, action: nil)
    private let shortcutButton = NSButton(title: "", target: nil, action: nil)
    private let resetButton = NSButton(title: "Reset to \(HotKeyCombo.default.label)", target: nil, action: nil)
    private let hint = NSTextField(wrappingLabelWithString: "")
    private var keyMonitor: Any?

    private static let defaultHint = "Click the shortcut, then press the new one. It opens the history from any app; then ⌘1–⌘9 picks an entry."

    init(hotKey: GlobalHotKey, history: History) {
        self.hotKey = hotKey
        self.history = history
        super.init()
    }

    func show() {
        if window == nil { window = makeWindow() }
        hint.stringValue = Self.defaultHint
        loginHint.stringValue = ""
        refresh()
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "ClipHistory Settings"
        w.isReleasedWhenClosed = false
        w.delegate = self

        shortcutButton.target = self
        shortcutButton.action = #selector(startRecording)
        shortcutButton.bezelStyle = .rounded
        shortcutButton.widthAnchor.constraint(equalToConstant: 140).isActive = true
        resetButton.target = self
        resetButton.action = #selector(reset)
        hint.textColor = .secondaryLabelColor
        hint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        hint.preferredMaxLayoutWidth = 360

        let formatter = NumberFormatter()
        formatter.minimum = NSNumber(value: Self.sizeRange.lowerBound)
        formatter.maximum = NSNumber(value: Self.sizeRange.upperBound)
        formatter.allowsFloats = false
        sizeField.formatter = formatter
        sizeField.alignment = .right
        sizeField.widthAnchor.constraint(equalToConstant: 50).isActive = true
        sizeField.target = self
        sizeField.action = #selector(sizeChanged(_:))
        sizeStepper.minValue = Double(Self.sizeRange.lowerBound)
        sizeStepper.maxValue = Double(Self.sizeRange.upperBound)
        sizeStepper.target = self
        sizeStepper.action = #selector(sizeChanged(_:))
        sizeStepper.toolTip = "Lowering this removes the oldest entries straight away"

        let row = NSStackView(views: [NSTextField(labelWithString: "Open clipboard history:"), shortcutButton])
        row.spacing = 8
        let sizeRow = NSStackView(views: [NSTextField(labelWithString: "Keep the last"), sizeField, sizeStepper,
                                          NSTextField(labelWithString: "copies")])
        sizeRow.spacing = 6
        loginCheckbox.target = self
        loginCheckbox.action = #selector(loginToggled)
        loginItemsButton.target = self
        loginItemsButton.action = #selector(openLoginItems)
        loginHint.textColor = .secondaryLabelColor
        loginHint.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        loginHint.preferredMaxLayoutWidth = 360

        let stack = NSStackView(views: [row, hint, resetButton, Self.separator(), sizeRow, Self.separator(),
                                        loginCheckbox, loginHint, loginItemsButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        w.contentView = stack
        w.center()
        return w
    }

    private static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.widthAnchor.constraint(equalToConstant: 360).isActive = true
        return box
    }

    @objc private func loginToggled() {
        let service = SMAppService.mainApp
        do {
            if loginCheckbox.state == .on {
                try service.register()
            } else {
                try service.unregister()
            }
            loginHint.stringValue = ""
            NSLog("ClipHistory: open at login \(loginCheckbox.state == .on ? "enabled" : "disabled"), status \(service.status.rawValue)")
        } catch {
            loginHint.stringValue = "Couldn't change this: \(error.localizedDescription)"
            NSLog("ClipHistory: open-at-login change failed: \(error)")
        }
        refresh()
    }

    @objc private func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    @objc private func sizeChanged(_ sender: NSControl) {
        let n = min(max(sender.integerValue, Self.sizeRange.lowerBound), Self.sizeRange.upperBound)
        history.setMaxItems(n)
        refresh()
    }

    private func refresh() {
        sizeField.integerValue = history.maxItems
        sizeStepper.integerValue = history.maxItems

        // Read from the system every time, so it matches System Settings → Login Items.
        let status = SMAppService.mainApp.status
        loginCheckbox.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        let needsApproval = status == .requiresApproval
        loginItemsButton.isHidden = !needsApproval
        if needsApproval {
            loginHint.stringValue = "Approve ClipHistory in System Settings → General → Login Items."
        }
        loginHint.isHidden = loginHint.stringValue.isEmpty
        let recording = keyMonitor != nil
        shortcutButton.title = recording ? "Type shortcut…" : hotKey.combo.label
        let isDefault = hotKey.combo == .default
        resetButton.isEnabled = !isDefault && !recording
        resetButton.toolTip = isDefault ? "Already using the default shortcut"
            : recording ? "Finish or cancel recording first" : nil
    }

    @objc private func startRecording() {
        guard keyMonitor == nil else { return }
        hotKey.unregister()  // otherwise pressing the current shortcut never reaches this window
        hint.stringValue = "Press the new shortcut, or Esc to cancel."
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return nil
        }
        refresh()
    }

    private func handle(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if Int(event.keyCode) == kVK_Escape && mods.isEmpty {
            stopRecording()
            hint.stringValue = Self.defaultHint
            return
        }
        guard !mods.isDisjoint(with: [.command, .option, .control]) else {
            NSSound.beep()
            hint.stringValue = "Include ⌘, ⌃ or ⌥, so the shortcut doesn't fire while you type. Esc cancels."
            return
        }
        let combo = HotKeyCombo(keyCode: UInt32(event.keyCode), modifiers: mods, key: Self.keyName(event))
        stopRecording(applying: combo)
    }

    private func stopRecording(applying combo: HotKeyCombo? = nil) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        if let combo {
            hint.stringValue = hotKey.set(combo) ? Self.defaultHint
                : "\(combo.label) is already in use by macOS or another app. Kept \(hotKey.combo.label)."
        } else {
            hotKey.register()
        }
        refresh()
    }

    @objc private func reset() {
        hint.stringValue = hotKey.set(.default) ? Self.defaultHint
            : "\(HotKeyCombo.default.label) is already in use by another app."
        refresh()
    }

    func windowWillClose(_ notification: Notification) {
        if keyMonitor != nil { stopRecording() }
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(_ event: NSEvent) -> String {
        if let name = specialKeys[Int(event.keyCode)] { return name }
        return event.charactersIgnoringModifiers?.uppercased() ?? "?"
    }
}
