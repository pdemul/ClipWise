import AppKit
import Carbon.HIToolbox

struct HotKeyCombo: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags
    var key: String  // what to show for the key, captured when it was recorded

    static let `default` = HotKeyCombo(keyCode: UInt32(kVK_ANSI_V), modifiers: [.control, .option], key: "V")

    var label: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + key
    }

    var carbonModifiers: UInt32 {
        var m = 0
        if modifiers.contains(.command) { m |= cmdKey }
        if modifiers.contains(.option) { m |= optionKey }
        if modifiers.contains(.control) { m |= controlKey }
        if modifiers.contains(.shift) { m |= shiftKey }
        return UInt32(m)
    }

    static func load() -> HotKeyCombo {
        let d = UserDefaults.standard
        guard d.object(forKey: "hotKeyCode") != nil, let key = d.string(forKey: "hotKeyKey") else { return .default }
        return HotKeyCombo(keyCode: UInt32(d.integer(forKey: "hotKeyCode")),
                           modifiers: NSEvent.ModifierFlags(rawValue: UInt(d.integer(forKey: "hotKeyModifiers"))),
                           key: key)
    }

    func save() {
        let d = UserDefaults.standard
        d.set(Int(keyCode), forKey: "hotKeyCode")
        d.set(Int(modifiers.rawValue), forKey: "hotKeyModifiers")
        d.set(key, forKey: "hotKeyKey")
    }
}

/// A system-wide hotkey via Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    private(set) var combo = HotKeyCombo.load()
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            let me = Unmanaged<GlobalHotKey>.fromOpaque(userData!).takeUnretainedValue()
            MainActor.assumeIsolated { me.action() }  // Carbon delivers on the main thread
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr { NSLog("ClipWise: could not install hotkey handler (\(status))") }
    }

    @discardableResult
    func register() -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: 1)  // 'CLIP'
        let status = RegisterEventHotKey(combo.keyCode, combo.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("ClipWise: could not register hotkey \(combo.label) (\(status))")
            ref = nil
            return false
        }
        NSLog("ClipWise: hotkey \(combo.label) registered")
        return true
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    /// Switch to a new combo. On failure the old one stays active and false is returned.
    func set(_ new: HotKeyCombo) -> Bool {
        let old = combo
        combo = new
        if register() {
            new.save()
            return true
        }
        combo = old
        register()
        return false
    }
}
