import Foundation

#if !os(watchOS)
/// A detailed Apple local file transcription response.
///
/// The provider-neutral file transcription API returns only text. Use
/// ``SpeechService/transcribeAppleAudioFile(file:options:)`` when your app also
/// needs Apple's segment timing, finalization state, or word-level metadata.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AppleSpeechFileTranscriptionResponse: Sendable, Equatable {
    /// The locale Apple selected for the transcription session.
    public let locale: Locale
    /// The full transcript text assembled from final Apple transcription results.
    public let text: String
    /// Final transcript entries normalized into SpeechKit's shared entry model.
    public let entries: [SpeechTranscriptEntry]

    /// Creates a detailed Apple local file transcription response.
    public init(
        locale: Locale,
        text: String,
        entries: [SpeechTranscriptEntry]
    ) {
        self.locale = locale
        self.text = text
        self.entries = entries
    }
}
#endif
