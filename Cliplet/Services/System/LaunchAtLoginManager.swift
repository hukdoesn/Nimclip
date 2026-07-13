import Foundation
import ServiceManagement

public enum LaunchAtLoginStatus: Equatable, Sendable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

public enum LaunchAtLoginError: LocalizedError {
    case registrationFailed(Error)
    case unregistrationFailed(Error)

    public var errorDescription: String? {
        switch self {
        case let .registrationFailed(error):
            return "Launch at login could not be enabled: \(error.localizedDescription)"
        case let .unregistrationFailed(error):
            return "Launch at login could not be disabled: \(error.localizedDescription)"
        }
    }
}

@MainActor
public final class LaunchAtLoginManager {
    private let service: SMAppService

    public init(service: SMAppService = .mainApp) {
        self.service = service
    }

    public var status: LaunchAtLoginStatus {
        switch service.status {
        case .enabled:
            return .enabled
        case .notRegistered:
            return .disabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        if isEnabled {
            guard service.status != .enabled else { return }
            do {
                try service.register()
            } catch {
                throw LaunchAtLoginError.registrationFailed(error)
            }
        } else {
            guard service.status != .notRegistered else { return }
            do {
                try service.unregister()
            } catch {
                throw LaunchAtLoginError.unregistrationFailed(error)
            }
        }
    }

    @discardableResult
    public func openSystemSettings() -> Bool {
        SMAppService.openSystemSettingsLoginItems()
        return true
    }
}
