import AppKit

protocol ShelfViewControllerDelegate: AnyObject {
    func shelfDidRequestClose(_ controller: ShelfViewController)
}

final class ShelfViewController: NSViewController, ShelfDropViewDelegate, NSSharingServiceDelegate {

    weak var delegate: ShelfViewControllerDelegate?

    private let storage = ShelfStorage()
    private var items: [ShelfItem] = []
    // Tracks the entire import, including delayed promise callbacks and archive writes.
    private let pendingImports = ImportLifetime()
    private var isClosing = false
    private let fileIOQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return queue
    }()

    /// Identity keys of files already added to this shelf — see `shelfDropView(performDrop:)`
    /// — so dragging the same file in again is rejected instead of piling up endless
    /// renamed duplicates ("file 1.ext", "file 2.ext", ...).
    private var knownFileKeys: Set<String> = []

    // Auto Layout's real minimum for the collapsed content is measured empirically (see
    // README) — asking for less makes the window animate toward an impossible size and get
    // yanked to the real minimum the instant the animation settles, which looks like a
    // glitch. Grew from 100 to fit the collapsed preview row of thumbnails. Independent of
    // ShelfSizePreference — the collapsed content (buttons, preview row, count pill) is
    // the same regardless of how many grid columns the expanded state uses.
    private let collapsedHeight: CGFloat = 132
    // Both read once at creation from the user's chosen size (Settings → Shelf Size) —
    // resizing an already-open shelf isn't attempted, so this shelf keeps whatever size it
    // started with even if the setting changes while it's open.
    let expandedHeight: CGFloat = ShelfSizePreference.value.expandedHeight
    let panelWidth: CGFloat = ShelfSizePreference.value.panelWidth
    private var isCollapsed = false

    private let closeButton = RoundIconButton(symbol: "xmark", tint: .white)
    private let collapseButton = RoundIconButton(symbol: "chevron.up", tint: .white)
    private let airDropButton = RoundIconButton(symbol: "square.and.arrow.up", tint: .white)
    private var airDropGlass: NSView!
    private var activeSharingService: NSSharingService?
    private let dropHintLabel = NSTextField(labelWithString: L("drop_hint"))
    private let countPill = PillButton(title: LocalizationManager.shared.fileCount(0))
    private let collapsedPreview = CollapsedPreviewRow()
    private var collectionView: NSCollectionView!
    private var scrollView: NSScrollView!
    private var selectAllMenuItem: NSMenuItem!

    override func loadView() {
        // The glass panel IS this controller's view (and therefore the window's
        // contentView once ShelfWindowController assigns it) — no plain wrapper view in
        // between. NSWindow guarantees its contentView tracks an animated setFrame
        // perfectly smoothly; an extra layer on top of that (even autoresizing-based)
        // still visibly lagged during the collapse/expand animation, so this avoids the
        // question entirely rather than fighting it.
        let chromeContent = ShelfDropView(frame: NSRect(x: 0, y: 0, width: panelWidth, height: expandedHeight))
        chromeContent.dropDelegate = self

        let glassPanel = GlassChrome.panel(cornerRadius: 22, content: chromeContent)
        self.view = glassPanel

        setupHeader(in: chromeContent)
        setupCollectionView(in: chromeContent)
        setupCountPill(in: chromeContent)

        registerDragTypes(on: chromeContent)
        refresh()
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // NSCollectionView re-asserts its own scroller during layout regardless of what
        // we configure on the scroll view up front, so hiding it has to be reapplied
        // every pass rather than done once at setup.
        scrollView.verticalScroller?.alphaValue = 0
        scrollView.horizontalScroller?.alphaValue = 0
    }

    // MARK: - Layout

    private func setupHeader(in container: NSView) {
        closeButton.target = self
        closeButton.action = #selector(closeTapped)
        let closeGlass = GlassChrome.control(cornerRadius: 14, content: closeButton)
        closeGlass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(closeGlass)

        collapseButton.target = self
        collapseButton.action = #selector(collapseTapped)
        let collapseGlass = GlassChrome.control(cornerRadius: 14, content: collapseButton)
        collapseGlass.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(collapseGlass)

        // Disabled until at least one file is selected; hidden entirely while collapsed
        // (see collapseTapped) since there's nothing to select without the grid visible.
        airDropButton.target = self
        airDropButton.action = #selector(airDropTapped)
        airDropButton.isEnabled = false
        let airDropGlass = GlassChrome.control(cornerRadius: 14, content: airDropButton)
        airDropGlass.translatesAutoresizingMaskIntoConstraints = false
        airDropGlass.alphaValue = 0.35
        container.addSubview(airDropGlass)
        self.airDropGlass = airDropGlass

        NSLayoutConstraint.activate([
            closeGlass.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            closeGlass.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 14),
            closeGlass.widthAnchor.constraint(equalToConstant: 28),
            closeGlass.heightAnchor.constraint(equalToConstant: 28),

            collapseGlass.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            collapseGlass.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -14),
            collapseGlass.widthAnchor.constraint(equalToConstant: 28),
            collapseGlass.heightAnchor.constraint(equalToConstant: 28),

            airDropGlass.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            airDropGlass.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            airDropGlass.widthAnchor.constraint(equalToConstant: 28),
            airDropGlass.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Only shown while collapsed (see collapseTapped) — a glance at what's inside
        // instead of the pill-sized bar just repeating the count with empty space above it.
        collapsedPreview.translatesAutoresizingMaskIntoConstraints = false
        collapsedPreview.isHidden = true
        collapsedPreview.dropForwardTarget = container
        registerDragTypes(on: collapsedPreview)
        container.addSubview(collapsedPreview)
        NSLayoutConstraint.activate([
            collapsedPreview.topAnchor.constraint(equalTo: closeGlass.bottomAnchor, constant: 8),
            collapsedPreview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            collapsedPreview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            collapsedPreview.heightAnchor.constraint(equalToConstant: 28),
        ])
    }

    private func setupCollectionView(in container: NSView) {
        let layout = NSCollectionViewFlowLayout()
        layout.itemSize = NSSize(width: 74, height: 84)
        layout.minimumInteritemSpacing = 10
        layout.minimumLineSpacing = 10
        layout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)

        collectionView = FirstMouseCollectionView()
        collectionView.collectionViewLayout = layout
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsMultipleSelection = true
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(FileThumbnailItem.self, forItemWithIdentifier: .thumbnail)
        collectionView.setDraggingSourceOperationMask([.copy], forLocal: false)
        // No local (same-app) operation: dropping an item back onto its own shelf must not
        // duplicate it. See ShelfDropView.isInternalDrag for the actual guard.
        collectionView.setDraggingSourceOperationMask([], forLocal: true)

        // Cmd+A can't work here — the shelf panel never becomes key (see ShelfPanel), so
        // it never receives keyboard events at all. A right-click menu is the mouse-only
        // equivalent, useful once there are enough files that ⌘-clicking each one gets
        // tedious.
        let contextMenu = NSMenu()
        let selectAllItem = contextMenu.addItem(withTitle: L("shelf.select_all"), action: #selector(selectAllTapped), keyEquivalent: "")
        selectAllItem.target = self
        selectAllMenuItem = selectAllItem
        collectionView.menu = contextMenu

        scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = collectionView
        scrollView.drawsBackground = false
        // No visible scroll indicator — scrolling itself (trackpad/wheel/drag) works
        // regardless. NSCollectionView keeps recreating/re-showing its own scroller
        // during layout no matter what we set here up front, so it's forced invisible
        // on every layout pass instead (see viewDidLayout).
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false
        container.addSubview(scrollView)

        dropHintLabel.translatesAutoresizingMaskIntoConstraints = false
        dropHintLabel.textColor = .white.withAlphaComponent(0.55)
        dropHintLabel.font = .systemFont(ofSize: 12)
        dropHintLabel.alignment = .center
        container.addSubview(dropHintLabel)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: closeButton.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -46),

            dropHintLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            dropHintLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),
            dropHintLabel.widthAnchor.constraint(equalToConstant: 180),
        ])
    }

    private func setupCountPill(in container: NSView) {
        countPill.translatesAutoresizingMaskIntoConstraints = false
        countPill.target = self
        countPill.action = #selector(collapseTapped)
        container.addSubview(countPill)

        NSLayoutConstraint.activate([
            countPill.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
            countPill.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            countPill.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    // MARK: - Drag destination (files coming IN)

    private func registerDragTypes(on view: NSView) {
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        view.registerForDraggedTypes(types)
    }

    func shelfDropView(_ view: ShelfDropView, performDrop pasteboard: NSPasteboard) -> Bool {
        guard !isClosing else { return false }
        let classes: [AnyClass] = [NSFilePromiseReceiver.self, NSURL.self]
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        guard let objects = pasteboard.readObjects(forClasses: classes, options: options), !objects.isEmpty else {
            return false
        }

        var addedAny = false

        for object in objects {
            if let promiseReceiver = object as? NSFilePromiseReceiver {
                // Promises (Mail/Safari attachments) never expose the sender's original file
                // path, only the proposed name — used as the dedup key instead. That's a
                // deliberate simplification: two different attachments that happen to share a
                // name would also be (harmlessly) treated as duplicates.
                let key = "promise:" + (promiseReceiver.fileNames.first ?? UUID().uuidString)
                guard !knownFileKeys.contains(key) else {
                    flashExistingItem(for: key)
                    continue
                }
                knownFileKeys.insert(key)
                addedAny = true
                // A receiver calls its reader once per promised file, including failures.
                for _ in 0..<max(1, promiseReceiver.fileNames.count) { pendingImports.begin() }
                promiseReceiver.receivePromisedFiles(
                    atDestination: storage.sessionDirectory,
                    options: [:],
                    operationQueue: fileIOQueue
                ) { fileURL, error in
                    DispatchQueue.main.async {
                        self.completeImport(url: error == nil ? fileURL : nil,
                                            displayName: fileURL.lastPathComponent, key: key)
                    }
                }
            } else if let url = object as? URL {
                let key = "url:" + url.standardizedFileURL.path
                guard !knownFileKeys.contains(key) else {
                    flashExistingItem(for: key)
                    continue
                }
                knownFileKeys.insert(key)
                addedAny = true
                pendingImports.begin()
                // The actual copy (and the ShelfItem it produces) happens off the main
                // thread — see ShelfStorage.copyFile — so a large file/folder doesn't
                // freeze the app or the drag session itself.
                fileIOQueue.addOperation {
                    let copied = self.storage.copyFile(from: url)
                    DispatchQueue.main.async {
                        self.completeImport(url: copied?.destination,
                                            displayName: copied?.displayName ?? url.lastPathComponent, key: key)
                    }
                }
            }
        }

        // The same "something just landed" tap Finder gives you when dragging an icon onto a
        // folder — one pulse per drop that actually added something new, not per file, and
        // not at all when the whole drop turned out to be duplicates already in the shelf.
        if addedAny {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
        // Returning false for an all-duplicates drop makes the dragged icon(s) snap back to
        // their origin — the standard AppKit "rejected" animation, on top of the flash on
        // the existing item(s) — instead of silently pretending the drop succeeded.
        return addedAny
    }

    private func completeImport(url: URL?, displayName: String, key: String) {
        guard let url else {
            knownFileKeys.remove(key)
            pendingImports.finish()
            return
        }
        ArchiveStorage.archive(url, sourceKey: key) {
            DispatchQueue.main.async {
                defer { self.pendingImports.finish() }
                guard !self.isClosing else { return }
                self.addItem(ShelfItem(displayName: displayName, tempURL: url), sourceKey: key)
            }
        }
    }

    private func addItem(_ item: ShelfItem, sourceKey: String? = nil) {
        item.sourceKey = sourceKey
        items.append(item)
        collectionView.insertItems(at: [IndexPath(item: items.count - 1, section: 0)])
        refresh()

        ThumbnailLoader.loadThumbnail(for: item.tempURL, pointSize: 96) { [weak self, weak item] image in
            guard let self, let item, let index = self.items.firstIndex(where: { $0 === item }) else { return }
            item.icon = image
            self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            self.collapsedPreview.update(with: self.items)
        }
    }

    /// Briefly highlights the shelf's existing copy of a file whose re-drop was just
    /// rejected as a duplicate, so the rejection isn't a silent no-op.
    private func flashExistingItem(for key: String) {
        guard let index = items.firstIndex(where: { $0.sourceKey == key }) else { return }
        let indexPath = IndexPath(item: index, section: 0)
        collectionView.scrollToItems(at: [indexPath], scrollPosition: .centeredVertically)
        (collectionView.item(at: indexPath) as? FileThumbnailItem)?.flash()
    }

    /// Takes a single file back out of the shelf (e.g. the wrong one got dropped in) —
    /// deletes only our temp copy, never the original. Also frees up its dedup key, so the
    /// same file can deliberately be dropped back in afterward.
    private func removeItem(_ item: ShelfItem) {
        guard let index = items.firstIndex(where: { $0 === item }) else { return }
        items.remove(at: index)
        if let key = item.sourceKey { knownFileKeys.remove(key) }
        // Items only become interactive after their archive operation has completed.
        let url = item.tempURL
        fileIOQueue.addOperation { try? FileManager.default.removeItem(at: url) }
        collectionView.deleteItems(at: [IndexPath(item: index, section: 0)])
        refresh()
        updateAirDropButtonState()
    }

    private func refresh() {
        dropHintLabel.isHidden = isCollapsed || !items.isEmpty
        countPill.setTitle(LocalizationManager.shared.fileCount(items.count))
        collapsedPreview.update(with: items)
    }

    // MARK: - Actions

    @objc private func closeTapped() {
        guard !isClosing else { return }
        isClosing = true
        let storage = self.storage
        pendingImports.close {
            storage.cleanUp()
        }
        delegate?.shelfDidRequestClose(self)
    }

    @objc private func airDropTapped() {
        let urls = collectionView.selectionIndexPaths
            .sorted { $0.item < $1.item }
            .map { items[$0.item].tempURL }
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        // sourceWindowForShareItems (tried earlier) attaches AirDrop as a sheet on our
        // panel, which brought back the system key-window focus ring we specifically
        // disabled ShelfPanel.canBecomeKey to avoid — hosting a sheet apparently forces
        // that highlight through a different path than plain key-window status. Anchoring
        // only via the button's screen frame avoids that (no window ownership involved)
        // while still avoiding the default "slides from the top of the screen" placement.
        // Keep a strong reference: NSSharingService can be deallocated mid-flow otherwise,
        // since nothing else retains it once perform(withItems:) returns.
        service.delegate = self
        activeSharingService = service
        service.perform(withItems: urls)
    }

    // MARK: - NSSharingServiceDelegate

    func sharingService(_ sharingService: NSSharingService, sourceFrameOnScreenForShareItem item: Any) -> NSRect {
        guard let window = view.window else { return .zero }
        let frameInWindow = airDropGlass.convert(airDropGlass.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }

    func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        activeSharingService = nil
    }

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: any Error) {
        activeSharingService = nil
    }

    private func updateAirDropButtonState() {
        let hasSelection = !collectionView.selectionIndexPaths.isEmpty
        airDropButton.isEnabled = hasSelection
        airDropGlass.alphaValue = hasSelection ? 1 : 0.35
    }

    @objc private func selectAllTapped() {
        guard !items.isEmpty else { return }
        let allIndexPaths = Set((0..<items.count).map { IndexPath(item: $0, section: 0) })
        // Programmatic selection changes don't call the delegate's didSelectItemsAt, unlike
        // an actual click — update the AirDrop button ourselves rather than relying on it.
        collectionView.selectItems(at: allIndexPaths, scrollPosition: [])
        updateAirDropButtonState()
    }

    @objc private func collapseTapped() {
        isCollapsed.toggle()
        dropHintLabel.isHidden = isCollapsed || !items.isEmpty
        airDropGlass.isHidden = isCollapsed
        collapseButton.rotate(to: isCollapsed ? .pi : 0)
        guard let window = view.window else { return }
        var frame = window.frame
        let newHeight = isCollapsed ? collapsedHeight : expandedHeight
        frame.origin.y += (frame.height - newHeight)
        frame.size.height = newHeight

        // Both stay visible for the whole crossfade — whichever should end up hidden only
        // gets `isHidden` reapplied once it has actually faded out, in the completion
        // handler, otherwise there'd be nothing to fade.
        scrollView.isHidden = false
        collapsedPreview.isHidden = false
        if isCollapsed {
            collapsedPreview.collapseIconsInstantly()
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            ctx.allowsImplicitAnimation = true
            window.animator().setFrame(frame, display: true)
            scrollView.animator().alphaValue = isCollapsed ? 0 : 1
            collapsedPreview.animator().alphaValue = isCollapsed ? 1 : 0
            if isCollapsed {
                collapsedPreview.growIconsIn()
            } else {
                collapsedPreview.shrinkIconsOut()
            }
        }, completionHandler: { [weak self] in
            guard let self else { return }
            self.scrollView.isHidden = self.isCollapsed
            self.collapsedPreview.isHidden = !self.isCollapsed
        })
    }
}

// MARK: - NSCollectionViewDataSource / Delegate

extension ShelfViewController: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .thumbnail, for: indexPath) as! FileThumbnailItem
        let shelfItem = items[indexPath.item]
        item.configure(with: shelfItem)
        item.onRemove = { [weak self, weak shelfItem] in
            guard let self, let shelfItem else { return }
            self.removeItem(shelfItem)
        }
        return item
    }

    // Files going OUT: hand the real temp-file URL to whatever app the user drags into.
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        items[indexPath.item].tempURL as NSURL
    }

    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        updateAirDropButtonState()
    }

    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) {
        updateAirDropButtonState()
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let thumbnail = NSUserInterfaceItemIdentifier("FileThumbnailItem")
}
