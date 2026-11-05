import AppKit
import AVFoundation
import UniformTypeIdentifiers

/// The file behind a history entry, if the entry is the full path of an audio file that still exists.
@MainActor
func audioFileURL(_ text: String) -> URL? {
    guard text.hasPrefix("/"), !text.contains("\n") else { return nil }
    let url = URL(fileURLWithPath: text)
    guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentTypeKey]),
          values.isRegularFile == true,
          values.contentType?.conforms(to: .audio) == true else { return nil }
    return url
}

/// All open mini players: at most one per file, and only one playing at a time.
@MainActor
final class AudioPlayers {
    private var players: [String: MiniPlayer] = [:]
    private var nextTopLeft = NSPoint.zero

    var autoplay: Bool {
        get { UserDefaults.standard.bool(forKey: "autoplayAudio") }
        set { UserDefaults.standard.set(newValue, forKey: "autoplayAudio") }
    }

    func open(_ url: URL) {
        let key = url.standardizedFileURL.path
        if let existing = players[key] {
            existing.panel.orderFrontRegardless()
            return
        }
        let player = MiniPlayer(url: url)
        player.onWillPlay = { [weak self] in
            guard let self else { return }
            for (other, otherPlayer) in players where other != key { otherPlayer.pause() }
        }
        player.onClose = { [weak self] in self?.players[key] = nil }
        players[key] = player

        player.panel.center()
        nextTopLeft = player.panel.cascadeTopLeft(from: nextTopLeft)
        player.panel.orderFrontRegardless()  // never activates ClipWise, so focus stays where it was
        if autoplay { player.play() }
    }
}

/// A small floating player, modelled on the Quick Look audio preview.
@MainActor
final class MiniPlayer: NSObject, NSWindowDelegate {
    var onWillPlay: (() -> Void)?
    var onClose: (() -> Void)?
    let panel: NSPanel

    private static let width: CGFloat = 460
    private static let speeds: [Float] = [0.5, 1, 1.25, 1.5, 2]

