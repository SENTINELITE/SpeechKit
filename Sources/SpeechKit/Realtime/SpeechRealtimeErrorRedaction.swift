import Foundation

/// Discards all untrusted payloads at the observable error boundary.
enum SpeechRealtimeErrorRedaction {
    static func redacted(_ error: Error) -> Error { SpeechErrorBoundary.safe(error) }
    static func redactedDescription(_ error: Error) -> String { SpeechErrorBoundary.safe(error).localizedDescription }
}
