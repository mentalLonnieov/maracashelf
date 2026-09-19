import Foundation

/// UI languages MaracaShelf ships with. Add a case here plus a matching
/// `Resources/<code>.lproj/Localizable.strings` to add another.
enum AppLanguage: String, CaseIterable {
    case en, ru, uk, pl, cs, de

    /// Name shown in the language picker, in that language itself (not translated into
    /// whatever language is currently active) — the standard convention for language
    /// pickers, since a user who doesn't read the current language still needs to find
    /// their own.
    var nativeName: String {
        switch self {
        case .en: return "English"
        case .ru: return "Русский"
        case .uk: return "Українська"
        case .pl: return "Polski"
        case .cs: return "Čeština"
        case .de: return "Deutsch"
        }
    }
}