    private let url: URL
    private let player: AVPlayer
    private var timeObserver: Any?
    private var observations: [NSKeyValueObservation] = []
    private var endObserver: NSObjectProtocol?
    private var duration: Double = 0
    private var scrubbing = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let albumLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private let elapsedLabel = NSTextField(labelWithString: "0:00")
    private let totalLabel = NSTextField(labelWithString: "--:--")
    private let progress = ClickThroughSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let volume = ClickThroughSlider(value: 1, minValue: 0, maxValue: 1, target: nil, action: nil)
    private lazy var playButton = symbolButton("play.fill", "Play", #selector(togglePlay), size: 18)
    private lazy var backButton = symbolButton("gobackward.15", "Back 15 seconds", #selector(skipBack), size: 16)
    private lazy var forwardButton = symbolButton("goforward.15", "Forward 15 seconds", #selector(skipForward), size: 16)
    private lazy var speedButton = symbolButton("speedometer", "Playback speed", #selector(showSpeeds), size: 15)

    init(url: URL) {
        self.url = url
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .pause
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 180),
                        styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        super.init()

        configurePanel()
        observe(item)
        Task { await loadDetails(of: asset) }
    }

    func play() {
        onWillPlay?()
        player.play()
    }

    func pause() {
        player.pause()
    }

    // MARK: Window

    private func configurePanel() {
        panel.title = url.lastPathComponent
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true

        let share = symbolButton("square.and.arrow.up", "Share", #selector(share(_:)), size: 14)
        let accessory = NSTitlebarAccessoryViewController()
        let shareHolder = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
        share.frame = NSRect(x: 4, y: 2, width: 24, height: 24)
        shareHolder.addSubview(share)
        accessory.view = shareHolder
        accessory.layoutAttribute = .right
        panel.addTitlebarAccessoryViewController(accessory)

        let root = NSVisualEffectView()
        root.material = .hudWindow
        root.blendingMode = .behindWindow
        root.state = .active

        titleLabel.stringValue = url.deletingPathExtension().lastPathComponent
        titleLabel.font = .boldSystemFont(ofSize: 15)
        for label in [titleLabel, albumLabel, timeLabel] {
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        titleLabel.toolTip = url.path
        albumLabel.isHidden = true
        timeLabel.isHidden = true

        let info = NSStackView(views: [titleLabel, albumLabel, timeLabel])
        info.orientation = .vertical
        info.alignment = .leading
        info.spacing = 3

        volume.target = self
        volume.action = #selector(volumeChanged)
        volume.controlSize = .small
        volume.toolTip = "Volume"
        volume.setAccessibilityLabel("Volume")
        volume.widthAnchor.constraint(equalToConstant: 90).isActive = true
        let speaker = NSImageView(image: NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: nil) ?? NSImage())
        speaker.contentTintColor = .secondaryLabelColor
        let volumeRow = NSStackView(views: [NSView(), volume, speaker])
        volumeRow.spacing = 6

        progress.target = self
        progress.action = #selector(progressChanged)
        progress.isContinuous = true
        progress.isEnabled = false
        progress.controlSize = .small
        progress.setAccessibilityLabel("Position")
        progress.setContentHuggingPriority(.defaultLow, for: .horizontal)
        progress.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        for label in [elapsedLabel, totalLabel] {
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.setContentHuggingPriority(.required, for: .horizontal)
        }

        let transport = NSStackView(views: [backButton, playButton, forwardButton, elapsedLabel, progress, totalLabel, speedButton])
        transport.spacing = 10
        transport.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let pill = NSBox()
        pill.boxType = .custom
        pill.borderWidth = 0
        pill.cornerRadius = 16
        pill.fillColor = .quaternaryLabelColor
        pill.contentViewMargins = .zero
        pill.contentView = transport
        transport.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            transport.topAnchor.constraint(equalTo: pill.topAnchor),
            transport.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            transport.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            transport.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
        ])

        let stack = NSStackView(views: [volumeRow, info, pill])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: Self.width),
            stack.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 2),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            volumeRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            info.widthAnchor.constraint(equalTo: stack.widthAnchor),
            pill.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        panel.contentView = root
        fitToContent()
    }

    /// Height follows the album and time lines, which appear once the file's details have loaded. The top stays put.
    private func fitToContent() {
        guard let root = panel.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let height = root.fittingSize.height
        var frame = panel.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }

