import AppKit

/// The small floating tab shown while a shelf is "peeked" off-screen — like Safari's
/// Picture-in-Picture window auto-hiding to a screen edge. Handles its own click-or-drag
/// activation: `mouseUp` fires regardless of how far the cursor moved before release (no
/// separate tap/drag distinction is needed, since both should do the same thing here), and
/// overriding `mouseDown`/`mouseDragged` as no-ops keeps AppKit from instead starting its
/// own window-background drag partway through — which would steal the mouseUp before this
/// view ever saw it, since `ShelfWindowController` moves the tab itself via `setFrameOrigin`
/// rather than relying on `isMovableByWindowBackground` for this particular view.
final class PeekTabView: NSView {
    var onActivate: (() -> Void)?
    /// Fired once when a drag carrying an acceptable file first hovers over the tab — lets
    /// `ShelfWindowController` expand the shelf back out so the drag can actually land
    /// somewhere. Only ever fires once per hover, same as `draggingEntered` itself; the
    /// window controller ignores repeat calls once it's no longer peeked.
    var onDragHover: (() -> Void)?
    private let imageView = NSImageView()

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
    override func mouseDown(with event: NSEvent) {}
    override func mouseDragged(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
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
