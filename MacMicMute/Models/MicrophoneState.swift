import Foundation

enum MicrophoneState: Equatable {
    case muted
    case unmuted
    case unavailable

    var isMuted: Bool? {
        switch self {
        case .muted: true
        case .unmuted: false
        case .unavailable: nil
        }
    }

    var statusTitle: String {
        switch self {
        case .muted: "Microphone: MUTED"
        case .unmuted: "Microphone: ON"
        case .unavailable: "Microphone: UNAVAILABLE"
        }
    }

    var symbolName: String {
        switch self {
        case .muted, .unavailable: "mic.slash.fill"
        case .unmuted: "mic.fill"
        }
    }
}
