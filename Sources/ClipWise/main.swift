import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // menubar only, no Dock icon

    let history = History()
    let monitor = ClipboardMonitor { history.add($0) }
    let menu = StatusMenu(history: history, monitor: monitor)
    let hotKey = GlobalHotKey { menu.open() }
    let settings = SettingsWindow(hotKey: hotKey, history: history)
    menu.onSettings = { settings.show() }
    _ = TransformerRegistry.shared  // discover and log transformers at launch
    monitor.start()
    hotKey.register()
    if CommandLine.arguments.contains("--settings") { settings.show() }

    withExtendedLifetime((menu, hotKey, settings)) { app.run() }
}
