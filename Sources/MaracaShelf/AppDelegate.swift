import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let shakeMonitor = ShakeDragMonitor()
    private var activeShelf: ShelfWindowController?
    private var statusItem: NSStatusItem?
    private var settingsWindowController: SettingsWindowController?
    private var archiveWindowController: ArchiveWindowController?
    private var archivePurgeTimer: Timer?

    private var archiveMenuItem: NSMenuItem?
    private var settingsMenuItem: NSMenuItem?
    private var accessibilityMenuItem: NSMenuItem?
    private var uninstallMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        ShelfStorage.cleanUpOrphanedSessions()
        ArchiveStorage.purgeExpired()
        promptForAccessibilityIfNeeded()
        setupStatusItem()

        NotificationCenter.default.addObserver(
            self, selector: #selector(refreshMenuTitles),
            name: LocalizationManager.languageDidChangeNotification, object: nil
        )

        shakeMonitor.onShake = { [weak self] location in
            self?.handleShake(at: location)
        }
        shakeMonitor.start()

        // The app can easily run for days between launches — sweep expired archive entries
        // periodically instead of relying solely on the launch-time and window-open checks.
        archivePurgeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            ArchiveStorage.purgeExpired()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        shakeMonitor.stop()
        archivePurgeTimer?.invalidate()
    }

    private func handleShake(at location: CGPoint) {
        // Only one shelf at a time — a second shake while one is open just leaves it be.
        guard activeShelf == nil else { return }

        let shelf = ShelfWindowController()
        shelf.onClose = { [weak self] in
            self?.activeShelf = nil
        }
        shelf.show(at: location)
        activeShelf = shelf
    }

    private func promptForAccessibilityIfNeeded() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = Self.loadStatusIcon()

        let menu = NSMenu()
        menu.addItem(withTitle: "MaracaShelf", action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())

        let archiveItem = menu.addItem(withTitle: "", action: #selector(openArchive), keyEquivalent: "")
        archiveItem.target = self
        archiveMenuItem = archiveItem

        let settingsItem = menu.addItem(withTitle: "", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        settingsMenuItem = settingsItem

        let accessibilityItem = menu.addItem(withTitle: "", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        accessibilityItem.target = self
        accessibilityMenuItem = accessibilityItem

        menu.addItem(.separator())

        let uninstallItem = menu.addItem(withTitle: "", action: #selector(uninstallTapped), keyEquivalent: "")
        uninstallItem.target = self
        uninstallMenuItem = uninstallItem

        menu.addItem(.separator())

        let quitItem = menu.addItem(withTitle: "", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        quitMenuItem = quitItem

        item.menu = menu
        statusItem = item
        refreshMenuTitles()
    }

    @objc private func refreshMenuTitles() {
        archiveMenuItem?.title = L("menu.show_archive")
        settingsMenuItem?.title = L("menu.settings")
        accessibilityMenuItem?.title = L("menu.accessibility")
        uninstallMenuItem?.title = L("menu.uninstall")
        quitMenuItem?.title = L("menu.quit")
    }

    /// Loads the custom maraca menu-bar icon from the app bundle's Resources (both @2x and
    /// @3x representations, so it stays crisp on any display), tagged as a template image
    /// so macOS tints it correctly for light/dark menu bars and the highlighted state.
    /// Falls back to a generic SF Symbol if the bundled files aren't present — e.g. when
    /// running the raw debug binary directly instead of the packaged .app.
    private static func loadStatusIcon() -> NSImage? {
        guard let resourceURL = Bundle.main.resourceURL else { return fallbackIcon() }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        var loadedAny = false
        for suffix in ["@2x", "@3x"] {
            let url = resourceURL.appendingPathComponent("MaracaStatusIcon\(suffix).png")
            if let data = try? Data(contentsOf: url), let rep = NSBitmapImageRep(data: data) {
                rep.size = NSSize(width: 18, height: 18)
                image.addRepresentation(rep)
                loadedAny = true
            }
        }
        guard loadedAny else { return fallbackIcon() }
        image.isTemplate = true
        return image
    }

    private static func fallbackIcon() -> NSImage? {
        NSImage(systemSymbolName: "shippingbox", accessibilityDescription: "MaracaShelf")
    }

    @objc private func openArchive() {
        let controller = archiveWindowController ?? ArchiveWindowController()
        archiveWindowController = controller
        controller.show()
    }

    @objc private func openSettings() {
        let controller = settingsWindowController ?? SettingsWindowController()
        settingsWindowController = controller
        controller.show()
    }

    @objc private func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    @objc private func uninstallTapped() {
        let alert = NSAlert()
        alert.messageText = L("uninstall.confirm_title")
        alert.informativeText = L("uninstall.confirm_message")
        alert.addButton(withTitle: L("uninstall.confirm_button"))
        alert.addButton(withTitle: L("uninstall.cancel_button"))
        alert.alertStyle = .warning
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let bundleURL = Bundle.main.bundleURL
        // Running the raw executable directly (e.g. `swift run`, or the debug binary during
        // development) rather than the packaged .app — there's nothing sensible to move to
        // the Trash, so just drop the archive and quit instead of recycling an unexpected path.
        guard bundleURL.pathExtension == "app" else {
            ArchiveStorage.removeSupportForUninstall { NSApp.terminate(nil) }
            return
        }

        // Move the app to the Trash FIRST and only delete the archive once that has
        // actually succeeded — the previous order deleted the archive unconditionally
        // before attempting the move, so a failed/denied Trash operation (surfaced only via
        // the ignored `error` parameter) used to silently destroy the user's data while
        // leaving the app installed. recycle()'s completion isn't guaranteed to run on the
        // main thread, so both branches below dispatch back to it explicitly.
        NSWorkspace.shared.recycle([bundleURL]) { _, error in
            guard error == nil else {
                DispatchQueue.main.async {
                    let failure = NSAlert()
                    failure.messageText = L("uninstall.failed_title")
                    failure.informativeText = L("uninstall.failed_message")
                    failure.alertStyle = .critical
                    failure.runModal()
                }
                return
            }
            ArchiveStorage.removeSupportForUninstall {
                NSApp.terminate(nil)
            }
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
