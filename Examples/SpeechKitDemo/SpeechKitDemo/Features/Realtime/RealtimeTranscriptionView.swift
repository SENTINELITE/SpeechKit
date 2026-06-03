import SpeechKit
import SwiftUI

/// A focused sample for SpeechKit realtime microphone transcription.
struct RealtimeTranscriptionView: View {
    @Environment(\.speechService) private var speech

    @Bindable var configuration: DemoConfiguration
    let inputPreview: DemoInputPreviewMonitor
    @Binding var transcriptSheetText: String
    @Binding var isTranscriptPresented: Bool
    @Binding var wordEmitterResetID: UUID
    @Binding var exportErrorMessage: String?
    let prepareAudioExport: () -> Void

    private var displayedTranscript: String {
        [speech.transcriptText, speech.partialTranscriptText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var isAudioActive: Bool {
        speech.realtimeConnectionState.isWorking
    }

    private var voiceLevel: Double {
        isAudioActive ? speech.realtimeAudioLevel : inputPreview.currentLevel
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

    private var hasSelectedProviderKey: Bool {
        configuration.hasAPIKey(for: configuration.realtimeProvider)
    }

    private var hasExportableRecording: Bool {
        !isAudioActive && speech.realtimeRecordingData != nil
    }

    private var primaryControlTitle: String {
        if !hasSelectedProviderKey && !isAudioActive {
            return "API Key Required"
        }
        return speech.realtimeConnectionState.isWorking ? "Stop Speaking" : "Start Speaking"
    }

    private var microphoneIconName: String {
        speech.realtimeConnectionState.isWorking ? "waveform.circle.fill" : "mic.fill"
    }

    private var activeErrorMessage: String? {
        if !hasSelectedProviderKey && !isAudioActive {
            return configuration.missingAPIKeyMessage(for: configuration.realtimeProvider)
        }
        return speech.lastError?.localizedDescription ?? exportErrorMessage
    }

    var body: some View {
        ZStack {
            DemoBackground(level: voiceLevel, state: voiceState)

            RealtimeWordEmitterView(
                transcript: displayedTranscript,
                isActive: speech.realtimeConnectionState.isWorking,
                level: voiceLevel,
                resetID: wordEmitterResetID
            )

            DemoVoiceStage(
                title: "Realtime transcription",
                providerTitle: configuration.realtimeProvider.title,
                iconName: microphoneIconName,
                voiceLevel: voiceLevel,
                voiceState: voiceState
            )

            DemoControlDock(
                primaryTitle: primaryControlTitle,
                primaryIcon: microphoneIconName,
                transcript: displayedTranscript,
                hasExportableRecording: hasExportableRecording,
                isRealtimeMode: true,
                isAudioActive: isAudioActive,
                errorMessage: activeErrorMessage,
                isPrimaryDisabled: !isAudioActive && !hasSelectedProviderKey,
                primaryAction: {
                    Task {
                        await handleMicrophoneTap()
                    }
                },
                showTranscript: showTranscript,
                saveRecording: prepareAudioExport
            )
        }
    }

    /// Starts or stops the realtime SpeechKit provider while keeping the passive preview out of the audio session.
    private func handleMicrophoneTap() async {
        configuration.apply(to: speech)
        exportErrorMessage = nil

        if speech.realtimeConnectionState.isWorking {
            await speech.stopListening()
            resetRealtimeWords()
            startInputPreviewIfAvailable()
            return
        }

        guard hasSelectedProviderKey else { return }
        inputPreview.stop(deactivateAudioSession: false)
        speech.clearTranscript()
        resetRealtimeWords()
        await speech.startListening(provider: configuration.realtimeProvider.speechProvider)
    }

    /// Presents the current realtime transcript in the shared transcript sheet.
    private func showTranscript() {
        transcriptSheetText = displayedTranscript
        isTranscriptPresented = true
    }

    /// Restarts the passive meter after realtime capture releases the microphone.
    private func startInputPreviewIfAvailable() {
        guard !isAudioActive else { return }
        inputPreview.startIfAuthorized()
    }

    /// Forces the decorative word emitter to start a new visual run.
    private func resetRealtimeWords() {
        wordEmitterResetID = UUID()
    }
}
