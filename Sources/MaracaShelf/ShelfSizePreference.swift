import AppKit

/// How large the shelf's expanded grid is. Persisted via UserDefaults; takes effect the
/// next time a shelf opens — resizing a panel the user might already be dragging over
/// would be jarring, so an already-open shelf keeps whatever size it started with.
enum ShelfSizePreference: String, CaseIterable {
    case standard
    case compact

    private static let key = "ShelfSize"

    static var value: ShelfSizePreference {
        get { UserDefaults.standard.string(forKey: key).flatMap(ShelfSizePreference.init) ?? .standard }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Grid columns in the expanded state — the only real difference between the two
    /// sizes; `panelWidth` is derived from it the same way the original fixed 3-column
    /// width (270) was tuned.
    private var columns: CGFloat {
        switch self {
        case .standard: return 3
        case .compact: return 2
        }
    }

    /// `NSCollectionViewFlowLayout`'s configured `minimumInteritemSpacing` is 10pt, but any
    /// leftover width in a row gets stretched into the gaps *between* items rather than
    /// left as slack — the original 270 was tuned so that stretch lands exactly on 12pt,
    /// matching the 12pt section insets (confirmed by dumping the actual cell frames: every
    /// gap, inset or interitem, ends up 12pt). So the width formula uses that resulting
    /// 12pt, not the nominal 10pt, to reproduce the same uniform-gap look at any column
    /// count: `columns*74 + (columns-1)*12 + 24` gives back exactly 270 for 3 columns.
    var panelWidth: CGFloat {
        columns * 74 + (columns - 1) * 12 + 24
    }

    /// Tall enough to show exactly two rows of items before scrolling — unlike the
    /// collapsed state's height, this isn't a hard Auto Layout minimum (the grid is
    /// inside a scroll view, so any height just shows fewer/more rows and scrolls for the
    /// rest), so it doesn't need the same empirical minimum-hunting `collapsedHeight` did.
    var expandedHeight: CGFloat {
        switch self {
        case .standard: return 320
        case .compact: return 298
        }
    }
}
