import Foundation
import SwiftData

@Model
final class AppSettings {
    static let defaultHistoryLimit = 500
    static let defaultRetentionDays = 2
    static let previousDefaultRetentionDays = 7
    static let legacyDefaultRetentionDays = 30
    static let earlierDefaultRetentionDays = [
        previousDefaultRetentionDays,
        legacyDefaultRetentionDays
    ]

    @Attribute(.unique) var id: UUID
    var historyLimit: Int
    var retentionDays: Int
    var hotKeyKeyCode: UInt32
    var hotKeyModifiers: UInt32
    var launchAtLogin: Bool
    var appearanceModeRawValue: String = "dark"
    var hasExplicitAppearanceSelection: Bool = false
    var languageRawValue: String = NimclipLanguage.defaultLanguage.rawValue
    var automaticImageTextRecognitionValue: Bool?
    var automaticUpdateChecksEnabledValue: Bool?
    var createdAt: Date
    var updatedAt: Date

    var automaticImageTextRecognition: Bool {
        get { automaticImageTextRecognitionValue ?? true }
        set { automaticImageTextRecognitionValue = newValue }
    }

    var automaticUpdateChecksEnabled: Bool {
        get { automaticUpdateChecksEnabledValue ?? true }
        set { automaticUpdateChecksEnabledValue = newValue }
    }

    init(
        id: UUID = UUID(),
        historyLimit: Int = AppSettings.defaultHistoryLimit,
        retentionDays: Int = AppSettings.defaultRetentionDays,
        hotKeyKeyCode: UInt32 = 9,
        hotKeyModifiers: UInt32 = 768,
        launchAtLogin: Bool = false,
        appearanceMode: NimclipAppearanceMode = .defaultMode,
        hasExplicitAppearanceSelection: Bool = false,
        language: NimclipLanguage = .defaultLanguage,
        automaticImageTextRecognition: Bool = true,
        automaticUpdateChecksEnabled: Bool = true,
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
        self.languageRawValue = language.rawValue
        self.automaticImageTextRecognitionValue = automaticImageTextRecognition
        self.automaticUpdateChecksEnabledValue = automaticUpdateChecksEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
