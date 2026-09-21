import AppKit

/// Settings window for adjusting shake sensitivity and the interface language, styled to
/// match the shelf itself: a borderless, rounded Liquid Glass card instead of a standard
/// system window. Unlike the shelf panel, this one is a normal (key-able) window — opening
/// it is a deliberate action from the menu, so it's fine for it to take keyboard focus like
/// any preferences window.
final class SettingsWindowController: NSWindowController {

    private let slider = NSSlider(value: ShakeSensitivity.value, minValue: 0, maxValue: 1, target: nil, action: nil)
    private let readoutLabel = NSTextField(labelWithString: "")
    private let closeButton = RoundIconButton(symbol: "xmark", tint: .white)

    private let windowTitleLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let leftEndLabel = NSTextField(labelWithString: "")
    private let rightEndLabel = NSTextField(labelWithString: "")
    private let resetButton = PillButton(title: "")
    private let languageTitleLabel = NSTextField(labelWithString: "")
    private let languagePopUp = NSPopUpButton(frame: .zero, pullsDown: false)

    private let storageTitleLabel = NSTextField(labelWithString: "")
    private let storageSubtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let storageSlider = NSSlider(
        value: Double(ArchiveRetentionSettings.days),
        minValue: Double(ArchiveRetentionSettings.minValue),
        maxValue: Double(ArchiveRetentionSettings.maxValue),
        target: nil, action: nil
    )
    private let storageReadoutLabel = NSTextField(labelWithString: "")
    private let clearArchiveButton = PillButton(title: "")

    private let shelfSizeTitleLabel = NSTextField(labelWithString: "")
    private let shelfSizeSubtitleLabel = NSTextField(wrappingLabelWithString: "")
    private let shelfSizeControl = NSSegmentedControl(labels: ["", ""], trackingMode: .selectOne, target: nil, action: nil)

    /// Index 0 is always "System" (nil override); the rest mirror `AppLanguage.allCases`.
    private let languageOptions: [AppLanguage?] = [nil] + AppLanguage.allCases

