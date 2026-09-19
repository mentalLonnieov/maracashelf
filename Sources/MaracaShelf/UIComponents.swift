import AppKit

/// Small icon button used for the close (×) and collapse (⌄) controls. Purely the glyph —
/// the circular glass chrome around it comes from `GlassChrome.control`.
final class RoundIconButton: NSButton {
    private let pointSize: CGFloat

    init(symbol: String, tint: NSColor, pointSize: CGFloat = 12) {
        self.pointSize = pointSize
        super.init(frame: .zero)
        isBordered = false
        title = ""
        contentTintColor = tint
        setSymbol(symbol)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSymbol(_ name: String) {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        imageScaling = .scaleProportionallyDown
    }

    // Kept for callers that think in terms of "rotate the chevron"; we just swap the glyph.
    func rotate(to radians: CGFloat) {
        setSymbol(radians == 0 ? "chevron.down" : "chevron.up")
    }

    // The shelf panel never becomes key (see ShelfPanel), so buttons must opt into
    // responding to the very first click instead of requiring a click-to-focus first.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Text label/button used for the "N файлов" indicator at the bottom of the shelf. Purely
/// the text — the capsule glass chrome around it comes from `GlassChrome.control`.
final class PillButton: NSButton {

    init(title: String) {
        super.init(frame: .zero)
        isBordered = false
        self.attributedTitle = Self.makeTitle(title)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setTitle(_ title: String) {
        self.attributedTitle = Self.makeTitle(title)
    }

    private static func makeTitle(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
        ])
    }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 28, height: 26)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// An `NSCollectionView` that responds to the first click/drag immediately, since the
/// shelf panel that hosts it never becomes key (see `ShelfPanel`).
final class FirstMouseCollectionView: NSCollectionView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A view that reports mouse hover via a closure. Used to reveal each thumbnail's per-item
/// remove badge only while the pointer is actually over it — this works regardless of the
/// shelf panel's key/main status, since tracking areas don't require either.
final class HoverTrackingView: NSView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?(true) }
    override func mouseExited(with event: NSEvent) { onHoverChange?(false) }
}
