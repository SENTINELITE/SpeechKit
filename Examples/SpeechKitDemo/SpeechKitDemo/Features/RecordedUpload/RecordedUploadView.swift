import SpeechKit
import SpeechKitVoz
import SwiftUI

/// A focused sample for recording local WAV audio and transcribing it with a selected SpeechKit file provider.
struct RecordedUploadView: View {
    @Environment(\.speechService) private var speech

    @Bindable var configuration: DemoConfiguration
    let recorder: DemoAudioRecorder
    let inputPreview: DemoInputPreviewMonitor
    @Binding var presentedTranscript: DemoTranscript?
    @Binding var vozResponse: VozFileTranscriptionResponse?
    @Binding var exportErrorMessage: String?
    let prepareAudioExport: () -> Void

    @State private var isTranscribingDictation = false
    @State private var dictationTranscript: String?
    @State private var dictationError: String?
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var activeRequestID: UUID?

    private var isAudioActive: Bool {
        recorder.isRecording || isTranscribingDictation
    }

    private var voiceLevel: Double {
        isAudioActive ? recorder.currentLevel : inputPreview.currentLevel
    }

    private var voiceState: DemoVoiceState {
        if isAudioActive {
            return .active
        }
        if inputPreview.isPreviewing {
            return .preview
        }
        return .idle
    }

    private var displayedTranscript: String {
        dictationTranscript ?? ""
    }

    private var hasSelectedProviderKey: Bool {
        configuration.hasAPIKey(for: configuration.fileProvider)
    }

    private var hasCompletedRecording: Bool {
        !recorder.isRecording && !isTranscribingDictation && recorder.lastRecordingURL != nil
    }

    private var microphoneIconName: String {
        recorder.isRecording ? "stop.circle.fill" : "record.circle"
    }

    private var primaryControlTitle: String {
        if !canStartRecording && !isAudioActive {
            if configuration.fileProvider == .voz { return "VOZ Model Required" }
            return configuration.isRelayEnabled ? "Relay Authorization Required" : "API Key Required"
        }
        if recorder.isRecording {
            return "Stop Recording"
        }
        if isTranscribingDictation {
            return configuration.fileProvider.isOnDevice ? "Transcribing locally" : "Uploading"
        }
        return "Record"
    }

    private var activeErrorMessage: String? {
        if configuration.fileProvider == .voz && !isVozReady && !isAudioActive {
            return "Download and prepare the VOZ model in Settings before recording local dictation."
        }
        if configuration.fileProvider.requiresAPIKey && !hasSelectedProviderKey && !isAudioActive {
            return configuration.missingAPIKeyMessage(for: configuration.fileProvider)
        }
        return dictationError ?? exportErrorMessage
    }

    var body: some View {
        ZStack {
            DemoBackground(level: voiceLevel, state: voiceState)

            DemoVoiceStage(
                title: configuration.fileProvider.isOnDevice ? "Record, transcribe locally" : "Record, upload, transcribe",
                providerTitle: configuration.fileProvider.title,
                iconName: microphoneIconName,
                voiceLevel: voiceLevel,
                voiceState: voiceState,
                actionTitle: primaryControlTitle,
                isActionDisabled: isTranscribingDictation || (!isAudioActive && !canStartRecording),
                action: {
                    Task {
                        await handleMicrophoneTap()
                    }
                }
            )

            DemoControlDock(
                primaryTitle: primaryControlTitle,
                primaryIcon: microphoneIconName,
                transcript: displayedTranscript,
                hasExportableRecording: hasCompletedRecording,
                isRealtimeMode: false,
                isAudioActive: isAudioActive,
                errorMessage: activeErrorMessage,
                isPrimaryDisabled: isTranscribingDictation || (!isAudioActive && !canStartRecording),
                primaryAction: {
                    Task {
                        await handleMicrophoneTap()
                    }
                },
                showTranscript: showTranscript,
                saveRecording: prepareAudioExport
            )
        }
        .onChange(of: configuration.fileProvider) { _, _ in
            cancelTranscriptionForProviderChange()
        }
        .onChange(of: configuration.credentialRevision) { _, _ in
            cancelTranscriptionForProviderChange()
        }
        .onDisappear {
            cancelTranscriptionForProviderChange()
        }
    }

    /// Toggles between capturing dictation audio and transcribing the completed recording.
    private func handleMicrophoneTap() async {
        exportErrorMessage = nil

        if recorder.isRecording {
            let recordingURL = recorder.lastRecordingURL
            do {
                if let url = try await recorder.stopRecordingForUpload(), recorder.lastRecordingURL == url {
                    beginDictationTranscription(url)
                } else {
                    startInputPreviewIfAvailable()
                }
            } catch {
                guard recorder.lastRecordingURL == recordingURL else { return }
                recorder.discardRecording()
                dictationError = DemoFailure.message(for: error)
                startInputPreviewIfAvailable()
            }
            return
        }

        guard canStartRecording else {
            dictationError = configuration.fileProvider == .voz
                ? "Download and prepare the VOZ model in Settings before recording local dictation."
                : configuration.missingAPIKeyMessage(for: configuration.fileProvider)
            return
        }

        inputPreview.stop()
        await startDictationRecording()
    }

