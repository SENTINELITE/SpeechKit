import SpeechKit

/// Demo display helpers for SpeechKit realtime lifecycle state.
extension SpeechRealtimeConnectionState {
    /// Whether the state owns or is transitioning an active realtime audio session.
    var isWorking: Bool {
        switch self {
        case .connecting, .connected, .listening, .stopping:
            return true
        case .disconnected, .error:
            return false
        }
    }

    /// A compact status title suitable for demo controls.
    var title: String {
        switch self {
        case .disconnected: "Realtime ready"
        case .connecting: "Connecting"
        case .connected: "Connected"
        case .listening: "Listening"
        case .stopping: "Stopping"
        case .error: "Realtime error"
        }
    }

    /// A provider-relative status sentence suitable for explanatory sample UI.
    var subtitle: String {
        switch self {
        case .disconnected: "is ready."
        case .connecting: "is opening a session."
        case .connected: "is connected."
        case .listening: "is streaming transcript text."
        case .stopping: "is stopping."
        case .error(let message): "failed: \(message)"
        }
    }
}
