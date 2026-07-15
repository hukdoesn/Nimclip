import AppKit

enum NimclipAppearanceMode: String, CaseIterable, Codable, Identifiable {
    case light
    case dark

    static let defaultMode: Self = .dark

    @MainActor
    static var currentSystemMode: Self {
        resolvedSystemMode(from: NSApplication.shared.effectiveAppearance)
    }

    static func resolvedSystemMode(from appearance: NSAppearance) -> Self {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? .dark
            : .light
    }

    var id: String { rawValue }

    var title: String {
        title(in: .defaultLanguage)
    }

    func title(in language: NimclipLanguage) -> String {
        switch self {
        case .light:
            return language.localized("浅色")
        case .dark:
            return language.localized("深色")
        }
    }

    var detail: String {
        detail(in: .defaultLanguage)
    }

    func detail(in language: NimclipLanguage) -> String {
        switch self {
        case .light:
            return language.localized("始终明亮")
        case .dark:
            return language.localized("始终深色")
        }
    }

    var systemImage: String {
        switch self {
        case .light:
            return "sun.max.fill"
        case .dark:
            return "moon.stars.fill"
        }
    }

    var opposite: Self {
        self == .light ? .dark : .light
    }

    var appearance: NSAppearance {
        let name: NSAppearance.Name = self == .light ? .aqua : .darkAqua
        return NSAppearance(named: name) ?? NSAppearance(named: .aqua)!
    }
}
