import Foundation
import SwiftData

@Model
final class ClipTag {
    @Attribute(.unique) var id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date
    var items: [ClipboardItem]

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String = "2F343A",
        createdAt: Date = Date(),
        items: [ClipboardItem] = []
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.items = items
    }
}
