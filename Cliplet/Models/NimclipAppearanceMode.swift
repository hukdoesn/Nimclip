import AppKit

enum NimclipAppearanceMode: String, CaseIterable, Codable, Identifiable {
    case light
    case dark

    static let defaultMode: Self = .dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .light:
            return "浅色"
        case .dark:
            return "深色"
        }
    }

    var detail: String {
        switch self {
        case .light:
            return "始终明亮"
        case .dark:
            return "始终深色"
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
