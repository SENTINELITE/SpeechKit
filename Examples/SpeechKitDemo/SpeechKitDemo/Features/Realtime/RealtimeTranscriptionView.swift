import SpeechKit
import SwiftUI

/// A focused sample for SpeechKit realtime microphone transcription.
struct RealtimeTranscriptionView: View {
    @Environment(\.speechService) private var speech

    @Bindable var configuration: DemoConfiguration
    let inputPreview: DemoInputPreviewMonitor
    @Binding var presentedTranscript: DemoTranscript?
    @Binding var wordEmitterResetID: UUID
    @Binding var exportErrorMessage: String?
    let prepareAudioExport: () -> Void

    private var displayedTranscript: String {
        guard configuration.realtimeProvider == .elevenLabs,
              speech.transcriptEntries.contains(where: { $0.speaker != nil }) else {
            return [speech.transcriptText, speech.partialTranscriptText]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
        return [speech.transcriptEntries.speakerLabeledText, partialSpeakerText ?? speech.partialTranscriptText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    /// The live partial prefixed with its draft speaker, while diarization resolves it.
    private var partialSpeakerText: String? {
        guard let entry = speech.partialTranscriptEntry, !entry.text.isEmpty,
              let speaker = entry.speaker ?? entry.words.last(where: { $0.speaker != nil })?.speaker else {
            return nil
        }
        return "\(speaker): \(entry.text)"
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

    private var realtimeProviderTitle: String {
        if configuration.realtimeProvider == .openAI {
            return "OpenAI · \(configuration.openAIRealtimeTranscriptionModel.rawValue)"
        }
        return configuration.realtimeProvider.title
    }

    private var hasExportableRecording: Bool {
        !isAudioActive && speech.realtimeRecordingData != nil
    }

    private var primaryControlTitle: String {
        if !hasSelectedProviderKey && !isAudioActive {
            return configuration.isRelayEnabled ? "Relay Authorization Required" : "API Key Required"
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
        return speech.lastError.map { DemoFailure.message(for: $0) } ?? exportErrorMessage
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
                providerTitle: realtimeProviderTitle,
                iconName: microphoneIconName,
                voiceLevel: voiceLevel,
                voiceState: voiceState,
                actionTitle: primaryControlTitle,
                isActionDisabled: !isAudioActive && !hasSelectedProviderKey,
                action: {
                    Task {
                        await handleMicrophoneTap()
                    }
                }
            )

            if let turnProbability = speech.realtimeTurnProbability, isAudioActive {
                VStack {
                    Spacer()
                    turnProbabilityIndicator(turnProbability)
                        .padding(.bottom, 150)
                }
            }

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
        exportErrorMessage = nil

        if speech.realtimeConnectionState.isWorking {
            await speech.stopListening()
            resetRealtimeWords()
            startInputPreviewIfAvailable()
            return
        }

        guard hasSelectedProviderKey else { return }
        do {
            try configuration.prepare(speech, for: configuration.realtimeProvider.apiKeyProvider)
        } catch {
            exportErrorMessage = DemoFailure.message(for: error)
            return
        }
        inputPreview.stop(deactivateAudioSession: false)
        speech.clearTranscript()
        resetRealtimeWords()
        await speech.startListening(provider: configuration.realtimeProvider.speechProvider)
    }

    /// Shows ElevenLabs' confidence that the open turn has ended while a session runs.
    private func turnProbabilityIndicator(_ value: Double) -> some View {
        HStack(spacing: 8) {
            Text("Turn")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: min(max(value, 0), 1))
                .frame(width: 72)
            Text(value, format: .percent.precision(.fractionLength(0)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassSurface(cornerRadius: 14)
    }

    /// Presents the current realtime transcript in the shared transcript sheet.
    private func showTranscript() {
        presentedTranscript = DemoTranscript(text: displayedTranscript)
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
