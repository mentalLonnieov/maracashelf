import AppKit

final class FileThumbnailItem: NSCollectionViewItem {

    /// Called when the user clicks the per-item remove badge — lets a wrong file dropped
    /// in by mistake be taken back out without clearing the whole shelf.
    var onRemove: (() -> Void)?

    private let removeButton = RoundIconButton(symbol: "xmark", tint: .white, pointSize: 8)
    private var removeBadge: NSView!

    override func loadView() {
        let container = HoverTrackingView()
        container.wantsLayer = true
        container.onHoverChange = { [weak self] hovering in
            self?.removeBadge.isHidden = !hovering
        }

        let iconView = NSImageView()
        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        label.translatesAutoresizingMaskIntoConstraints = false

        removeButton.target = self
        removeButton.action = #selector(removeTapped)
        let badge = GlassChrome.control(cornerRadius: 9, content: removeButton)
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.isHidden = true
        removeBadge = badge

        container.addSubview(iconView)
        container.addSubview(label)
        container.addSubview(badge)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            iconView.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),

            label.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 4),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),

            badge.topAnchor.constraint(equalTo: iconView.topAnchor, constant: -6),
            badge.trailingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            badge.widthAnchor.constraint(equalToConstant: 18),
            badge.heightAnchor.constraint(equalToConstant: 18),
        ])

        self.view = container
        self.imageView = iconView
        self.textField = label
    }

    override var isSelected: Bool {
        didSet {
            view.layer?.backgroundColor = isSelected
                ? NSColor.white.withAlphaComponent(0.15).cgColor
                : NSColor.clear.cgColor
            view.layer?.cornerRadius = 8
        }
    }

    func configure(with item: ShelfItem) {
        imageView?.image = item.icon
        textField?.stringValue = item.displayName
        removeBadge.isHidden = true
    }

    @objc private func removeTapped() {
        onRemove?()
    }
}