    /// Requests microphone permission and creates a temporary WAV file for transcription.
    private func startDictationRecording() async {
        do {
            dictationError = nil
            dictationTranscript = nil
            vozResponse = nil
            _ = try await recorder.startRecording()
        } catch {
            dictationError = DemoFailure.message(for: error)
        }
    }

    /// Starts a new dictation request and gives it exclusive ownership of the displayed result.
    private func beginDictationTranscription(_ url: URL) {
        transcriptionTask?.cancel()
        let provider = configuration.fileProvider
        let requestID = UUID()
        activeRequestID = requestID
        transcriptionTask = Task {
            await transcribeDictation(url, provider: provider, requestID: requestID)
        }
    }

    /// Transcribes the locally recorded WAV file with the provider selected when recording stopped.
    private func transcribeDictation(_ url: URL, provider: DemoFileProvider, requestID: UUID) async {
        guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
        guard provider == .voz || configuration.hasAPIKey(for: provider) else {
            recorder.discardRecording()
            dictationError = configuration.missingAPIKeyMessage(for: provider)
            return
        }

        guard provider != .voz || isVozReady else {
            recorder.discardRecording()
            dictationError = "Download and prepare the VOZ model in Settings before transcribing locally."
            return
        }

        isTranscribingDictation = true
        dictationError = nil
        dictationTranscript = nil
        vozResponse = nil
        defer {
            if activeRequestID == requestID {
                isTranscribingDictation = false
                transcriptionTask = nil
                startInputPreviewIfAvailable()
            }
        }

        do {
            try configuration.prepare(speech, for: provider.apiKeyProvider)
            defer {
                if activeRequestID == requestID { configuration.releaseAuthorization(from: speech) }
            }
            if provider == .voz {
                let response = try await speech.transcribeVozAudioFile(file: url)
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                dictationTranscript = response.text
                vozResponse = response
            } else if provider == .elevenLabs, configuration.elevenLabsReturnsSpeakers {
                // The detailed response carries per-word speakers that the plain-text path drops.
                let response = try await speech.transcribeElevenLabsAudioFile(file: url, options: configuration.elevenLabsFileOptions)
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                dictationTranscript = response.speakerLabeledText
            } else if provider == .mistral, configuration.mistralDiarize {
                // The detailed response carries per-segment speakers that the plain-text path drops.
                let response = try await speech.transcribeMistralAudioFile(file: url, options: configuration.mistralFileOptions)
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                dictationTranscript = response.speakerLabeledText
            } else if provider == .fishAudio, configuration.fishAudioReturnsSpeakers {
                // The detailed response carries speaker turns that the plain-text path drops.
                let response = try await speech.transcribeFishAudioAudioFile(file: url, options: configuration.fishAudioFileOptions)
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                dictationTranscript = response.speakerLabeledText
            } else if let speechProvider = provider.speechProvider {
                let response = try await speech.transcribeAudioFile(
                    provider: speechProvider,
                    file: url,
                    options: configuration.fileOptions(for: provider)
                )
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                dictationTranscript = response
            }
            if ownsCurrentResult(for: provider, requestID: requestID) { recorder.retainForExport() }
        } catch {
            guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
            recorder.discardRecording()
            dictationError = DemoFailure.message(for: error)
        }
    }

    /// Presents the latest dictation transcript in the shared transcript sheet.
    private func showTranscript() {
        presentedTranscript = DemoTranscript(text: displayedTranscript, vozResponse: vozResponse)
    }

    /// Restarts the passive input meter when the recording/upload flow releases the audio session.
    private func startInputPreviewIfAvailable() {
        guard !isAudioActive else { return }
        inputPreview.startIfAuthorized()
    }

    private var canStartRecording: Bool {
        configuration.fileProvider == .voz ? isVozReady : hasSelectedProviderKey
    }

    private var isVozReady: Bool {
        if case .ready = speech.vozModelState { return true }
        return false
    }

    private func ownsCurrentResult(for provider: DemoFileProvider, requestID: UUID) -> Bool {
        !Task.isCancelled && activeRequestID == requestID && configuration.fileProvider == provider
    }

    /// Drops all state belonging to a provider that is no longer selected.
    private func cancelTranscriptionForProviderChange() {
        transcriptionTask?.cancel()
        recorder.discardRecording()
        configuration.releaseAuthorization(from: speech)
        transcriptionTask = nil
        activeRequestID = nil
        isTranscribingDictation = false
        dictationTranscript = nil
        vozResponse = nil
        dictationError = nil
    }
}
