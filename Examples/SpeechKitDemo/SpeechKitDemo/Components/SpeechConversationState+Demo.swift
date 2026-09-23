import SpeechKit

/// Demo display helpers for the SpeechKit speech-to-speech conversation lifecycle.
extension SpeechConversationState {
    /// Whether the state owns or is transitioning an active conversation audio session.
    var isWorking: Bool {
        switch self {
        case .connecting, .active, .ending:
            return true
        case .idle, .ended, .error:
            return false
        }
    }

    /// A compact status title suitable for demo controls.
    var title: String {
        switch self {
        case .idle: "Conversation ready"
        case .connecting: "Connecting"
        case .active: "Live"
        case .ending: "Ending"
        case .ended: "Session ended"
        case .error: "Conversation error"
        }
    }

    /// A provider-relative status sentence suitable for explanatory sample UI.
    var subtitle: String {
        switch self {
        case .idle: "is ready."
        case .connecting: "is opening a session."
        case .active(let sessionID): "is live in session \(sessionID)."
        case .ending: "is closing the session."
        case .ended(let reason, let seconds): Self.endedSubtitle(reason: reason, seconds: seconds)
        case .error(let message): "failed: \(message)"
        }
    }

    /// Builds the ended-session sentence, including billed seconds when the provider reported them.
    private static func endedSubtitle(reason: SpeechConversationEndReason, seconds: Double?) -> String {
        guard let seconds else {
            return "ended (\(reason.rawValue))."
        }
        return "ended (\(reason.rawValue)) after \(Int(seconds.rounded()))s of audio."
    }
}
