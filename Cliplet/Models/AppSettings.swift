import Foundation
import SwiftData

@Model
final class AppSettings {
    static let defaultHistoryLimit = 500
    static let defaultRetentionDays = 7
    static let legacyDefaultRetentionDays = 30

    @Attribute(.unique) var id: UUID
    var historyLimit: Int
    var retentionDays: Int
    var hotKeyKeyCode: UInt32
    var hotKeyModifiers: UInt32
    var launchAtLogin: Bool
    var appearanceModeRawValue: String = "dark"
    var hasExplicitAppearanceSelection: Bool = false
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        historyLimit: Int = AppSettings.defaultHistoryLimit,
        retentionDays: Int = AppSettings.defaultRetentionDays,
        hotKeyKeyCode: UInt32 = 9,
        hotKeyModifiers: UInt32 = 768,
        launchAtLogin: Bool = false,
        appearanceMode: NimclipAppearanceMode = .defaultMode,
        hasExplicitAppearanceSelection: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.historyLimit = historyLimit
        self.retentionDays = retentionDays
        self.hotKeyKeyCode = hotKeyKeyCode
        self.hotKeyModifiers = hotKeyModifiers
        self.launchAtLogin = launchAtLogin
        self.appearanceModeRawValue = appearanceMode.rawValue
        self.hasExplicitAppearanceSelection = hasExplicitAppearanceSelection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
