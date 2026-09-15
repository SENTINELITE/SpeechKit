@preconcurrency import AVFoundation
import Foundation

#if !os(watchOS)
import Speech

/// A local file transcription client backed by Apple's Speech framework.
///
/// This client is intentionally API-key free. It validates Apple Speech
/// availability, resolves the configured locale to one Apple supports, prepares
/// local speech assets, then analyzes an `AVAudioFile` through `SpeechAnalyzer`.
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
public struct AppleSpeechFileTranscriptionClient: Sendable {
    /// Creates an Apple local file transcription client.
    public init() {}

    /// Transcribes an audio file and returns plain transcript text.
    ///
    /// - Parameters:
    ///   - file: A local audio file URL readable by `AVAudioFile`.
    ///   - configuration: The Apple Speech defaults to use for this request.
    ///   - options: Per-request overrides for locale and asset handling.
    /// - Returns: The final transcript text assembled in audio-time order.
    public func transcribeAudioFile(
        file: URL,
        configuration: AppleSpeechConfiguration,
        options: AppleSpeechFileTranscriptionOptions? = nil
    ) async throws -> String {
        try await transcribeAudioFileDetailed(
            file: file,
            configuration: configuration,
            options: options
        ).text
    }

    /// Transcribes an audio file and returns normalized Apple result metadata.
    ///
    /// - Parameters:
    ///   - file: A local audio file URL readable by `AVAudioFile`.
    ///   - configuration: The Apple Speech defaults to use for this request.
    ///   - options: Per-request overrides for locale and asset handling.
    /// - Returns: A detailed response containing final transcript entries.
    public func transcribeAudioFileDetailed(
        file: URL,
        configuration: AppleSpeechConfiguration,
        options: AppleSpeechFileTranscriptionOptions? = nil
    ) async throws -> AppleSpeechFileTranscriptionResponse {
        let resolved = try await AppleSpeechSupport.makeFileTranscriber(
            configuration: configuration,
            options: options
        )
        let transcriber = resolved.transcriber
        let audioFile = try AVAudioFile(forReading: file)
        let analyzer = SpeechAnalyzer(
            modules: [transcriber],
            options: AppleSpeechSupport.analyzerOptions(from: configuration.modelRetention)
        )

        try await analyzer.setContext(AppleSpeechSupport.analysisContext(from: configuration))
        try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)

        let resultTask = Task {
            var entriesByID: [String: SpeechTranscriptEntry] = [:]
            for try await result in transcriber.results {
                guard result.isFinal, let entry = AppleSpeechSupport.makeEntry(from: result, locale: resolved.locale) else {
                    continue
                }
                entriesByID[entry.sourceID ?? entry.id.uuidString] = entry
            }
            return entriesByID.values.sorted(by: AppleSpeechSupport.sortsBefore)
        }

        do {
            if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            let entries = try await resultTask.value
            let text = entries.map(\.text).joined(separator: " ")
            return AppleSpeechFileTranscriptionResponse(
                locale: resolved.locale,
                text: text,
                entries: entries
            )
        } catch {
            resultTask.cancel()
            await analyzer.cancelAndFinishNow()
            throw error
        }
    }
}
#endif
