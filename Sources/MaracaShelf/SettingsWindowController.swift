import AppKit

/// Settings window for adjusting shake sensitivity, styled to match the shelf itself: a
/// borderless, rounded Liquid Glass card instead of a standard system window. Unlike the
/// shelf panel, this one is a normal (key-able) window — opening it is a deliberate action
/// from the menu, so it's fine for it to take keyboard focus like any preferences window.
final class SettingsWindowController: NSWindowController {

    private let slider = NSSlider(value: ShakeSensitivity.value, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let readoutLabel = NSTextField(labelWithString: "")
    private let closeButton = RoundIconButton(symbol: "xmark", tint: .white)

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()
        self.init(window: window)
        buildUI()
        updateReadout()
    }

    private func buildUI() {
        guard let root = window?.contentView else { return }

        let chromeContent = NSView()
        let glassPanel = GlassChrome.panel(cornerRadius: 22, content: chromeContent)
        // Autoresizing, not Auto Layout — see GlassChrome.pin for why.
        glassPanel.translatesAutoresizingMaskIntoConstraints = true
        glassPanel.autoresizingMask = [.width, .height]
        glassPanel.frame = root.bounds
        root.addSubview(glassPanel)

        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        let closeGlass = GlassChrome.control(cornerRadius: 14, content: closeButton)
        closeGlass.translatesAutoresizingMaskIntoConstraints = false
        chromeContent.addSubview(closeGlass)

        let title = NSTextField(labelWithString: "Чувствительность тряски")
        title.font = .boldSystemFont(ofSize: 14)
        title.textColor = .white

        let subtitle = NSTextField(wrappingLabelWithString: "Насколько сильно нужно трясти файл, чтобы открылась полка")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .white.withAlphaComponent(0.65)
        subtitle.alignment = .center

        let leftLabel = NSTextField(labelWithString: "Нужна сильная тряска")
        leftLabel.font = .systemFont(ofSize: 11)
        leftLabel.textColor = .white.withAlphaComponent(0.5)

        let rightLabel = NSTextField(labelWithString: "Достаточно лёгкой тряски")
        rightLabel.font = .systemFont(ofSize: 11)
        rightLabel.textColor = .white.withAlphaComponent(0.5)
        rightLabel.alignment = .right

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true

        readoutLabel.font = .boldSystemFont(ofSize: 12)
        readoutLabel.textColor = .white
        readoutLabel.alignment = .center

        let resetButton = PillButton(title: "Сбросить")
        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        let resetGlass = GlassChrome.control(cornerRadius: 13, content: resetButton)
        resetGlass.translatesAutoresizingMaskIntoConstraints = false

        let endpointsRow = NSStackView(views: [leftLabel, rightLabel])
        endpointsRow.orientation = .horizontal
        endpointsRow.distribution = .fillEqually

        let stack = NSStackView(views: [title, subtitle, slider, endpointsRow, readoutLabel, resetGlass])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(4, after: title)
        stack.setCustomSpacing(16, after: subtitle)
        stack.setCustomSpacing(4, after: slider)

        chromeContent.addSubview(stack)
        NSLayoutConstraint.activate([
            closeGlass.topAnchor.constraint(equalTo: chromeContent.topAnchor, constant: 14),
            closeGlass.leadingAnchor.constraint(equalTo: chromeContent.leadingAnchor, constant: 14),
            closeGlass.widthAnchor.constraint(equalToConstant: 28),
            closeGlass.heightAnchor.constraint(equalToConstant: 28),

            stack.topAnchor.constraint(equalTo: closeGlass.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: chromeContent.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: chromeContent.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: chromeContent.bottomAnchor),
            subtitle.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            slider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            endpointsRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
        ])
    }

    @objc private func sliderChanged() {
        ShakeSensitivity.value = slider.doubleValue
        updateReadout()
    }

    @objc private func resetTapped() {
        ShakeSensitivity.value = ShakeSensitivity.defaultValue
        slider.doubleValue = ShakeSensitivity.value
        updateReadout()
    }

    @objc private func closeTapped() {
        window?.orderOut(nil)
    }

    private func updateReadout() {
        readoutLabel.stringValue = "Чувствительность: \(Int(ShakeSensitivity.value * 100))%"
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
