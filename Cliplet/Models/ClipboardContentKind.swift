import Foundation

enum ClipboardContentKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text
    case image

    var id: String { rawValue }
}

enum ClipboardPresentationKind: String, CaseIterable, Identifiable, Sendable {
    case text
    case link
    case code
    case image

    var id: String { rawValue }

    var title: String {
        title(in: .defaultLanguage)
    }

    func title(in language: NimclipLanguage) -> String {
        switch self {
        case .text: language.localized("文本")
        case .link: language.localized("链接")
        case .code: language.localized("代码")
        case .image: language.localized("图片")
        }
    }

    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .image: "photo"
        }
    }

    static func classify(kind: ClipboardContentKind, text: String?) -> Self {
        guard kind == .text else { return .image }
        guard let text else { return .text }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .text }
        if isLink(trimmed) { return .link }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    private static func isLink(_ text: String) -> Bool {
        guard !text.contains(where: { $0.isWhitespace }) else { return false }

        let lowercased = text.lowercased()
        if lowercased.hasPrefix("www.") {
            return URL(string: "https://\(text)")?.host != nil
        }

        guard let components = URLComponents(string: text),
              let scheme = components.scheme?.lowercased() else {
            return false
        }
        switch scheme {
        case "http", "https", "ftp":
            return components.host != nil
        case "mailto", "tel":
            return !components.path.isEmpty
        default:
            return false
        }
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        let commandPrefixes = [
            "brew ", "cargo ", "curl ", "docker ", "git ", "go ", "kubectl ",
            "npm ", "npx ", "pip ", "pnpm ", "python ", "swift ", "yarn "
        ]
        if commandPrefixes.contains(where: lowercased.hasPrefix) {
            return true
        }

        let syntaxMarkers = [
            "func ", "class ", "struct ", "enum ", "import ", "const ", "let ",
            "var ", "return ", "select ", "from ", "#!/", "</", "=>", "::"
        ]
        let markerMatches = syntaxMarkers.reduce(into: 0) { count, marker in
            if lowercased.contains(marker) { count += 1 }
        }
        if markerMatches >= 2 { return true }

        let hasCodeDelimiters = (text.contains("{") && text.contains("}"))
            || (text.contains("(") && text.contains(")") && text.contains(";"))
        return hasCodeDelimiters && (text.contains("\n") || text.count < 240)
    }
}

enum ClipboardContentFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case text
    case link
    case code
    case image

    var id: String { rawValue }

    var title: String {
        title(in: .defaultLanguage)
    }

    func title(in language: NimclipLanguage) -> String {
        switch self {
        case .all: language.localized("全部")
        case .text: language.localized("文本")
        case .link: language.localized("链接")
        case .code: language.localized("代码")
        case .image: language.localized("图片")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .text: ClipboardPresentationKind.text.systemImage
        case .link: ClipboardPresentationKind.link.systemImage
        case .code: ClipboardPresentationKind.code.systemImage
        case .image: ClipboardPresentationKind.image.systemImage
        }
    }

    func includes(_ kind: ClipboardPresentationKind) -> Bool {
        switch self {
        case .all: true
        case .text: kind == .text
        case .link: kind == .link
        case .code: kind == .code
        case .image: kind == .image
        }
    }
}
