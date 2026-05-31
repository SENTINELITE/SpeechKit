import Foundation
import SwiftUI

/// A SwiftUI-observable OpenAI realtime transcription service.
@Observable
@MainActor
public final class OpenAIRealtimeService {
    /// The current realtime connection state.
    public private(set) var connectionState: SpeechRealtimeConnectionState = .disconnected
    /// The latest partial transcript text.
    public private(set) var partialTranscriptText: String = ""
    /// The committed transcript entries.
    public private(set) var transcriptEntries: [SpeechTranscriptEntry] = []
    /// The most recent realtime error, if any.
    public private(set) var lastError: Error?

    /// The OpenAI API key used for realtime transcription.
    public var apiKey: String
    /// Options for the OpenAI realtime transcription session.
    public var options: OpenAIRealtimeSessionOptions

    private let audioManager = AudioCaptureManager(targetSampleRate: 24000)
    private let webSocket = OpenAIRealtimeWebSocket()
    private var listeningTask: Task<Void, Never>?
    private var partialsByItemID: [String: String] = [:]
    private var commitTask: Task<Void, Never>?
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

    /// Creates an OpenAI realtime transcription service.
    public init(apiKey: String = "", options: OpenAIRealtimeSessionOptions = OpenAIRealtimeSessionOptions()) {
        self.apiKey = apiKey
        self.options = options
    }

    /// Starts realtime microphone transcription.
    public func startListening() async {
        guard !connectionState.isLifecycleActive else { return }

        guard !apiKey.isEmpty else {
            connectionState = .error("OpenAI is not configured")
            lastError = OpenAIError.apiKeyMissing
            return
        }

        let runID = beginLifecycleRun()
        connectionState = .connecting
        partialTranscriptText = ""
        lastError = nil

        let hasPermission = await audioManager.requestPermission()
        guard isCurrentLifecycleRun(runID) else { return }
        guard hasPermission else {
            connectionState = .error("Microphone permission denied")
            lastError = OpenAIError.permissionDenied
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
                let audioStream = try audioManager.startCapture()
                guard isCurrentLifecycleRun(runID) else {
                    audioManager.stopCapture()
                    await webSocket.disconnect()
                    return
                }
                connectionState = .listening

                let sendTask = Task {
                    await sendAudioChunks(audioStream, runID: runID)
                }
                let commitTask = makeCommitTask(interval: options.commitInterval, runID: runID)
                self.commitTask = commitTask

                for try await message in messageStream {
                    if Task.isCancelled { break }
                    guard isCurrentLifecycleRun(runID) else { break }

                    switch message {
                    case .sessionCreated(let sessionID), .sessionUpdated(let sessionID):
                        if let sessionID, !connectionState.isListening {
                            connectionState = .connected(sessionID: sessionID)
                        }

                    case .transcriptionDelta(let delta):
                        let key = delta.itemID ?? "current"
                        partialsByItemID[key, default: ""] += delta.delta
                        partialTranscriptText = partialsByItemID[key, default: ""]

                    case .transcriptionCompleted(let completed):
                        let text = completed.transcript.isEmpty
                            ? partialsByItemID[completed.itemID ?? "current", default: ""]
                            : completed.transcript
                        if !text.isEmpty {
                            transcriptEntries.append(
                                SpeechTranscriptEntry(
                                    provider: .openAI,
                                    sourceID: completed.itemID,
                                    text: text
                                )
                            )
                            partialsByItemID[completed.itemID ?? "current"] = nil
                            partialTranscriptText = ""
                        }

                    case .error(let message):
                        lastError = OpenAIError.connectionFailed(message)
                        connectionState = .error(message)

                    case .unknown:
                        break
                    }
                }

                sendTask.cancel()
                commitTask?.cancel()
            } catch {
                if !Task.isCancelled, isCurrentLifecycleRun(runID) {
                    lastError = error
                    connectionState = .error(error.localizedDescription)
                }
            }

            await cleanupAfterStop(runID: runID)
        }
    }

    /// Stops realtime microphone transcription and disconnects from OpenAI.
    public func stopListening() async {
        guard connectionState.isLifecycleActive || listeningTask != nil || audioManager.isCapturing else {
            connectionState = .disconnected
            return
        }

        invalidateLifecycleRun()
        connectionState = .stopping
        listeningTask?.cancel()
        listeningTask = nil
        commitTask?.cancel()
        commitTask = nil

        do {
            try await webSocket.commitInputAudioBuffer()
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
        partialsByItemID.removeAll()
    }

    /// Sets lifecycle state for tests that exercise facade orchestration without opening audio devices.
    func setLifecycleStateForTesting(_ state: SpeechRealtimeConnectionState) {
        connectionState = state
    }

    private func sendAudioChunks(_ stream: AsyncStream<Data>, runID: UUID) async {
        for await audioData in stream {
            if Task.isCancelled { break }
            guard isCurrentLifecycleRun(runID) else { break }

            do {
                try await webSocket.send(OpenAIInputAudioBufferAppendMessage(audioData: audioData))
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

    private func makeCommitTask(interval: TimeInterval, runID: UUID) -> Task<Void, Never>? {
        guard interval > 0 else { return nil }

        return Task {
            let nanoseconds = UInt64(interval * 1_000_000_000)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: nanoseconds)
                if Task.isCancelled { break }
                guard await MainActor.run(body: { isCurrentLifecycleRun(runID) }) else { break }
                try? await webSocket.commitInputAudioBuffer()
            }
        }
    }

    private func cleanupAfterStop(runID: UUID) async {
        guard isCurrentLifecycleRun(runID) else { return }
        commitTask?.cancel()
        commitTask = nil
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
