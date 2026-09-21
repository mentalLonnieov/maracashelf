import AppKit

protocol ShelfDropViewDelegate: AnyObject {
    func shelfDropView(_ view: ShelfDropView, performDrop pasteboard: NSPasteboard) -> Bool
}

/// The root view of the shelf. Drag-and-drop destination methods only work when implemented
/// on an NSView (or NSWindow), so this thin subclass exists purely to forward them to the
/// view controller, which owns the actual file-handling logic.
final class ShelfDropView: NSView {
    weak var dropDelegate: ShelfDropViewDelegate?

    /// Every pasteboard type the shelf accepts incoming files from — shared with any other
    /// view that needs to register as a drag destination for the same kinds of drops
    /// (`CollapsedPreviewRow` forwards instead of registering its own, but `PeekTabView`
    /// needs to actually register, since it must react to a hover before anything is
    /// dropped, not just forward a drop that already landed).
    static let incomingDragTypes: [NSPasteboard.PasteboardType] = {
        var types: [NSPasteboard.PasteboardType] = [.fileURL]
        types.append(contentsOf: NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) })
        return types
    }()

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isInternalDrag(sender) else { return [] }
        return sender.draggingPasteboard.canReadObject(forClasses: [NSFilePromiseReceiver.self, NSURL.self], options: nil)
            ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isInternalDrag(sender) else { return false }
        return dropDelegate?.shelfDropView(self, performDrop: sender.draggingPasteboard) ?? false
    }

    /// True when the drag was started by picking up an item already inside this same shelf
    /// window (e.g. grabbing a thumbnail and letting go without leaving the panel) — that
    /// must not be treated as a new incoming file, or it would duplicate the item.
    private func isInternalDrag(_ sender: NSDraggingInfo) -> Bool {
        guard let sourceView = sender.draggingSource as? NSView else { return false }
        return sourceView.window === window
    }
}
