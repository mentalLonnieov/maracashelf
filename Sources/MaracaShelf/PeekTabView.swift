import AppKit

/// The small floating tab shown while a shelf is "peeked" off-screen — like Safari's
/// Picture-in-Picture window auto-hiding to a screen edge. Handles its own click/drag
/// gestures directly (not via `isMovableByWindowBackground`, which mouseDown/mouseDragged
/// deliberately never call `super` for, to keep AppKit from starting its own
/// window-background drag partway through and stealing the mouseUp before this view ever
/// saw it): a plain click, or a drag that pulls the tab away from the edge, activates it
/// (restores the shelf); a drag that stays close to the edge instead just slides the tab up
/// or down along it, since a real tab in this position (flush against a screen edge) has no
/// room to be dragged outward without also moving vertically somewhat, and that shouldn't be
/// misread as "pull it out".
final class PeekTabView: NSView {
    var onActivate: (() -> Void)?
    /// Fired once when a drag carrying an acceptable file first hovers over the tab — lets
    /// `ShelfWindowController` expand the shelf back out so the drag can actually land
    /// somewhere. Only ever fires once per hover, same as `draggingEntered` itself; the
    /// window controller ignores repeat calls once it's no longer peeked.
    var onDragHover: (() -> Void)?
    /// Fired every time a vertical reposition drag actually moves the tab — lets
    /// `ShelfWindowController` keep its "restore to here" frame in sync with the tab's
    /// current position, not just wherever it was when peeking first started.
    var onReposition: (() -> Void)?
    private let imageView = NSImageView()

    /// How far the cursor has to move (in either axis) from mouseDown before it counts as a
    /// drag rather than a click.
    private let clickThreshold: CGFloat = 4
    /// How far *horizontally* the cursor has to move before a drag counts as "pull the tab
    /// out" (restore) rather than "slide it along the edge" (reposition in place).
    private let pullOutThreshold: CGFloat = 24
    // Screen coordinates, not `event.locationInWindow` — that's measured relative to the
    // window's *current* frame, which we're the one moving every step of this drag. Using it
    // as the delta source fed back into that same window's origin creates a feedback loop
    // where each move shrinks how much of the cursor's further travel still registers,
    // making the tab lag further and further behind the cursor as the drag continues.
    // `NSEvent.mouseLocation` is absolute and never affected by our own `setFrameOrigin`
    // calls, so deltas measured from it stay accurate for the whole gesture.
    private var mouseDownScreenLocation: NSPoint?
    private var windowOriginAtMouseDown: NSPoint?
    /// Set once a drag has moved far enough horizontally to commit to "pull it out" — once
    /// set, further vertical movement no longer repositions the tab, matching how a real
    /// pull-out gesture would keep tracking the cursor's intent rather than flip back and
    /// forth between the two behaviors as it wobbles.
    private var isPullingOut = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        imageView.contentTintColor = .white
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        setDirection(pointingRight: true)
        registerForDraggedTypes(ShelfDropView.incomingDragTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Points toward wherever the shelf will slide back in from — right when peeking off
    /// the left edge, left when peeking off the right edge.
    func setDirection(pointingRight: Bool) {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        let symbol = pointingRight ? "chevron.right" : "chevron.left"
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownScreenLocation = NSEvent.mouseLocation
        windowOriginAtMouseDown = window?.frame.origin
        isPullingOut = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownScreenLocation, let originStart = windowOriginAtMouseDown, let window else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        if isPullingOut || abs(dx) >= pullOutThreshold {
            isPullingOut = true
            return
        }
        var newOrigin = originStart
        newOrigin.y += dy
        if let screen = window.screen {
            newOrigin.y = max(screen.visibleFrame.minY + 8,
                               min(newOrigin.y, screen.visibleFrame.maxY - window.frame.height - 8))
        }
        window.setFrameOrigin(newOrigin)
        onReposition?()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownScreenLocation = nil
            windowOriginAtMouseDown = nil
            isPullingOut = false
        }
        guard let start = mouseDownScreenLocation else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        let movedFarEnoughToBeADrag = abs(dx) >= clickThreshold || abs(dy) >= clickThreshold
        // Either this was a plain click (negligible movement in both axes), or a drag that
        // moved far enough horizontally to commit to "pull it out" — anything else was a
        // vertical reposition along the edge, which settles wherever mouseDragged left it
        // rather than restoring the shelf.
        guard !movedFarEnoughToBeADrag || isPullingOut else { return }
        onActivate?()
    }

    // Dragging-destination callbacks, unlike mouse events, are delivered to whichever exact
    // view hit-tests at that point with no fallback to an ancestor (see
    // CollapsedPreviewRow.hitTest for the same issue) — without this, a drag hovering
    // directly over the visible chevron glyph would hit `imageView` instead of this view,
    // which isn't registered for any dragged types, and the hover would silently do nothing.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard sender.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self, NSURL.self], options: nil) else {
            return []
        }
        onDragHover?()
        return .copy
    }
}
