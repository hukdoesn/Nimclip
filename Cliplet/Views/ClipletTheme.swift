import AppKit
import SwiftUI

extension NimclipAppearanceMode {
    var colorScheme: ColorScheme {
        self == .dark ? .dark : .light
    }
}

extension Color {
    static let clipletCanvas = Color(nsColor: .windowBackgroundColor)
    static let clipletSurface = Color(nsColor: .controlBackgroundColor)
    static let clipletBorder = Color(nsColor: .separatorColor)
    static let clipletControlFill = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.24, alpha: 1)
                : NSColor(calibratedWhite: 0.96, alpha: 1)
        }
    )
    static let clipletControlHover = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.29, alpha: 1)
                : NSColor(calibratedWhite: 0.91, alpha: 1)
        }
    )
    static let clipletControlPressed = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.34, alpha: 1)
                : NSColor(calibratedWhite: 0.85, alpha: 1)
        }
    )
    static let clipletControlBorder = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.62, alpha: 0.62)
                : NSColor(calibratedWhite: 0.28, alpha: 0.48)
        }
    )
    static let clipletKeycapFill = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.34, alpha: 1)
                : NSColor.white
        }
    )
    static let clipletKeycapBorder = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.78, alpha: 0.58)
                : NSColor(calibratedWhite: 0.25, alpha: 0.48)
        }
    )
    static let clipletHover = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.20, alpha: 1)
                : NSColor(calibratedWhite: 0.885, alpha: 1)
        }
    )
    static let clipletSelection = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.82, alpha: 1)
                : NSColor(calibratedWhite: 0.25, alpha: 1)
        }
    )
    static let clipletSelectionForeground = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.10, alpha: 1)
                : NSColor.white
        }
    )
    static let clipletSettingsSurface = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.205, alpha: 1)
                : NSColor(calibratedWhite: 0.985, alpha: 1)
        }
    )
    static let clipletSidebar = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(calibratedWhite: 0.145, alpha: 1)
                : NSColor(calibratedWhite: 0.945, alpha: 1)
        }
    )
    static let clipletFavorite = Color(
        nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? NSColor(red: 0.95, green: 0.72, blue: 0.29, alpha: 1)
                : NSColor(red: 0.63, green: 0.39, blue: 0.04, alpha: 1)
        }
    )
    static let clipletFavoriteDark = Color(red: 0.63, green: 0.39, blue: 0.04)
    static let clipletFavoriteBright = Color(red: 0.95, green: 0.72, blue: 0.29)

    init(clipletHex: String) {
        let cleaned = clipletHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(cleaned, radix: 16) ?? 0x2F343A
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
