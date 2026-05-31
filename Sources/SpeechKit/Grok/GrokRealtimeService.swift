import Foundation
import SwiftUI

/// A SwiftUI-observable Grok realtime transcription service.
@Observable
@MainActor
public final class GrokRealtimeService {
    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscriptText: String = ""
    /// The latest partial transcript entry.
    public private(set) var partialTranscriptEntry: SpeechTranscriptEntry?
    /// The committed transcript entries.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// The most recent realtime error, if any.
    public private(set) var lastError: Error?

    /// The Grok API key used for realtime transcription.
    public var apiKey: String
    /// Options for the Grok realtime transcription session.
    public var options: GrokRealtimeOptions {
        didSet {
            audioManager.setTargetSampleRate(Double(options.sampleRate))
        }
    }

    private let audioManager: AudioCaptureManager
    private let webSocket = GrokRealtimeWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var committedFingerprints: Set<String> = []
    private var lifecycleRunID = UUID()

    /// The committed transcript text joined with spaces.
    public var transcriptText: String {
        transcriptEntries.map(\.text).joined(separator: " ")
    }

    /// The latest normalized microphone input level for the active realtime capture.
    public var realtimeAudioLevel: Double {
        audioManager.currentLevel
    }

    /// The latest realtime microphone recording as WAV data, if capture has produced audio.
    public var realtimeRecordingData: Data? {
        audioManager.recordedWAVData
    }

    /// Creates a Grok realtime transcription service.
    public init(apiKey: String = "", options: GrokRealtimeOptions = GrokRealtimeOptions()) {
        self.apiKey = apiKey
        self.options = options
        self.audioManager = AudioCaptureManager(targetSampleRate: Double(options.sampleRate))
    }

    /// Starts realtime microphone transcription.
    public func startListening() async {
        guard !connectionState.isLifecycleActive else { return }

        guard !apiKey.isEmpty else {
            connectionState = .error("Grok is not configured")
            lastError = GrokRealtimeError.apiKeyMissing
            return
        }

        do {
            try options.validate()
        } catch {
            connectionState = .error(error.localizedDescription)
            lastError = error
            return
        }

        let runID = beginLifecycleRun()
        connectionState = .connecting
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        lastError = nil

        let hasPermission = await audioManager.requestPermission()
        guard isCurrentLifecycleRun(runID) else { return }
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = SpeechAudioCaptureError.permissionDenied
            return
        }

        let apiKey = apiKey
        let options = options

        listeningTask = Task {
            do {
                let messageStream = try await webSocket.connect(apiKey: apiKey, options: options)
                guard isCurrentLifecycleRun(runID) else {
                    await webSocket.disconnect()
                    return
                }
                var sendTask: Task<Void, Never>?

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }

                    switch message {
                    case .transcriptCreated(let created):
                        connectionState = .connected(sessionID: created.sessionID ?? "")
                        do {
                            let audioStream = try audioManager.startCapture()
                            connectionState = .listening
                            sendTask = Task {
                                await sendAudioChunks(audioStream, runID: runID)
                            }
                        } catch {
                            if isCurrentLifecycleRun(runID) {
                                lastError = error
                                connectionState = .error("Failed to start audio capture")
                            }
                        }

                    case .transcriptPartial(let transcript):
                        handleTranscript(transcript)

                    case .transcriptDone(let transcript):
                        commitTranscriptIfNeeded(transcript, forceUtteranceFinal: true)
                        partialTranscriptText = ""
                        partialTranscriptEntry = nil

                    case .error(let message):
                        lastError = GrokRealtimeError.connectionFailed(message)
                        connectionState = .error(message)

                    case .unknown:
                        break
                    }
                }

                sendTask?.cancel()
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = error
                    connectionState = .error(error.localizedDescription)
                }
            }

            await cleanupAfterStop(runID: runID)
        }
    }

    /// Stops realtime microphone transcription and disconnects from Grok.
    public func stopListening() async {
        guard connectionState.isLifecycleActive || listeningTask != nil || audioManager.isCapturing else {
            connectionState = .disconnected
            return
        }

        invalidateLifecycleRun()
        connectionState = .stopping
        listeningTask?.cancel()
        listeningTask = nil

        do {
            try await webSocket.sendAudioDone()
        } catch {
            // Ignore errors when stopping.
        }

        await webSocket.disconnect()
        audioManager.stopCapture()
        connectionState = .disconnected
    }

    /// Clears committed and partial realtime transcript text.
    public func clearTranscript() {
        transcriptEntries.removeAll()
        partialTranscriptText = ""
        partialTranscriptEntry = nil
        committedFingerprints.removeAll()
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    private func handleTranscript(_ transcript: GrokTranscript) {
        if transcript.isFinal == true {
            commitTranscriptIfNeeded(transcript, forceUtteranceFinal: false)
            partialTranscriptText = ""
            partialTranscriptEntry = nil
        } else {
            let entry = makeEntry(from: transcript, isFinal: false, isUtteranceFinal: false)
            partialTranscriptEntry = entry
            partialTranscriptText = entry.text
        }
    }

    private func commitTranscriptIfNeeded(_ transcript: GrokTranscript, forceUtteranceFinal: Bool) {
        let entry = makeEntry(
            from: transcript,
            isFinal: true,
            isUtteranceFinal: forceUtteranceFinal || transcript.speechFinal == true
        )
        guard !entry.text.isEmpty else { return }

        let sourceID = entry.sourceID ?? ""
        let start = entry.start.map { String($0) } ?? ""
        let duration = entry.duration.map { String($0) } ?? ""
        let channelIndex = entry.channelIndex.map { String($0) } ?? ""
        let fingerprint = [sourceID, entry.text, start, duration, channelIndex].joined(separator: "|")

        guard !committedFingerprints.contains(fingerprint) else { return }
        committedFingerprints.insert(fingerprint)
        transcriptEntries.append(entry)
    }

    private func makeEntry(
        from transcript: GrokTranscript,
        isFinal: Bool,
        isUtteranceFinal: Bool
    ) -> SpeechTranscriptEntry {
        SpeechTranscriptEntry(
            provider: .grok,
            text: transcript.text,
            start: transcript.start,
            duration: transcript.duration,
            isFinal: isFinal,
            isUtteranceFinal: isUtteranceFinal,
            channelIndex: transcript.channelIndex,
            speaker: transcript.speaker,
            words: transcript.words?.map(SpeechTranscriptWord.init) ?? []
        )
    }

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            do {
                try await webSocket.sendAudio(audioData)
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    await MainActor.run {
                        lastError = error
                    }
                }
                break
            }
        }
    }

    private func cleanupAfterStop(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }
        audioManager.stopCapture()
        await webSocket.disconnect()
        if connectionState.isLifecycleActive {
            connectionState = .disconnected
        }
    }

    private func beginLifecycleRun() -> UUID {
        let runID = UUID()
        lifecycleRunID = runID
        return runID
    }

    private func invalidateLifecycleRun() {
        lifecycleRunID = UUID()
    }

    private func isCurrentLifecycleRun(_ runID: UUID) -> Bool {
        lifecycleRunID == runID
    }
}
