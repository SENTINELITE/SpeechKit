@preconcurrency import AVFoundation
import Foundation

#if !os(watchOS)
import Speech

/// Realtime microphone transcription backed by Apple's local Speech framework.
///
/// `AppleSpeechService` mirrors the lifecycle shape of SpeechKit's network
/// realtime services, but it keeps all work on device through `SpeechAnalyzer`
/// and `SpeechTranscriber`. The service stores volatile Apple results as a
/// single partial entry and upserts final results by audio time range to avoid
/// duplicating text when Apple revises a volatile segment.
@Observable
@MainActor
@available(iOS 26.0, macOS 26.0, visionOS 26.0, *)
@available(watchOS, unavailable)
final class AppleSpeechService {
    /// The current Apple local realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest volatile transcript entry from Apple Speech.
    public private(set) var partialTranscriptEntry: SpeechTranscriptEntry?
    /// Final transcript entries from Apple Speech, sorted by audio start time.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// The most recent realtime error from Apple Speech.
    public private(set) var lastError: Error?

    /// The Apple local Speech configuration used by ``startListening(configuration:)``.
    var configuration = AppleSpeechConfiguration()

    private let audioManager = AppleSpeechAudioCaptureManager()
    private var analyzer: SpeechAnalyzer?
    private var resultTask: Task<Void, Never>?
    private var analysisTask: Task<Void, Never>?
    private var committedEntriesByID: [String: SpeechTranscriptEntry] = [:]
    private var partialEntryID: String?
    private var runID: UUID?

    /// The latest normalized microphone input level.
    var realtimeAudioLevel: Double {
        audioManager.currentLevel
    }

    /// Recording retention after a session stops. The default preserves export after stop.
    public var recordingRetention: SpeechRecordingRetention {
        get { audioManager.recordingRetention }
        set { audioManager.recordingRetention = newValue }
    }

    /// The latest realtime microphone recording as WAV data, if capture has produced audio.
    var realtimeRecordingData: Data? {
        audioManager.recordedWAVData
    }

    /// The latest volatile transcript text from Apple Speech.
    var partialTranscriptText: String {
        partialTranscriptEntry?.text ?? ""
    }

    /// Starts Apple local realtime microphone transcription.
    ///
    /// - Parameter configuration: The Apple Speech configuration to use for the
    ///   local analysis session.
    func startListening(configuration: AppleSpeechConfiguration) async {
        guard !connectionState.isLifecycleActive else { return }

        self.configuration = configuration
        connectionState = .connecting
        lastError = nil
        partialTranscriptEntry = nil
        partialEntryID = nil
        committedEntriesByID.removeAll()
        transcriptEntries.removeAll()

        let currentRunID = UUID()
        runID = currentRunID
        defer {
            if runID == currentRunID, Task.isCancelled { invalidateConfiguration() }
        }

        do {
            let resolved = try await AppleSpeechSupport.makeRealtimeTranscriber(configuration: configuration)
            guard runID == currentRunID, !Task.isCancelled else { return }
            let transcriber = resolved.transcriber
            let modules: [any SpeechModule] = [transcriber]
            let analyzer = SpeechAnalyzer(
                modules: modules,
                options: AppleSpeechSupport.analyzerOptions(from: configuration.modelRetention)
            )
            let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules)
            guard runID == currentRunID, !Task.isCancelled else { return }
            try await analyzer.setContext(AppleSpeechSupport.analysisContext(from: configuration))
            guard runID == currentRunID, !Task.isCancelled else { return }
            try await analyzer.prepareToAnalyze(in: targetFormat)

            guard runID == currentRunID, !Task.isCancelled else { return }
            guard await audioManager.requestPermission() else {
                throw SpeechAudioCaptureError.permissionDenied
            }

            guard runID == currentRunID, !Task.isCancelled else { return }
            let inputStream = try audioManager.startCapture(targetFormat: targetFormat)
            self.analyzer = analyzer

            resultTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    for try await result in transcriber.results {
                        await self?.handle(result, locale: resolved.locale, runID: currentRunID)
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await self?.handleRealtimeError(error, runID: currentRunID)
                }
            }

            analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
                do {
                    _ = try await analyzer.analyzeSequence(inputStream)
                } catch is CancellationError {
                    return
                } catch {
                    await self?.handleRealtimeError(error, runID: currentRunID)
                }
            }

            connectionState = .listening
        } catch {
            guard runID == currentRunID, !Task.isCancelled else { return }
            await stopInternal(cancelAnalysis: true)
            connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            lastError = SpeechErrorBoundary.safe(error)
        }
    }

    /// Stops Apple local realtime transcription and finalizes pending audio.
    func stopListening() async {
        if connectionState == .connecting { runID = nil }
        guard connectionState.isLifecycleActive else { return }
        connectionState = .stopping
        audioManager.stopCapture()

        do {
            try await analyzer?.finalizeAndFinishThroughEndOfInput()
            await analysisTask?.value
            await resultTask?.value
            connectionState = .disconnected
        } catch {
            await stopInternal(cancelAnalysis: true)
            connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
            lastError = SpeechErrorBoundary.safe(error)
        }

        await stopInternal(cancelAnalysis: false)
    }

    /// Clears committed and volatile Apple transcript text.
    func discardRecording() { audioManager.discardRecording() }

    func clearTranscript() {
        partialTranscriptEntry = nil
        partialEntryID = nil
        committedEntriesByID.removeAll()
        transcriptEntries.removeAll()
    }

    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    private func handle(
        _ result: SpeechTranscriber.Result,
        locale: Locale,
        runID: UUID
    ) {
        guard runID == self.runID, let entry = AppleSpeechSupport.makeEntry(from: result, locale: locale) else {
            return
        }

        let sourceID = entry.sourceID ?? entry.id.uuidString
        if result.isFinal {
            if partialEntryID == sourceID {
                partialTranscriptEntry = nil
                partialEntryID = nil
            }
            committedEntriesByID[sourceID] = entry
            transcriptEntries = committedEntriesByID.values.sorted(by: AppleSpeechSupport.sortsBefore)
        } else {
            partialEntryID = sourceID
            partialTranscriptEntry = entry
        }
    }

    private func handleRealtimeError(_ error: Error, runID: UUID) {
        guard runID == self.runID, connectionState.isLifecycleActive else { return }
        lastError = SpeechErrorBoundary.safe(error)
        connectionState = .error(SpeechErrorBoundary.safe(error).localizedDescription)
    }

    func invalidateConfiguration() {
        runID = nil
        audioManager.stopCapture()
        resultTask?.cancel()
        resultTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        let previous = analyzer
        analyzer = nil
        connectionState = .disconnected
        lastError = nil
        Task { await previous?.cancelAndFinishNow() }
    }

    private func stopInternal(cancelAnalysis: Bool) async {
        let analyzer = analyzer
        self.analyzer = nil
        audioManager.stopCapture()
        resultTask?.cancel()
        resultTask = nil
        analysisTask?.cancel()
        analysisTask = nil
        runID = nil
        if cancelAnalysis {
            await analyzer?.cancelAndFinishNow()
        }
    }
}
#endif
