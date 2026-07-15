import Foundation

private final class NimclipLocalizationBundleToken: NSObject {}

enum NimclipLanguage: String, CaseIterable, Codable, Identifiable, Sendable {
    case simplifiedChinese = "zh-Hans"
    case english = "en"

    static let defaultLanguage: Self = .simplifiedChinese

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    private static let localizationBundle: Bundle = {
        let candidates = [Bundle.main, Bundle(for: NimclipLocalizationBundleToken.self)]
            + Bundle.allBundles

        return candidates.first { bundle in
            bundle.bundleIdentifier == "com.nimclip.app"
                && bundle.url(forResource: NimclipLanguage.english.rawValue, withExtension: "lproj") != nil
        } ?? candidates.first { bundle in
            bundle.url(forResource: NimclipLanguage.english.rawValue, withExtension: "lproj") != nil
        } ?? .main
    }()

    func localized(_ key: String) -> String {
        guard self != .simplifiedChinese,
              let localizationURL = Self.localizationBundle.url(
                  forResource: rawValue,
                  withExtension: "lproj"
              ),
              let languageBundle = Bundle(url: localizationURL) else {
            return key
        }

        return languageBundle.localizedString(
            forKey: key,
            value: key,
            table: "Localizable"
        )
    }

    func localizedFormat(_ key: String, _ arguments: CVarArg...) -> String {
        String(
            format: localized(key),
            locale: locale,
            arguments: arguments
        )
    }
}