    convenience init() {
        let window = KeyableBorderlessWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            // No .resizable — there's no visible edge to drag anyway (borderless, no
            // title bar), and per ShelfPanel it's also what let macOS's window-tiling
            // gesture and a stray key-window highlight rectangle apply to a window in the
            // first place; removing it doesn't affect our own animated setFrame calls,
            // which aren't gated by this style mask bit.
            styleMask: [.borderless],
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
        refreshLocalizedText()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshLocalizedText),
            name: LocalizationManager.languageDidChangeNotification, object: nil
        )
    }

    private func buildUI() {
        guard let window else { return }
        let initialBounds = window.contentView?.bounds ?? .zero

        let chromeContent = NSView()
        let glassPanel = GlassChrome.panel(cornerRadius: 22, content: chromeContent)
        // Autoresizing, not Auto Layout — see GlassChrome.pin for why.
        glassPanel.translatesAutoresizingMaskIntoConstraints = true
        glassPanel.autoresizingMask = [.width, .height]
        // 2pt smaller than the window's own bounds on every side, instead of filling them
        // exactly — this is what actually fixes the corner-outline bug (three earlier
        // attempts, none of which touched this: focus ring, contentView identity, styleMask
        // .resizable). The artifact is the WindowServer's own key-window highlight, drawn
        // along the window's literal rectangular edge regardless of view/layer shape; with
        // zero margin that edge coincided exactly with our rounded glass's own outer
        // corners, so it showed through right where the corner mask had clipped the glass
        // away. A 2pt transparent gap puts that edge safely outside the visible card. A
        // plain `backdrop` view (not the glass panel itself) is the window's contentView so
        // there's an actually-transparent area for that gap to sit in.
        glassPanel.frame = initialBounds.insetBy(dx: 2, dy: 2)
        let backdrop = NSView(frame: initialBounds)
        backdrop.autoresizingMask = [.width, .height]
        backdrop.addSubview(glassPanel)
        window.contentView = backdrop

        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        let closeGlass = GlassChrome.control(cornerRadius: 14, content: closeButton)
        closeGlass.translatesAutoresizingMaskIntoConstraints = false
        chromeContent.addSubview(closeGlass)

        // Sits in the same row as the close button (vertically centered on it) instead of
        // its own line below — that used to leave an odd empty strip next to "×".
        windowTitleLabel.font = .boldSystemFont(ofSize: 15)
        windowTitleLabel.textColor = .white
        windowTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        chromeContent.addSubview(windowTitleLabel)

        // Now a section header, not the window's own title (see windowTitleLabel above) —
        // this window covers more than just sensitivity, so it needed an overall title;
        // this label was demoted to match languageTitleLabel's section-header styling.
        titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .white.withAlphaComponent(0.65)

        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .white.withAlphaComponent(0.65)
        subtitleLabel.alignment = .center

        leftEndLabel.font = .systemFont(ofSize: 11)
        leftEndLabel.textColor = .white.withAlphaComponent(0.5)

        rightEndLabel.font = .systemFont(ofSize: 11)
        rightEndLabel.textColor = .white.withAlphaComponent(0.5)
        rightEndLabel.alignment = .right

        slider.target = self
        slider.action = #selector(sliderChanged)
        slider.isContinuous = true

        readoutLabel.font = .boldSystemFont(ofSize: 12)
        readoutLabel.textColor = .white
        readoutLabel.alignment = .center

        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        let resetGlass = GlassChrome.control(cornerRadius: 13, content: resetButton)
        resetGlass.translatesAutoresizingMaskIntoConstraints = false

        let endpointsRow = NSStackView(views: [leftEndLabel, rightEndLabel])
        endpointsRow.orientation = .horizontal
        endpointsRow.distribution = .fillEqually

        languageTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        languageTitleLabel.textColor = .white.withAlphaComponent(0.65)

        // A native control forced into dark appearance so its text stays legible against
        // our permanently-dark glass card, regardless of the system's own light/dark mode.
        languagePopUp.appearance = NSAppearance(named: .darkAqua)
        languagePopUp.target = self
        languagePopUp.action = #selector(languageChanged)

        let divider = NSBox()
        divider.boxType = .separator

        storageTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        storageTitleLabel.textColor = .white.withAlphaComponent(0.65)

        storageSubtitleLabel.font = .systemFont(ofSize: 12)
        storageSubtitleLabel.textColor = .white.withAlphaComponent(0.65)
        storageSubtitleLabel.alignment = .center

        storageSlider.target = self
        storageSlider.action = #selector(storageSliderChanged)
        storageSlider.isContinuous = true
        storageSlider.numberOfTickMarks = ArchiveRetentionSettings.maxValue - ArchiveRetentionSettings.minValue + 1
        storageSlider.allowsTickMarkValuesOnly = true

        storageReadoutLabel.font = .boldSystemFont(ofSize: 12)
        storageReadoutLabel.textColor = .white
        storageReadoutLabel.alignment = .center

        clearArchiveButton.target = self
        clearArchiveButton.action = #selector(clearArchiveTapped)
        let clearArchiveGlass = GlassChrome.control(cornerRadius: 13, content: clearArchiveButton)
        clearArchiveGlass.translatesAutoresizingMaskIntoConstraints = false

        let divider2 = NSBox()
        divider2.boxType = .separator

        shelfSizeTitleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        shelfSizeTitleLabel.textColor = .white.withAlphaComponent(0.65)

        shelfSizeSubtitleLabel.font = .systemFont(ofSize: 12)
        shelfSizeSubtitleLabel.textColor = .white.withAlphaComponent(0.65)
        shelfSizeSubtitleLabel.alignment = .center

        // Forced dark, like languagePopUp — a native control's default appearance would
        // otherwise follow the system's own light/dark mode instead of this permanently
        // dark glass card, leaving its text unreadable in Light Mode.
        shelfSizeControl.appearance = NSAppearance(named: .darkAqua)
        shelfSizeControl.target = self
        shelfSizeControl.action = #selector(shelfSizeChanged)

        let divider3 = NSBox()
        divider3.boxType = .separator

        let stack = NSStackView(views: [
            titleLabel, subtitleLabel, slider, endpointsRow, readoutLabel, resetGlass,
            divider, languageTitleLabel, languagePopUp,
            divider2, storageTitleLabel, storageSubtitleLabel, storageSlider, storageReadoutLabel, clearArchiveGlass,
            divider3, shelfSizeTitleLabel, shelfSizeSubtitleLabel, shelfSizeControl,
        ])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.setCustomSpacing(4, after: titleLabel)
        stack.setCustomSpacing(16, after: subtitleLabel)
        stack.setCustomSpacing(4, after: slider)
        stack.setCustomSpacing(18, after: resetGlass)
        stack.setCustomSpacing(6, after: divider)
        stack.setCustomSpacing(6, after: languageTitleLabel)
        stack.setCustomSpacing(18, after: languagePopUp)
        stack.setCustomSpacing(6, after: divider2)
        stack.setCustomSpacing(16, after: storageSubtitleLabel)
        stack.setCustomSpacing(4, after: storageSlider)
        stack.setCustomSpacing(18, after: clearArchiveGlass)
        stack.setCustomSpacing(6, after: divider3)
        stack.setCustomSpacing(16, after: shelfSizeSubtitleLabel)

        chromeContent.addSubview(stack)
        NSLayoutConstraint.activate([
            closeGlass.topAnchor.constraint(equalTo: chromeContent.topAnchor, constant: 14),
            closeGlass.leadingAnchor.constraint(equalTo: chromeContent.leadingAnchor, constant: 14),
            closeGlass.widthAnchor.constraint(equalToConstant: 28),
            closeGlass.heightAnchor.constraint(equalToConstant: 28),

            windowTitleLabel.centerYAnchor.constraint(equalTo: closeGlass.centerYAnchor),
            windowTitleLabel.centerXAnchor.constraint(equalTo: chromeContent.centerXAnchor),

            stack.topAnchor.constraint(equalTo: closeGlass.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: chromeContent.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: chromeContent.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: chromeContent.bottomAnchor),
            subtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            slider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            endpointsRow.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            divider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            languagePopUp.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            divider2.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            storageSubtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            storageSlider.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            divider3.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
            shelfSizeSubtitleLabel.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48),
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

    @objc private func languageChanged() {
        LocalizationManager.shared.userOverride = languageOptions[languagePopUp.indexOfSelectedItem]
    }

    @objc private func storageSliderChanged() {
        ArchiveRetentionSettings.days = Int(storageSlider.doubleValue.rounded())
        updateStorageReadout()
    }

    @objc private func shelfSizeChanged() {
        ShelfSizePreference.value = shelfSizeControl.selectedSegment == 0 ? .standard : .compact
    }

    @objc private func clearArchiveTapped() {
        let alert = NSAlert()
        alert.messageText = L("archive.clear_confirm_title")
        alert.informativeText = L("archive.clear_confirm_message")
        alert.addButton(withTitle: L("archive.clear_confirm_button"))
        alert.addButton(withTitle: L("archive.cancel_button"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ArchiveStorage.clearAll()
    }

    private func updateReadout() {
        readoutLabel.stringValue = String(format: L("settings.readout"), Int(ShakeSensitivity.value * 100))
    }

    private func updateStorageReadout() {
        storageReadoutLabel.stringValue = LocalizationManager.shared.retentionDaysLabel(ArchiveRetentionSettings.days)
    }

    /// Re-applies every piece of text in the window — called on first build and whenever
    /// the language changes (including from this very window's own picker), so it updates
    /// live without needing to be reopened.
    @objc private func refreshLocalizedText() {
        windowTitleLabel.stringValue = L("settings.window_title")
        titleLabel.stringValue = L("settings.title")
        subtitleLabel.stringValue = L("settings.subtitle")
        leftEndLabel.stringValue = L("settings.weak_end")
        rightEndLabel.stringValue = L("settings.strong_end")
        resetButton.setTitle(L("settings.reset"))
        languageTitleLabel.stringValue = L("settings.language_title")
        updateReadout()

        storageTitleLabel.stringValue = L("settings.storage_title")
        storageSubtitleLabel.stringValue = L("settings.storage_subtitle")
        clearArchiveButton.setTitle(L("settings.storage_clear_now"))
        updateStorageReadout()

        shelfSizeTitleLabel.stringValue = L("settings.shelf_size_title")
        shelfSizeSubtitleLabel.stringValue = L("settings.shelf_size_subtitle")
        shelfSizeControl.setLabel(L("settings.shelf_size_standard"), forSegment: 0)
        shelfSizeControl.setLabel(L("settings.shelf_size_compact"), forSegment: 1)
        shelfSizeControl.selectedSegment = ShelfSizePreference.value == .standard ? 0 : 1

        languagePopUp.removeAllItems()
        let systemLabel = "\(L("settings.language_system")) (\(LocalizationManager.shared.currentLanguage.nativeName))"
        languagePopUp.addItem(withTitle: systemLabel)
        for language in AppLanguage.allCases {
            languagePopUp.addItem(withTitle: language.nativeName)
        }
        let selectedIndex = languageOptions.firstIndex { $0 == LocalizationManager.shared.userOverride } ?? 0
        languagePopUp.selectItem(at: selectedIndex)
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
