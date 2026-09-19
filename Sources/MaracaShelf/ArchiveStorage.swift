import Foundation

/// A serialized, independently testable archive. No AppKit objects cross its queue.
final class ArchiveStore {
    private let root: URL
    private let queue = DispatchQueue(label: "MaracaShelf.Archive", qos: .utility)
    private let metadataName = ".maraca-source-key"

    init(root: URL) { self.root = root }

    func archive(_ source: URL, sourceKey: String?) throws {
        try queue.sync {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if let sourceKey, folders().contains(where: { key(for: $0) == sourceKey }) { return }
            let id = UUID().uuidString
            let staging = root.appendingPathComponent(".pending-" + id)
            let destination = root.appendingPathComponent(id)
            do {
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(source.lastPathComponent))
                // The external marker distinguishes user content named like the old metadata.
                try (sourceKey ?? "").write(to: sidecar(destination), atomically: true, encoding: .utf8)
                try FileManager.default.moveItem(at: staging, to: destination)
            } catch {
                try? FileManager.default.removeItem(at: staging)
                try? FileManager.default.removeItem(at: sidecar(destination))
                throw error
            }
        }
    }

    func entries() -> [URL] {
        queue.sync {
            folders().sorted { date($0) > date($1) }.compactMap { folder in
                let hasExternalKey = FileManager.default.fileExists(atPath: sidecar(folder).path)
                return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
                    .first { hasExternalKey || $0.lastPathComponent != metadataName }
            }
        }
    }

    func remove(_ file: URL) throws {
        try queue.sync {
            let folder = file.deletingLastPathComponent()
            guard folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL else { return }
            try FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: sidecar(folder))
        }
    }

    func clearAll() throws {
        try queue.sync {
            if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.removeItem(at: root) }
        }
    }

    func purgeExpired(before cutoff: Date) -> Bool {
        queue.sync {
            var changed = false
            for folder in folders() where date(folder) < cutoff {
                do {
                    try FileManager.default.removeItem(at: folder)
                    try? FileManager.default.removeItem(at: sidecar(folder))
                    changed = true
                } catch { NSLog("Archive purge failed: %@", error.localizedDescription) }
            }
            return changed
        }
    }

    private func sidecar(_ folder: URL) -> URL {
        root.appendingPathComponent(folder.lastPathComponent + metadataName)
    }

    private func key(for folder: URL) -> String? {
        // Support existing archives without rewriting user data on upgrade.
        (try? String(contentsOf: sidecar(folder), encoding: .utf8))
            ?? (try? String(contentsOf: folder.appendingPathComponent(metadataName), encoding: .utf8))
    }

    private func folders() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    private func date(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
    }
}

enum ArchiveStorage {
    static let didChangeNotification = Notification.Name("MaracaShelf.ArchiveDidChange")
    static let supportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MaracaShelf", isDirectory: true)
    private static let store = ArchiveStore(root: supportDirectory.appendingPathComponent("Archive"))
    private static let work = DispatchQueue(label: "MaracaShelf.ArchiveRequests", qos: .utility)
    private static var isUninstalling = false // Accessed only on work.

    static func archive(_ source: URL, sourceKey: String?, completion: @escaping () -> Void) {
        work.async {
            defer { completion() }
            guard !isUninstalling else { return }
            do {
                try store.archive(source, sourceKey: sourceKey)
                notifyChanged()
            } catch { NSLog("Archive copy failed: %@", error.localizedDescription) }
        }
    }

    static func loadEntries(completion: @escaping ([ShelfItem]) -> Void) {
        work.async {
            let urls = store.entries()
            DispatchQueue.main.async {
                completion(urls.map { ShelfItem(displayName: $0.lastPathComponent, tempURL: $0) })
            }
        }
    }

    static func remove(_ item: ShelfItem) {
        let url = item.tempURL
        work.async {
            do { try store.remove(url); notifyChanged() }
            catch { NSLog("Archive removal failed: %@", error.localizedDescription) }
        }
    }

    static func clearAll() {
        work.async {
            do { try store.clearAll(); notifyChanged() }
            catch { NSLog("Archive clear failed: %@", error.localizedDescription) }
        }
    }

    static func purgeExpired() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -ArchiveRetentionSettings.days, to: Date()) else { return }
        work.async { if store.purgeExpired(before: cutoff) { notifyChanged() } }
    }

    static func removeSupportForUninstall(completion: @escaping () -> Void) {
        work.async {
            // Drain earlier writes and reject imports delivered after uninstall started.
            isUninstalling = true
            do {
                if FileManager.default.fileExists(atPath: supportDirectory.path) {
                    try FileManager.default.removeItem(at: supportDirectory)
                }
            } catch { NSLog("Uninstall data removal failed: %@", error.localizedDescription) }
            DispatchQueue.main.async(execute: completion)
        }
    }

    private static func notifyChanged() {
        DispatchQueue.main.async { NotificationCenter.default.post(name: didChangeNotification, object: nil) }
    }
}
