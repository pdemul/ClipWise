import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)  // menubar only, no Dock icon

    let history = History()
    let players = AudioPlayers()
    let monitor = ClipboardMonitor { text in
        history.add(text)
        if players.autoplay, let audio = audioFileURL(text) { players.open(audio) }
    }
    let menu = StatusMenu(history: history, monitor: monitor, players: players)
    let hotKey = GlobalHotKey { menu.open() }
    let settings = SettingsWindow(hotKey: hotKey, history: history)
    menu.onSettings = { settings.show() }
    _ = TransformerRegistry.shared  // discover and log transformers at launch
    monitor.start()
    hotKey.register()
    if CommandLine.arguments.contains("--settings") { settings.show() }

    withExtendedLifetime((menu, hotKey, settings, players)) { app.run() }
}
