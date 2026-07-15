import Foundation

enum NimclipBuildInfo {
    static let version = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "开发构建"
}

struct NimclipAvailableUpdate: Equatable, Sendable {
    let version: String
    let releaseURL: URL
}

enum NimclipUpdateCheckError: LocalizedError {
    case invalidResponse
    case requestFailed(statusCode: Int)

    var errorDescription: String? {
        errorDescription(in: .defaultLanguage)
    }

    func errorDescription(in language: NimclipLanguage) -> String {
        switch self {
        case .invalidResponse:
            return language.localized("暂时无法读取版本信息。")
        case .requestFailed:
            return language.localized("暂时无法连接到更新服务。")
        }
    }
}

struct NimclipUpdateChecker {
    static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/hukdoesn/Nimclip/releases/latest"
    )!

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func check(
        currentVersion: String = NimclipBuildInfo.version
    ) async throws -> NimclipAvailableUpdate? {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Nimclip/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NimclipUpdateCheckError.invalidResponse
        }
        guard httpResponse.statusCode == 200 else {
            throw NimclipUpdateCheckError.requestFailed(
                statusCode: httpResponse.statusCode
            )
        }
        return try Self.availableUpdate(from: data, currentVersion: currentVersion)
    }

    static func availableUpdate(
        from data: Data,
        currentVersion: String
    ) throws -> NimclipAvailableUpdate? {
        let release: LatestReleaseResponse
        do {
            release = try JSONDecoder().decode(LatestReleaseResponse.self, from: data)
        } catch {
            throw NimclipUpdateCheckError.invalidResponse
        }

        guard !release.draft,
              !release.prerelease,
              isVersion(release.tagName, newerThan: currentVersion) else {
            return nil
        }

        return NimclipAvailableUpdate(
            version: normalizedVersion(release.tagName),
            releaseURL: release.htmlURL
        )
    }

    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        guard let candidateVersion = ParsedVersion(candidate),
              let currentVersion = ParsedVersion(current) else {
            return false
        }
        return candidateVersion > currentVersion
    }

    private static func normalizedVersion(_ version: String) -> String {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("v") {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private struct LatestReleaseResponse: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    private struct ParsedVersion: Comparable {
        private let components: [Int]
        private let prerelease: [Identifier]?

        init?(_ rawValue: String) {
            var value = NimclipUpdateChecker.normalizedVersion(rawValue)
            value = String(value.split(separator: "+", maxSplits: 1)[0])

            let parts = value.split(
                separator: "-",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            let numberParts = parts[0].split(
                separator: ".",
                omittingEmptySubsequences: false
            )
            guard !numberParts.isEmpty else { return nil }

            var parsedComponents: [Int] = []
            parsedComponents.reserveCapacity(numberParts.count)
            for part in numberParts {
                guard let number = Int(part), number >= 0 else { return nil }
                parsedComponents.append(number)
            }
            while parsedComponents.last == 0, parsedComponents.count > 1 {
                parsedComponents.removeLast()
            }
            components = parsedComponents

            if parts.count == 2, !parts[1].isEmpty {
                prerelease = parts[1].split(separator: ".").map(Identifier.init)
            } else {
                prerelease = nil
            }
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            let count = max(lhs.components.count, rhs.components.count)
            for index in 0..<count {
                let left = index < lhs.components.count ? lhs.components[index] : 0
                let right = index < rhs.components.count ? rhs.components[index] : 0
                if left != right { return left < right }
            }

            switch (lhs.prerelease, rhs.prerelease) {
            case (nil, nil):
                return false
            case (.some, nil):
                return true
            case (nil, .some):
                return false
            case let (.some(left), .some(right)):
                let identifierCount = max(left.count, right.count)
                for index in 0..<identifierCount {
                    guard index < left.count else { return true }
                    guard index < right.count else { return false }
                    if left[index] != right[index] {
                        return left[index] < right[index]
                    }
                }
                return false
            }
        }

        private enum Identifier: Comparable {
            case number(Int)
            case text(String)

            init(_ value: Substring) {
                if let number = Int(value) {
                    self = .number(number)
                } else {
                    self = .text(String(value).lowercased())
                }
            }

            static func < (lhs: Self, rhs: Self) -> Bool {
                switch (lhs, rhs) {
                case let (.number(left), .number(right)):
                    return left < right
                case (.number, .text):
                    return true
                case (.text, .number):
                    return false
                case let (.text(left), .text(right)):
                    return left < right
                }
            }
        }
    }
}

extension Notification.Name {
    static let nimclipCheckForUpdatesRequested = Notification.Name(
        "NimclipCheckForUpdatesRequested"
    )
}
