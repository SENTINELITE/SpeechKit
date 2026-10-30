import SpeechKit
import SpeechKitVoz
import SwiftUI
import UniformTypeIdentifiers

/// A standalone sample for importing an existing audio or movie file and sending it to SpeechKit.
struct FileTranscriptionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.speechService) private var speech

    @Bindable var configuration: DemoConfiguration

    @State private var isImporterPresented = false
    @State private var selectedFile: URL?
    @State private var transcript: String?
    @State private var vozResponse: VozFileTranscriptionResponse?
    @State private var errorMessage: String?
    @State private var isTranscribing = false
    @State private var startedAt: Date?
    @State private var activeTimeout: TimeInterval?
    @State private var transcriptionTask: Task<Void, Never>?
    @State private var activeRequestID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                providerSection
                audioFileSection
                resultSection
            }
            .navigationTitle("File Transcription")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
            .fileImporter(
                isPresented: $isImporterPresented,
                allowedContentTypes: [.audio, .movie],
                allowsMultipleSelection: false,
                onCompletion: handleImportResult
            )
            .onChange(of: configuration.fileProvider) { _, _ in
                cancelTranscriptionForProviderChange()
            }
            .onDisappear {
                cancelTranscriptionForProviderChange()
            }
        }
    }

    /// Selects the provider and exposes the shared file-option controls for this workflow.
    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: $configuration.fileProvider) {
                ForEach(DemoFileProvider.allCases) { provider in
                    Text(provider.title)
                        .tag(provider)
                        .disabled(provider.requiresAPIKey && !configuration.hasAPIKey(for: provider))
                }
            }
            .pickerStyle(.menu)

            if configuration.fileProvider.requiresAPIKey && !configuration.hasAPIKey(for: configuration.fileProvider) {
                Label(configuration.missingAPIKeyMessage(for: configuration.fileProvider), systemImage: "key.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if configuration.fileProvider == .voz, !isVozReady {
                vozPreparationControls
            }

            FileProviderOptionsView(configuration: configuration)
        }
    }

    @ViewBuilder
    private var vozPreparationControls: some View {
        switch speech.vozModelState {
        case .unprepared:
            Label("Prepare the VOZ model before transcribing locally.", systemImage: "arrow.down.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Prepare VOZ model", action: speech.prepareVozModelInBackground)
        case .checkingCache:
            Label("Checking the cached VOZ model…", systemImage: "magnifyingglass.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView("Verifying model files…")
            Button("Cancel preparation", role: .cancel, action: speech.releaseVozModel)
        case .downloading:
            Label("Downloading the VOZ model…", systemImage: "arrow.down.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView(value: speech.vozModelDownloadProgress)
            LabeledContent(
                "Download",
                value: speech.vozModelDownloadProgress,
                format: .percent.precision(.fractionLength(0))
            )
            Button("Cancel preparation", role: .cancel, action: speech.releaseVozModel)
        case .loading:
            Label("Loading the VOZ model…", systemImage: "gearshape.2")
                .font(.caption)
                .foregroundStyle(.secondary)
            ProgressView("Loading model…")
            Button("Cancel preparation", role: .cancel, action: speech.releaseVozModel)
        case .ready:
            EmptyView()
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .textSelection(.enabled)
            Button("Retry VOZ preparation", action: speech.prepareVozModelInBackground)
        }
    }

    /// Lets a reader inspect the minimum code needed to pick a file and call transcription.
    private var audioFileSection: some View {
        Section("Audio File") {
            Button {
                isImporterPresented = true
            } label: {
                Label("Select audio file", systemImage: "waveform.badge.plus")
            }
            .disabled(isTranscribing)

            if let selectedFile {
                LabeledContent("Selected", value: selectedFile.lastPathComponent)

                Button {
                    beginTranscription(of: selectedFile)
                } label: {
                    Label("Transcribe selected file", systemImage: "text.bubble")
                }
                .disabled(isTranscribing || !canTranscribe)
            }
        }
    }

    /// Displays upload progress, errors, or the provider transcript.
    private var resultSection: some View {
        Section("Result") {
            if isTranscribing {
                if configuration.fileProvider.isOnDevice {
                    DemoLocalTranscriptionStatusView(startedAt: startedAt)
                } else {
                    DemoUploadStatusView(
                        providerName: configuration.fileProvider.title,
                        startedAt: startedAt,
                        timeoutInterval: activeTimeout
                    )
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            if let transcript {
                Text(transcript)
                    .textSelection(.enabled)

                if let vozResponse {
                    VozTranscriptionDetailView(response: vozResponse)
                }
            } else if !isTranscribing {
                Text("No transcription yet")
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Stores the imported file URL and clears stale result state.
    private func handleImportResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFile = urls.first
            transcript = nil
            vozResponse = nil
            errorMessage = nil
        case .failure(let error):
            errorMessage = "Failed to import audio: \(error.localizedDescription)"
        }
    }

    /// Starts a new request and gives it exclusive ownership of this workflow's result surface.
    private func beginTranscription(of url: URL) {
        transcriptionTask?.cancel()
        let provider = configuration.fileProvider
        let requestID = UUID()
        activeRequestID = requestID
        transcriptionTask = Task {
            await transcribe(url, provider: provider, requestID: requestID)
        }
    }

    /// Calls SpeechKit with a security-scoped URL so files picked outside the sandbox remain readable.
    private func transcribe(_ url: URL, provider: DemoFileProvider, requestID: UUID) async {
        guard provider == .voz || configuration.hasAPIKey(for: provider) else {
            errorMessage = configuration.missingAPIKeyMessage(for: configuration.fileProvider)
            return
        }

        guard provider != .voz || isVozReady else {
            errorMessage = "Download and prepare the VOZ model in Settings before transcribing locally."
            return
        }

        configuration.apply(to: speech)
        isTranscribing = true
        startedAt = Date()
        activeTimeout = configuration.timeoutInterval(for: provider)
        errorMessage = nil
        transcript = nil
        vozResponse = nil
        defer {
            if activeRequestID == requestID {
                isTranscribing = false
                startedAt = nil
                activeTimeout = nil
                transcriptionTask = nil
            }
        }

        do {
            if provider == .voz {
                let response = try await speech.transcribeVozAudioFile(securityScopedURL: url)
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                transcript = response.text
                vozResponse = response
            } else if provider == .mistral, configuration.mistralDiarize {
                // The detailed response carries per-segment speakers that the plain-text path drops.
                let response = try await speech.transcribeMistralAudioFile(securityScopedURL: url, options: configuration.mistralFileOptions)
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                transcript = response.speakerLabeledText
            } else if let speechProvider = provider.speechProvider {
                let response = try await speech.transcribeAudioFile(
                    provider: speechProvider,
                    securityScopedURL: url,
                    options: configuration.fileOptions(for: provider)
                )
                guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
                transcript = response
            }
        } catch {
            guard ownsCurrentResult(for: provider, requestID: requestID) else { return }
            errorMessage = error.localizedDescription
        }
    }

    /// Invalidates an in-flight result before a provider change can display stale content.
    private func cancelTranscriptionForProviderChange() {
        transcriptionTask?.cancel()
        transcriptionTask = nil
        activeRequestID = nil
        isTranscribing = false
        startedAt = nil
        activeTimeout = nil
        transcript = nil
        vozResponse = nil
        errorMessage = nil
    }

    private var canTranscribe: Bool {
        configuration.fileProvider == .voz ? isVozReady : configuration.hasAPIKey(for: configuration.fileProvider)
    }

    private var isVozReady: Bool {
        if case .ready = speech.vozModelState { return true }
        return false
    }

    private func ownsCurrentResult(for provider: DemoFileProvider, requestID: UUID) -> Bool {
        !Task.isCancelled && activeRequestID == requestID && configuration.fileProvider == provider
    }
}
