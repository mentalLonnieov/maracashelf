import AppKit

/// A compact row of small file icons shown only while the shelf is collapsed, so the
/// pill-sized bar still gives a glance at what's actually inside instead of just a count.
///
/// There's no room here for per-file selection like the expanded grid has, so pressing and
/// dragging from *any* icon just drags every file at once — the collapsed state is a
/// "grab the whole shelf" shortcut, not a picker.
final class CollapsedPreviewRow: NSView, NSDraggingSource {
    /// The panel's own drop-accepting view (`ShelfDropView`) — incoming drags are forwarded
    /// here rather than handled independently. `ShelfDropView` fully covers the panel
    /// including while collapsed, but AppKit only delivers dragging-destination callbacks
    /// to whichever *specific* view is registered for the dragged types and sits topmost
    /// under the pointer; this row visually sits on top of it while collapsed and wasn't
    /// itself registered, so drops landing directly on the visible icons were silently
    /// rejected. Forwarding (rather than duplicating the drop-handling logic here) keeps
    /// that logic — including the same-window self-drop guard — in one place.
    weak var dropForwardTarget: NSView?

    private let stack = NSStackView()
    private let maxVisible = 5
    private let iconSize: CGFloat = 28
    /// How far the pointer has to move from mouseDown before it counts as a drag rather
    /// than a click — avoids starting a drag session on every tiny mouse jitter.
    private let dragStartThreshold: CGFloat = 4

    private var items: [ShelfItem] = []
    private var mouseDownEvent: NSEvent?

    /// Width/height constraints for each icon, kept around so the collapse/expand
    /// transition can animate them growing from or shrinking to nothing.
    private var iconSizeConstraints: [(width: NSLayoutConstraint, height: NSLayoutConstraint)] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // The icon images and the "+N" label are purely decorative — all interaction (both the
    // outgoing "drag everything out" gesture and the incoming drop-forwarding below) is
    // meant to belong to the row itself. Dragging-destination callbacks, unlike mouse
    // events, are delivered to whichever exact view the point hit-tests to with no
    // fallback to an ancestor, so without this override a drop landing squarely on an icon
    // (rather than the gaps between them) would silently miss instead of reaching
    // `dropForwardTarget`.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    func update(with items: [ShelfItem]) {
        self.items = items
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        iconSizeConstraints.removeAll()

        for item in items.prefix(maxVisible) {
            let imageView = NSImageView()
            imageView.image = item.icon
            imageView.imageScaling = .scaleProportionallyUpOrDown
            imageView.translatesAutoresizingMaskIntoConstraints = false
            let width = imageView.widthAnchor.constraint(equalToConstant: iconSize)
            let height = imageView.heightAnchor.constraint(equalToConstant: iconSize)
            NSLayoutConstraint.activate([width, height])
            iconSizeConstraints.append((width, height))
            stack.addArrangedSubview(imageView)
        }

        let extra = items.count - maxVisible
        if extra > 0 {
            let label = NSTextField(labelWithString: "+\(extra)")
            label.font = .systemFont(ofSize: 12, weight: .semibold)
            label.textColor = .white.withAlphaComponent(0.8)
            stack.addArrangedSubview(label)
        }
    }

    /// Snaps every icon to zero size with no animation — call right before the collapse
    /// animation starts, so `growIconsIn()` inside the animated block has something to
    /// visibly grow from.
    func collapseIconsInstantly() {
        for pair in iconSizeConstraints {
            pair.width.constant = 0
            pair.height.constant = 0
        }
        layoutSubtreeIfNeeded()
    }

    /// Call inside an `NSAnimationContext` block (with `allowsImplicitAnimation = true`)
    /// to animate the icons growing in from nothing.
    func growIconsIn() {
        for pair in iconSizeConstraints {
            pair.width.constant = iconSize
            pair.height.constant = iconSize
        }
        layoutSubtreeIfNeeded()
    }

    /// Call inside an `NSAnimationContext` block to animate the icons shrinking away to
    /// nothing (used when expanding back out of the collapsed state).
    func shrinkIconsOut() {
        for pair in iconSizeConstraints {
            pair.width.constant = 0
            pair.height.constant = 0
        }
        layoutSubtreeIfNeeded()
    }

    // MARK: - Drag out (grabs every file at once)

    // The shelf panel never becomes key (see ShelfPanel), so this needs to respond to the
    // very first click/drag instead of requiring the window to be focused first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = items.isEmpty ? nil : event
    }

    override func mouseDragged(with event: NSEvent) {
        guard let downEvent = mouseDownEvent else { return }
        let dx = event.locationInWindow.x - downEvent.locationInWindow.x
        let dy = event.locationInWindow.y - downEvent.locationInWindow.y
        guard (dx * dx + dy * dy) > dragStartThreshold * dragStartThreshold else { return }
        mouseDownEvent = nil // only start the session once per press

        let anchor = convert(downEvent.locationInWindow, from: nil)
        let cardSize = NSSize(width: 40, height: 40)
        let cascadeStep: CGFloat = 6

        let draggingItems: [NSDraggingItem] = items.enumerated().map { index, item in
            let dragItem = NSDraggingItem(pasteboardWriter: item.tempURL as NSURL)
            let offset = CGFloat(index) * cascadeStep
            let frame = NSRect(
                x: anchor.x - cardSize.width / 2 + offset,
                y: anchor.y - cardSize.height / 2 - offset,
                width: cardSize.width, height: cardSize.height
            )
            dragItem.setDraggingFrame(frame, contents: item.icon)
            return dragItem
        }

        beginDraggingSession(with: draggingItems, event: downEvent, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    // MARK: - Drag in (forwarded to the panel's drop view — see `dropForwardTarget`)

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropForwardTarget?.draggingEntered(sender) ?? []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropForwardTarget?.performDragOperation(sender) ?? false
    }
}
