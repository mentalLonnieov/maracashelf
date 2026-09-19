import Foundation

/// The CLDR plural categories relevant to integer counts (the "many" category's fractional
/// cases don't apply here — we only ever pluralize whole numbers of files).
enum PluralCategory: String {
    case one, few, many, other
}

/// Implements each supported language's plural rules for integers, per Unicode CLDR
/// (https://cldr.unicode.org/index/cldr-spec/plural-rules). English/German only distinguish
/// one vs. other; Russian/Ukrainian share the same three-category Slavic rule; Polish and
/// Czech each have their own variant.
enum Pluralizer {
    static func category(for n: Int, language: AppLanguage) -> PluralCategory {
        let i = abs(n)
        switch language {
        case .en, .de:
            return i == 1 ? .one : .other

        case .ru, .uk:
            let mod10 = i % 10, mod100 = i % 100
            if mod10 == 1 && mod100 != 11 { return .one }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return .few }
            if mod10 == 0 || (5...9).contains(mod10) || (11...14).contains(mod100) { return .many }
            return .other

        case .pl:
            let mod10 = i % 10, mod100 = i % 100
            if i == 1 { return .one }
            if (2...4).contains(mod10) && !(12...14).contains(mod100) { return .few }
            return .many

        case .cs:
            if i == 1 { return .one }
            if (2...4).contains(i) { return .few }
            return .other
        }
    }
}
