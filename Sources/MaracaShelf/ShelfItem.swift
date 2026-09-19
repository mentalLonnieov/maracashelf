import AppKit
import UniformTypeIdentifiers

/// A single file held in the shelf. We keep our own temporary copy so the shelf stays
/// usable (and draggable) even if the original file is moved, renamed, or is on a volume
/// that goes away — and so closing the shelf can clean up without ever touching the source.
final class ShelfItem {
    let displayName: String
    let tempURL: URL
    /// Starts out as the generic file-type icon and gets swapped for a real content
    /// preview (actual image/PDF/etc. content) once `ThumbnailLoader` finishes rendering it.
    var icon: NSImage

    init(displayName: String, tempURL: URL) {
        self.displayName = displayName
        self.tempURL = tempURL
        self.icon = NSWorkspace.shared.icon(forFile: tempURL.path)
    }
}

/// Owns a per-session temporary directory that holds copies of everything dropped into the
/// shelf. Deleting it (on close) never touches the original files, only our copies.
final class ShelfStorage {
    let sessionDirectory: URL

    init() {
        sessionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MaracaShelf-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDirectory, withIntermediateDirectories: true)
    }

    /// Copies a source file into this session's temp directory, resolving name collisions.
    func copy(from sourceURL: URL) -> ShelfItem? {
        let baseName = sourceURL.lastPathComponent
        var destination = sessionDirectory.appendingPathComponent(baseName)
        var counter = 1
        let ext = sourceURL.pathExtension
        let stem = sourceURL.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: destination.path) {
            let candidate = ext.isEmpty ? "\(stem) \(counter)" : "\(stem) \(counter).\(ext)"
            destination = sessionDirectory.appendingPathComponent(candidate)
            counter += 1
        }

        do {
            // Prefer a real copy; if the source disappears mid-shake, just skip it.
            try FileManager.default.copyItem(at: sourceURL, to: destination)
            return ShelfItem(displayName: baseName, tempURL: destination)
        } catch {
            return nil
        }
    }

    /// Removes every copy the shelf made. Never touches original files.
    func cleanUp() {
        try? FileManager.default.removeItem(at: sessionDirectory)
    }

    /// Sweeps up temp copies left behind by a previous run that crashed or was force-quit
    /// before its shelf could be closed normally. Only ever touches our own temp copies.
    static func cleanUpOrphanedSessions() {
        let tmp = FileManager.default.temporaryDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else { return }
        for url in contents where url.lastPathComponent.hasPrefix("MaracaShelf-") {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
