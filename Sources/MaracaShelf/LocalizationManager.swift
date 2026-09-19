import Foundation

/// Loads and switches MaracaShelf's UI language independently of the system's own locale
/// resolution, so the user can override it from the settings window without relaunching —
/// unlike `NSLocalizedString`, which always resolves against `Bundle.main` and the
/// system's language list.
final class LocalizationManager {
    static let shared = LocalizationManager()

    /// Posted whenever the effective language changes, so already-built UI (the status bar
    /// menu, an open settings window) can refresh its text in place.
    static let languageDidChangeNotification = Notification.Name("MaracaShelf.LanguageDidChange")

    private static let defaultsKey = "AppLanguage"

    private var bundle: Bundle

    private init() {
        bundle = .main
        bundle = Self.loadBundle(for: Self.resolveLanguage())
    }

    /// The user's explicit choice, if any. `nil` means "follow the system language."
    var userOverride: AppLanguage? {
        get {
            UserDefaults.standard.string(forKey: Self.defaultsKey).flatMap(AppLanguage.init)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
            }
            bundle = Self.loadBundle(for: currentLanguage)
            NotificationCenter.default.post(name: Self.languageDidChangeNotification, object: nil)
        }
    }

    /// The language actually in effect right now.
    var currentLanguage: AppLanguage { Self.resolveLanguage() }

    private static func resolveLanguage() -> AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: defaultsKey), let override = AppLanguage(rawValue: raw) {
            return override
        }
        for preferred in Locale.preferredLanguages {
            let code = Locale(identifier: preferred).language.languageCode?.identifier ?? String(preferred.prefix(2))
            if let match = AppLanguage(rawValue: code) { return match }
        }
        return .en
    }

    private static func loadBundle(for language: AppLanguage) -> Bundle {
        guard let resourceURL = Bundle.main.resourceURL else { return .main }
        let lprojURL = resourceURL.appendingPathComponent("\(language.rawValue).lproj")
        return Bundle(url: lprojURL) ?? .main
    }

    func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: key, table: nil)
    }

    /// A "N files" style string, pluralized correctly for the current language.
    func fileCount(_ count: Int) -> String {
        let key: String
        switch Pluralizer.category(for: count, language: currentLanguage) {
        case .one: key = "files.one"
        case .few: key = "files.few"
        case .many: key = "files.many"
        case .other: key = "files.other"
        }
        return String(format: string(key), count)
    }
}

/// Shorthand for `LocalizationManager.shared.string(_:)`.
func L(_ key: String) -> String {
    LocalizationManager.shared.string(key)
}
