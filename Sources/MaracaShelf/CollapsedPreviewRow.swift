import AppKit

/// A compact row of small file icons shown only while the shelf is collapsed, so the
/// pill-sized bar still gives a glance at what's actually inside instead of just a count.
final class CollapsedPreviewRow: NSView {
    private let stack = NSStackView()
    private let maxVisible = 5
    private let iconSize: CGFloat = 28

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

    func update(with items: [ShelfItem]) {
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
}
