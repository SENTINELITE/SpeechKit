import SpeechKit
import SpeechKitVoz
import SwiftUI

/// The unified SpeechKit sample screen that wires shared demo state into focused workflow views.
struct ContentView: View {
    @Environment(\.speechService) private var directSpeech

    @State private var configuration = DemoConfiguration()
    @State private var recorder = DemoAudioRecorder()
    @State private var inputPreview = DemoInputPreviewMonitor()
    @State private var isRealtimeMode = true
    @State private var isFileSheetPresented = false
    @State private var isSettingsPresented = false
    @State private var isAudioExporterPresented = false
    @State private var presentedTranscript: DemoTranscript?
    @State private var vozResponse: VozFileTranscriptionResponse?
    @State private var wordEmitterResetID = UUID()
    @State private var exportedAudio = RecordedAudioFileDocument()
    @State private var exportedAudioFilename = "speechkit-dictation.wav"
    @State private var audioExportError: String?

    private var speech: SpeechService { configuration.relayService ?? directSpeech }

    var body: some View {
        NavigationStack {
            ZStack {
                if isRealtimeMode {
                    RealtimeTranscriptionView(
                        configuration: configuration,
                        inputPreview: inputPreview,
                        presentedTranscript: $presentedTranscript,
                        wordEmitterResetID: $wordEmitterResetID,
                        exportErrorMessage: $audioExportError,
                        prepareAudioExport: prepareAudioExport
                    )
                } else {
                    RecordedUploadView(
                        configuration: configuration,
                        recorder: recorder,
                        inputPreview: inputPreview,
                        presentedTranscript: $presentedTranscript,
                        vozResponse: $vozResponse,
                        exportErrorMessage: $audioExportError,
                        prepareAudioExport: prepareAudioExport
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
                            Picker("Mode", selection: $isRealtimeMode) {
                                Text("Realtime").tag(true)
                                Text("Dictation").tag(false)
                            }
                        }

                        if isRealtimeMode {
                            RealtimeProviderPicker(configuration: configuration)
                        } else {
                            FileProviderPicker(configuration: configuration, title: "Dictation Provider")
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
            .onChange(of: isRealtimeMode) { _, newValue in
                handleModeChange(isRealtimeMode: newValue)
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
            .sheet(item: $presentedTranscript) { transcript in
                TranscriptSheet(transcript: transcript.text, vozResponse: transcript.vozResponse)
            }
            .onChange(of: isAudioExporterPresented) { _, presented in
                if !presented { clearAudioExport() }
            }
            .fileExporter(
                isPresented: $isAudioExporterPresented,
                document: exportedAudio,
                contentType: .wav,
                defaultFilename: exportedAudioFilename,
                onCompletion: handleAudioExportResult
            )
        }
        .environment(\.speechService, speech)
    }

    /// Refreshes nonsecret key status and starts the idle input preview when possible.
    private func configureDemo() {
        applyConfiguration()
        startInputPreviewIfAvailable()
    }

    /// Stops microphone work owned by the demo when the screen leaves the hierarchy.
    private func stopDemo() {
        inputPreview.stop()
        recorder.discardRecording()
        exportedAudio = RecordedAudioFileDocument()
        Task { await configuration.resetAuthorization(in: speech) }
    }

    /// Reconciles audio capture state when the unified sample switches between realtime and recorded-upload modes.
    private func handleModeChange(isRealtimeMode: Bool) {
        resetRealtimeWords()
        audioExportError = nil
        vozResponse = nil

        Task {
            if isRealtimeMode {
                recorder.discardRecording()
                startInputPreviewIfAvailable()
            } else {
                inputPreview.stop()
                await configuration.resetAuthorization(in: speech)
                startInputPreviewIfAvailable()
            }
        }
    }

    /// Refreshes key metadata after settings close without loading saved values.
    private func applyConfiguration() {
        configuration.refreshKeyStatus()
    }

    /// Opens the standalone file-import transcription workflow.
    private func showFileTranscription() {
        inputPreview.stop()
        recorder.discardRecording()
        Task {
            await configuration.resetAuthorization(in: speech)
            isFileSheetPresented = true
        }
    }

    /// Opens provider keys and default option controls.
    private func showSettings() {
        inputPreview.stop()
        recorder.discardRecording()
        Task {
            await configuration.resetAuthorization(in: speech)
            isSettingsPresented = true
        }
    }

    /// Starts the passive microphone meter unless a workflow already owns the audio session.
    private func startInputPreviewIfAvailable() {
        let isAudioActive = isRealtimeMode ? speech.realtimeConnectionState.isWorking : recorder.isRecording
        guard !isAudioActive else { return }
        inputPreview.startIfAuthorized()
    }

    /// Restarts the realtime session after a provider change so the active WebSocket uses the selected configuration.
    private func restartRealtimeIfNeeded() async {
        guard isRealtimeMode, speech.realtimeConnectionState.isWorking else { return }
        await configuration.resetAuthorization(in: speech)
        do {
            try configuration.prepare(speech, for: configuration.realtimeProvider.apiKeyProvider)
        } catch {
            audioExportError = DemoFailure.message(for: error)
            return
        }
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
        if let realtimeRecordingData = speech.realtimeRecordingData, isRealtimeMode || recorder.lastRecordingURL == nil {
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
            audioExportError = "Failed to prepare recording. \(DemoFailure.message(for: error))"
        }
    }

    /// Routes exporter failures back into the active workflow's error surface.
    private func handleAudioExportResult(_ result: Result<URL, Error>) {
        defer { clearAudioExport() }
        if case .failure(let error) = result {
            audioExportError = "Failed to save recording. \(DemoFailure.message(for: error))"
        }
    }
    private func clearAudioExport() {
        exportedAudio = RecordedAudioFileDocument()
        speech.discardRecording()
        recorder.discardRecording()
    }
}

#Preview {
    ContentView()
        .environment(\.speechService, SpeechService())
}
