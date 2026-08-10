import SwiftUI

/// Presentation tone only — screens map domain state to a tone + label.
enum SemanticTone: Equatable {
    case neutral
    case info
    case success
    case warning
    case danger

    var color: Color {
        switch self {
        case .neutral: return Color.secondary
        case .info: return Color.accentColor
        case .success: return Color.green
        case .warning: return Color.orange
        case .danger: return Color.red
        }
    }

    var fillOpacity: Double {
        switch self {
        case .neutral: return 0.12
        case .info: return 0.12
        case .success: return 0.14
        case .warning: return 0.16
        case .danger: return 0.14
        }
    }
}

extension SemanticTone {
    /// Map common dictionary / vocabulary status strings.
    static func forStatus(_ status: String) -> SemanticTone {
        switch status.lowercased() {
        case "active", "final", "completed", "granted": return .success
        case "suggested", "draft", "paused", "queued": return .warning
        case "reviewed", "running": return .info
        case "failed", "disabled", "cancelled", "denied": return .danger
        default: return .neutral
        }
    }
}
