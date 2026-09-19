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
}