    private func symbolButton(_ symbol: String, _ label: String, _ action: Selector, size: CGFloat) -> NSButton {
        let button = ClickThroughButton(frame: .zero)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        button.symbolConfiguration = .init(pointSize: size, weight: .regular)
        button.target = self
        button.action = action
        button.toolTip = label
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func windowWillClose(_ notification: Notification) {
        player.pause()
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        observations.removeAll()
        player.replaceCurrentItem(with: nil)
        onClose?()
    }

    // MARK: Playback state

    private func observe(_ item: AVPlayerItem) {
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated { self?.showTime(time.seconds) }
        }
        // The icon follows the player, so it stays right when the system pauses playback too.
        observations.append(player.observe(\.timeControlStatus) { [weak self] _, _ in
            Task { @MainActor in self?.showPlayState() }
        })
        observations.append(item.observe(\.status) { [weak self] item, _ in
            guard item.status == .failed else { return }
            let description = item.error?.localizedDescription ?? "unknown error"
            Task { @MainActor in self?.showFailure(description) }
        })
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rewindAfterEnd() }
        }
    }

    private func loadDetails(of asset: AVURLAsset) async {
        do {
            let (metadata, length, playable) = try await asset.load(.commonMetadata, .duration, .isPlayable)
            guard playable else { return showFailure("not playable") }

            if length.isNumeric, length.seconds > 0 {
                duration = length.seconds
                progress.maxValue = duration
                progress.isEnabled = true
                totalLabel.stringValue = Self.format(duration)
                showDetail(timeLabel, "Time", Self.format(duration))
            }
            if let title = await Self.string(.commonIdentifierTitle, in: metadata) {
                titleLabel.stringValue = title
            }
            if let album = await Self.string(.commonIdentifierAlbumName, in: metadata) {
                showDetail(albumLabel, "Album", album)
            }
            fitToContent()
        } catch {
            showFailure(error.localizedDescription)
        }
    }

    private static func string(_ identifier: AVMetadataIdentifier, in metadata: [AVMetadataItem]) async -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let value = try? await item.load(.stringValue),
              !value.isEmpty else { return nil }
        return value
    }

    /// "Album: **name**", as in Quick Look.
    private func showDetail(_ label: NSTextField, _ name: String, _ value: String) {
        let size = NSFont.systemFontSize
        let text = NSMutableAttributedString(string: "\(name): ", attributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.secondaryLabelColor,
        ])
        text.append(NSAttributedString(string: value, attributes: [
            .font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        label.attributedStringValue = text
        label.toolTip = value
        label.isHidden = false
    }

    private func showFailure(_ reason: String) {
        NSLog("ClipWise: could not play \(url.path): \(reason)")
        player.pause()
        titleLabel.stringValue = "Can't play this file"
        for control in [playButton, backButton, forwardButton, speedButton, progress, volume] as [NSControl] {
            control.isEnabled = false
        }
    }

    private func showTime(_ seconds: Double) {
        guard seconds.isFinite, !scrubbing else { return }
        elapsedLabel.stringValue = Self.format(seconds)
        progress.doubleValue = seconds
    }

    private func showPlayState() {
        let playing = player.timeControlStatus != .paused
        let label = playing ? "Pause" : "Play"
        playButton.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill", accessibilityDescription: label)
        playButton.toolTip = label
    }

    private func rewindAfterEnd() {
        player.seek(to: .zero)
        showTime(0)
    }

    private static func format(_ seconds: Double) -> String {
        let total = Int(max(seconds, 0))
        let (h, m, s) = (total / 3600, total / 60 % 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    // MARK: Controls

    @objc private func togglePlay() {
        if player.timeControlStatus == .paused { play() } else { pause() }
    }

    @objc private func skipBack() { skip(by: -15) }
    @objc private func skipForward() { skip(by: 15) }

    private func skip(by seconds: Double) {
        let target = max(player.currentTime().seconds + seconds, 0)
        let clamped = duration > 0 ? min(target, duration) : target
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        showTime(clamped)
    }

    @objc private func progressChanged() {
        let finished = NSApp.currentEvent?.type == .leftMouseUp
        scrubbing = !finished
        elapsedLabel.stringValue = Self.format(progress.doubleValue)
        let time = CMTime(seconds: progress.doubleValue, preferredTimescale: 600)
        if finished {
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        } else {
            player.seek(to: time)
        }
    }

    @objc private func volumeChanged() {
        player.volume = volume.floatValue
    }

    @objc private func showSpeeds() {
        let menu = NSMenu()
        for speed in Self.speeds {
            let item = NSMenuItem(title: speed.formatted() + "×", action: #selector(setSpeed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = speed
            item.state = player.defaultRate == speed ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: speedButton.bounds.height + 4), in: speedButton)
    }

    @objc private func setSpeed(_ sender: NSMenuItem) {
        guard let speed = sender.representedObject as? Float else { return }
        player.defaultRate = speed  // what play() uses from now on
        if player.timeControlStatus != .paused { player.rate = speed }
    }

    @objc private func share(_ sender: NSButton) {
        NSSharingServicePicker(items: [url]).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }
}

// ClipWise is never the active app, so without these the first click on a control would be swallowed.
private final class ClickThroughButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class ClickThroughSlider: NSSlider {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
