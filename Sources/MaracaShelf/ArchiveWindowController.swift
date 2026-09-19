import AppKit

/// Shows every file kept in `ArchiveStorage`'s persistent folder — opened from the status
/// bar's "Show Archive…" item, independent of any shake-triggered shelf. Styled like the
/// shelf itself (a Liquid Glass card) but as a normal, key-able window, since opening it is a
/// deliberate action from the menu rather than something that must avoid stealing focus.
final class ArchiveWindowController: NSWindowController {

    private var entries: [ShelfItem] = []

    private let closeButton = RoundIconButton(symbol: "xmark", tint: .white)
    private let windowTitleLabel = NSTextField(labelWithString: "")
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private let clearButton = PillButton(title: "")
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 270, height: 420),
            styleMask: [.borderless, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 260, height: 300)
        // Floats above ordinary windows and follows the active Space — same level
        // ShelfPanel uses (not a higher one: .screenSaver was tried there and found to
        // break drag & drop hit-testing, since very high levels are excluded from it).
        // Unlike ShelfPanel this stays in Mission Control/App Exposé and the window
        // cycle, since it's a real window the user deliberately keeps open, not a
        // transient overlay.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
        guard let root = window?.contentView else { return }

        let chromeContent = NSView()
        let glassPanel = GlassChrome.panel(cornerRadius: 22, content: chromeContent)
        // Autoresizing, not Auto Layout — see GlassChrome.pinTrackingAnimatedResize; this
        // window is resizable, so the glass needs to track its frame the same way the
        // shelf's does during its collapse/expand animation.
        glassPanel.translatesAutoresizingMaskIntoConstraints = true
        glassPanel.autoresizingMask = [.width, .height]
        glassPanel.frame = root.bounds
        root.addSubview(glassPanel)

        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        let closeGlass = GlassChrome.control(cornerRadius: 14, content: closeButton)
        closeGlass.translatesAutoresizingMaskIntoConstraints = false
        chromeContent.addSubview(closeGlass)

        windowTitleLabel.font = .boldSystemFont(ofSize: 15)
        windowTitleLabel.textColor = .white
        windowTitleLabel.translatesAutoresizingMaskIntoConstraints = false
        chromeContent.addSubview(windowTitleLabel)

        clearButton.target = self
        clearButton.action = #selector(clearTapped)
        let clearGlass = GlassChrome.control(cornerRadius: 13, content: clearButton)
        clearGlass.translatesAutoresizingMaskIntoConstraints = false
        chromeContent.addSubview(clearGlass)

        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 74, height: 84)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView = NSCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FileThumbnailItem.self, forItemWithIdentifier: .archiveThumbnail)
        collectionView.setDraggingSourceOperationMask([.copy], forLocal: false)

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        chromeContent.addSubview(scrollView)

        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.textColor = .white.withAlphaComponent(0.55)
        emptyLabel.font = .systemFont(ofSize: 12)
        emptyLabel.alignment = .center
        chromeContent.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            closeGlass.topAnchor.constraint(equalTo: chromeContent.topAnchor, constant: 14),
            closeGlass.leadingAnchor.constraint(equalTo: chromeContent.leadingAnchor, constant: 14),
            closeGlass.widthAnchor.constraint(equalToConstant: 28),
            closeGlass.heightAnchor.constraint(equalToConstant: 28),

            windowTitleLabel.centerYAnchor.constraint(equalTo: closeGlass.centerYAnchor),
            windowTitleLabel.centerXAnchor.constraint(equalTo: chromeContent.centerXAnchor),

            // "Clear Archive" lives at the bottom (like the shelf's own count pill), not in
            // the header — a variable-width pill sharing the header row with a *centered*
            // title collided with it in longer languages (e.g. Russian "Очистить архив" ran
            // into "Архив"). Bottom placement has no such width contention regardless of
            // translation length.
            clearGlass.bottomAnchor.constraint(equalTo: chromeContent.bottomAnchor, constant: -14),
            clearGlass.centerXAnchor.constraint(equalTo: chromeContent.centerXAnchor),
            clearGlass.heightAnchor.constraint(equalToConstant: 26),

            scrollView.topAnchor.constraint(equalTo: closeGlass.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: chromeContent.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: chromeContent.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: clearGlass.topAnchor, constant: -10),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            emptyLabel.widthAnchor.constraint(equalToConstant: 200),
        ])
    }

    @objc private func closeTapped() {
        window?.orderOut(nil)
    }

    @objc private func clearTapped() {
        guard !entries.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = L("archive.clear_confirm_title")
        alert.informativeText = L("archive.clear_confirm_message")
        alert.addButton(withTitle: L("archive.clear_confirm_button"))
        alert.addButton(withTitle: L("archive.cancel_button"))
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        ArchiveStorage.clearAll()
        reload()
    }

    @objc private func refreshLocalizedText() {
        windowTitleLabel.stringValue = L("archive.window_title")
        clearButton.setTitle(L("archive.clear_now"))
        emptyLabel.stringValue = L("archive.empty")
    }

    private func reload() {
        ArchiveStorage.purgeExpired()
        entries = ArchiveStorage.loadEntries()
        collectionView.reloadData()
        emptyLabel.isHidden = !entries.isEmpty
        loadThumbnails()
    }

    private func loadThumbnails() {
        for entry in entries {
            ThumbnailLoader.loadThumbnail(for: entry.tempURL, pointSize: 96) { [weak self, weak entry] image in
                guard let self, let entry, let index = self.entries.firstIndex(where: { $0 === entry }) else { return }
                entry.icon = image
                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            }
        }
    }

    func show() {
        reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension ArchiveWindowController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        entries.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .archiveThumbnail, for: indexPath) as! FileThumbnailItem
        let entry = entries[indexPath.item]
        item.configure(with: entry)
        item.onRemove = { [weak self, weak entry] in
            guard let self, let entry else { return }
            self.removeEntry(entry)
        }
        return item
    }

    // Files going OUT: hand the real archived-file URL to whatever app the user drags into.
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        entries[indexPath.item].tempURL as NSURL
    }

    private func removeEntry(_ entry: ShelfItem) {
        guard let index = entries.firstIndex(where: { $0 === entry }) else { return }
        ArchiveStorage.remove(entry)
        entries.remove(at: index)
        collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        emptyLabel.isHidden = !entries.isEmpty
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let archiveThumbnail = NSUserInterfaceItemIdentifier("ArchiveThumbnailItem")
}
