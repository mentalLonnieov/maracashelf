import Foundation

/// Persistent, cross-launch storage for every file that has ever passed through a shelf.
/// Unlike `ShelfStorage`'s per-session temp directory (wiped the instant that shelf closes),
/// these copies live in Application Support and survive relaunches — only removed by the
/// retention timer, a manual "Clear Archive", or the in-app Uninstall action.
enum ArchiveStorage {

    /// `~/Library/Application Support/MaracaShelf` — the whole folder is what Uninstall
    /// deletes, so nothing else of ours should ever be stored outside it.
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MaracaShelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }()

    private static let root: URL = {
        let url = supportDirectory.appendingPathComponent("Archive", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Hidden sidecar file recording the identity (`ShelfItem.sourceKey`) of the file each
    /// archive folder was copied from — lets `archive(_:sourceKey:)` recognize "this exact
    /// file is already archived" across shelf sessions, not just within one open shelf.
    /// The leading dot keeps it out of `loadEntries()`'s `.skipsHiddenFiles` directory scan.
    private static let sourceKeyFileName = ".maraca-source-key"

    /// Copies a file (already a shelf's own temp copy, never the original) into permanent
    /// storage, in its own UUID-named folder so two archived files with the same name never
    /// collide. A no-op if `sourceKey` matches a file already archived — from this same
    /// shelf session or an earlier one — so removing and re-adding the same file, or
    /// dragging it into a brand-new shake session, doesn't pile up redundant copies.
    static func archive(_ sourceURL: URL, sourceKey: String?) {
        if let sourceKey, isAlreadyArchived(sourceKey: sourceKey) {
            return
        }
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: sourceURL, to: folder.appendingPathComponent(sourceURL.lastPathComponent))
            if let sourceKey {
                try sourceKey.write(to: folder.appendingPathComponent(sourceKeyFileName), atomically: true, encoding: .utf8)
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private static func isAlreadyArchived(sourceKey: String) -> Bool {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) else { return false }
        return folders.contains { folder in
            let existingKey = try? String(contentsOf: folder.appendingPathComponent(sourceKeyFileName), encoding: .utf8)
            return existingKey == sourceKey
        }
    }

    /// Every archived file, newest first.
    static func loadEntries() -> [ShelfItem] {
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        return folders
            .sorted { creationDate(of: $0) > creationDate(of: $1) }
            .compactMap { folder -> ShelfItem? in
                guard let file = try? FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
                ).first else {
                    return nil
                }
                return ShelfItem(displayName: file.lastPathComponent, tempURL: file)
            }
    }

    /// Deletes one archived file (and its containing folder).
    static func remove(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: item.tempURL.deletingLastPathComponent())
    }

    /// Deletes every archived file.
    static func clearAll() {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// Deletes archived folders older than `ArchiveRetentionSettings.days`. Called on launch,
    /// periodically while running, and whenever the archive window opens.
    static func purgeExpired() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -ArchiveRetentionSettings.days, to: Date()) else { return }
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles]
        ) else { return }
        for folder in folders where creationDate(of: folder) < cutoff {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    private static func creationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }
}
