import SpeechKit
import SwiftUI

/// A focused sample for recording local WAV audio and uploading it through SpeechKit file transcription.
struct RecordedUploadView: View {
    @Environment(\.speechService) private var speech

    @Bindable var configuration: DemoConfiguration
    let recorder: DemoAudioRecorder
    let inputPreview: DemoInputPreviewMonitor
    @Binding var transcriptSheetText: String
    @Binding var isTranscriptPresented: Bool
    @Binding var exportErrorMessage: String?
    let prepareAudioExport: () -> Void

    @State private var isUploadingDictation = false
    @State private var dictationTranscript: String?
    @State private var dictationError: String?

    private var isAudioActive: Bool {
        recorder.isRecording || isUploadingDictation
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
        !recorder.isRecording && !isUploadingDictation && recorder.lastRecordingURL != nil
    }

    private var microphoneIconName: String {
        recorder.isRecording ? "stop.circle.fill" : "record.circle"
    }

    private var primaryControlTitle: String {
        if !hasSelectedProviderKey && !isAudioActive {
            return "API Key Required"
        }
        if recorder.isRecording {
            return "Stop Recording"
        }
        if isUploadingDictation {
            return "Uploading"
        }
        return "Record"
    }

    private var activeErrorMessage: String? {
        if !hasSelectedProviderKey && !isAudioActive {
            return configuration.missingAPIKeyMessage(for: configuration.fileProvider)
        }
        return dictationError ?? exportErrorMessage
    }

    var body: some View {
        ZStack {
            DemoBackground(level: voiceLevel, state: voiceState)

            DemoVoiceStage(
                title: "Record, upload, transcribe",
                providerTitle: configuration.fileProvider.title,
                iconName: microphoneIconName,
                voiceLevel: voiceLevel,
                voiceState: voiceState
            )

            DemoControlDock(
                primaryTitle: primaryControlTitle,
                primaryIcon: microphoneIconName,
                transcript: displayedTranscript,
                hasExportableRecording: hasCompletedRecording,
                isRealtimeMode: false,
                isAudioActive: isAudioActive,
                errorMessage: activeErrorMessage,
                isPrimaryDisabled: isUploadingDictation || (!isAudioActive && !hasSelectedProviderKey),
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

    /// Toggles between capturing dictation audio and uploading the completed recording.
    private func handleMicrophoneTap() async {
        configuration.apply(to: speech)
        exportErrorMessage = nil

        if recorder.isRecording {
            do {
                if let url = try await recorder.stopRecordingForUpload() {
                    await uploadDictation(url)
                } else {
                    startInputPreviewIfAvailable()
                }
            } catch {
                dictationError = error.localizedDescription
                startInputPreviewIfAvailable()
            }
            return
        }

        guard hasSelectedProviderKey else {
            dictationError = configuration.missingAPIKeyMessage(for: configuration.fileProvider)
            return
        }

        inputPreview.stop()
        await startDictationRecording()
    }

    /// Requests microphone permission and creates a temporary WAV file for the upload sample.
    private func startDictationRecording() async {
        do {
            dictationError = nil
            dictationTranscript = nil
            _ = try await recorder.startRecording()
        } catch {
            dictationError = error.localizedDescription
        }
    }

    /// Uploads the recorded WAV file using the selected file-transcription provider and option set.
    private func uploadDictation(_ url: URL) async {
        guard hasSelectedProviderKey else {
            dictationError = configuration.missingAPIKeyMessage(for: configuration.fileProvider)
            return
        }

        isUploadingDictation = true
        dictationError = nil
        dictationTranscript = nil
        defer {
            isUploadingDictation = false
            startInputPreviewIfAvailable()
        }

        do {
            dictationTranscript = try await speech.transcribeAudioFile(
                provider: configuration.fileProvider.speechProvider,
                file: url,
                options: configuration.fileOptions(for: configuration.fileProvider)
            )
        } catch {
            dictationError = error.localizedDescription
        }
    }

    /// Presents the latest uploaded dictation transcript in the shared transcript sheet.
    private func showTranscript() {
        transcriptSheetText = displayedTranscript
        isTranscriptPresented = true
    }

    /// Restarts the passive input meter when the recording/upload flow releases the audio session.
    private func startInputPreviewIfAvailable() {
        guard !isAudioActive else { return }
        inputPreview.startIfAuthorized()
    }
}
