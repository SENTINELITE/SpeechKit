import SpeechKit
import SwiftUI

/// The workflow shown by the unified SpeechKit sample screen.
enum DemoMode: String, CaseIterable, Identifiable {
    /// Streaming microphone transcription.
    case realtime
    /// Record-then-upload transcription.
    case dictation
    /// Full-duplex speech-to-speech conversation.
    case conversation

    var id: Self { self }

    /// The display name shown in the toolbar mode picker.
    var title: String {
        switch self {
        case .realtime: "Realtime"
        case .dictation: "Dictation"
        case .conversation: "Conversation"
        }
    }
}

/// The unified SpeechKit sample screen that wires shared demo state into focused workflow views.
struct ContentView: View {
    @Environment(\.speechService) private var speech

    @State private var configuration = DemoConfiguration()
    @State private var recorder = DemoAudioRecorder()
    @State private var inputPreview = DemoInputPreviewMonitor()
    @State private var mode: DemoMode = .realtime
    @State private var isFileSheetPresented = false
    @State private var isSettingsPresented = false
    @State private var isTranscriptPresented = false
    @State private var isAudioExporterPresented = false
    @State private var transcriptSheetText = ""
    @State private var wordEmitterResetID = UUID()
    @State private var exportedAudio = RecordedAudioFileDocument()
    @State private var exportedAudioFilename = "speechkit-dictation.wav"
    @State private var audioExportError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                switch mode {
                case .realtime:
                    RealtimeTranscriptionView(
                        configuration: configuration,
                        inputPreview: inputPreview,
                        transcriptSheetText: $transcriptSheetText,
                        isTranscriptPresented: $isTranscriptPresented,
                        wordEmitterResetID: $wordEmitterResetID,
                        exportErrorMessage: $audioExportError,
                        prepareAudioExport: prepareAudioExport
                    )
                case .dictation:
                    RecordedUploadView(
                        configuration: configuration,
                        recorder: recorder,
                        inputPreview: inputPreview,
                        transcriptSheetText: $transcriptSheetText,
                        isTranscriptPresented: $isTranscriptPresented,
                        exportErrorMessage: $audioExportError,
                        prepareAudioExport: prepareAudioExport
                    )
                case .conversation:
                    ConversationView(
                        configuration: configuration,
                        inputPreview: inputPreview,
                        transcriptSheetText: $transcriptSheetText,
                        isTranscriptPresented: $isTranscriptPresented
                    )
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button(action: showFileTranscription) {
                        Label("File Transcription", systemImage: "waveform.badge.plus")
                            .labelStyle(.iconOnly)
                    }
                    .glassToolbarButton()

                    Menu {
                        Section("Mode") {
                            Picker("Mode", selection: $mode) {
                                ForEach(DemoMode.allCases) { demoMode in
                                    Text(demoMode.title).tag(demoMode)
                                }
                            }
                        }

                        switch mode {
                        case .realtime:
                            RealtimeProviderPicker(configuration: configuration)
                        case .dictation:
                            FileProviderPicker(configuration: configuration, title: "Dictation Provider")
                        case .conversation:
                            Section("Conversation Provider") {
                                Text("OpenAI GPT-Live")
                            }
                        }

                        Section {
                            Button(action: showSettings) {
                                Label("Settings", systemImage: "gearshape")
                            }
                        }
                    } label: {
                        Label("Demo Controls", systemImage: "slider.horizontal.3")
                            .labelStyle(.iconOnly)
                    }
                    .glassToolbarButton()
                }
            }
            .onAppear(perform: configureDemo)
            .onDisappear(perform: stopDemo)
            .onChange(of: mode) { oldValue, newValue in
                handleModeChange(from: oldValue, to: newValue)
            }
            .onChange(of: configuration.realtimeProvider) { _, _ in
                Task {
                    await restartRealtimeIfNeeded()
                }
            }
            .sheet(isPresented: $isFileSheetPresented, onDismiss: applyConfiguration) {
                FileTranscriptionView(configuration: configuration)
            }
            .sheet(isPresented: $isSettingsPresented, onDismiss: applyConfiguration) {
                SettingsSheet(configuration: configuration)
            }
            .sheet(isPresented: $isTranscriptPresented) {
                TranscriptSheet(transcript: transcriptSheetText)
            }
            .fileExporter(
                isPresented: $isAudioExporterPresented,
                document: exportedAudio,
                contentType: .wav,
                defaultFilename: exportedAudioFilename,
                onCompletion: handleAudioExportResult
            )
        }
    }

    /// Applies the saved provider configuration to the shared `SpeechService` and starts the idle input preview when possible.
    private func configureDemo() {
        applyConfiguration()
        startInputPreviewIfAvailable()
    }

    /// Stops microphone work owned by the demo when the screen leaves the hierarchy.
    private func stopDemo() {
        inputPreview.stop()
        _ = recorder.stopRecording()
        Task {
            await speech.stopListening()
            await speech.endConversation()
        }
    }

    /// Reconciles audio capture state when the unified sample switches workflows.
    ///
    /// Leaving conversation mode ends the GPT-Live session immediately, because
    /// the provider bills for every second of streamed audio.
    private func handleModeChange(from oldMode: DemoMode, to newMode: DemoMode) {
        resetRealtimeWords()
        audioExportError = nil

        Task {
            if oldMode == .conversation {
                await speech.endConversation()
            }

            switch newMode {
            case .realtime:
                _ = recorder.stopRecording()
            case .dictation:
                inputPreview.stop()
                await speech.stopListening()
            case .conversation:
                _ = recorder.stopRecording()
                await speech.stopListening()
            }

            startInputPreviewIfAvailable()
        }
    }

    /// Reapplies provider settings after sheets mutate persisted configuration.
    private func applyConfiguration() {
        configuration.apply(to: speech)
    }

    /// Opens the standalone file-import transcription workflow.
    private func showFileTranscription() {
        isFileSheetPresented = true
    }

    /// Opens provider keys and default option controls.
    private func showSettings() {
        isSettingsPresented = true
    }

    /// Starts the passive microphone meter unless a workflow already owns the audio session.
    private func startInputPreviewIfAvailable() {
        let isAudioActive: Bool = switch mode {
        case .realtime: speech.realtimeConnectionState.isWorking
        case .dictation: recorder.isRecording
        case .conversation: speech.conversationState.isWorking
        }
        guard !isAudioActive else { return }
        inputPreview.startIfAuthorized()
    }

    /// Restarts the realtime session after a provider change so the active WebSocket uses the selected configuration.
    private func restartRealtimeIfNeeded() async {
        guard mode == .realtime, speech.realtimeConnectionState.isWorking else { return }
        await speech.stopListening()
        applyConfiguration()
        speech.clearTranscript()
        resetRealtimeWords()
        await speech.startListening(provider: configuration.realtimeProvider.speechProvider)
    }

    /// Clears transient word-emitter state without touching the committed transcript.
    private func resetRealtimeWords() {
        wordEmitterResetID = UUID()
    }

    /// Prepares either the realtime WAV capture or the last recorded-upload file for the system file exporter.
    private func prepareAudioExport() {
        if let realtimeRecordingData = speech.realtimeRecordingData, mode != .dictation || recorder.lastRecordingURL == nil {
            exportedAudio = RecordedAudioFileDocument(data: realtimeRecordingData)
            exportedAudioFilename = "speechkit-realtime-\(UUID().uuidString).wav"
            audioExportError = nil
            isAudioExporterPresented = true
            return
        }

        guard let url = recorder.lastRecordingURL else { return }
        do {
            exportedAudio = RecordedAudioFileDocument(data: try Data(contentsOf: url))
            exportedAudioFilename = url.lastPathComponent
            audioExportError = nil
            isAudioExporterPresented = true
        } catch {
            audioExportError = "Failed to prepare recording: \(error.localizedDescription)"
        }
    }

    /// Routes exporter failures back into the active workflow's error surface.
    private func handleAudioExportResult(_ result: Result<URL, Error>) {
        if case .failure(let error) = result {
            audioExportError = "Failed to save recording: \(error.localizedDescription)"
        }
    }
}

#Preview {
    ContentView()
        .environment(\.speechService, SpeechService())
}
